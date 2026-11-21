import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:shi_wu_ji/constants/app_colors.dart';
import 'package:shi_wu_ji/models/category.dart';
import 'package:shi_wu_ji/models/item.dart';
import 'package:shi_wu_ji/models/storage.dart';
import 'package:shi_wu_ji/providers/category_dict_provider.dart';
import 'package:shi_wu_ji/providers/category_provider.dart';
import 'package:shi_wu_ji/providers/item_providers.dart';
import 'package:shi_wu_ji/providers/storage_providers.dart';
import 'package:shi_wu_ji/services/description_parser.dart';
import 'package:shi_wu_ji/services/photo_service.dart';
import 'package:shi_wu_ji/widgets/emoji_text.dart';
import 'package:shi_wu_ji/widgets/location_picker_sheet.dart';
import 'package:shi_wu_ji/widgets/toast_utils.dart';

/// 智能录入页：拍照（可选）+ 一句话描述 → 内置规则解析 → 确认卡片 → 入库。
///
/// 解析由 [DescriptionParser.parseAll] 完成（内置关键词/正则规则，不调用外部 AI）：
/// - 支持一句话多件物品（"客厅有纸巾和电池"按连词切分，位置自动继承）；
/// - 解析出的房间/柜体若不存在，保存时按「主柜体 / 主区域」级联自动创建；
/// - 未识别位置时自动预选上次使用的位置（常用位置记忆）；
/// - 同名且同位置的物品入库时询问"合并数量 / 仍新建"；
/// - 支持语音输入（speech_to_text，平台不支持时隐藏麦克风按钮）；
/// - 照片默认来源（拍照/相册）可设置并持久化。
class SmartAddPage extends ConsumerStatefulWidget {
  const SmartAddPage({super.key});

  @override
  ConsumerState<SmartAddPage> createState() => _SmartAddPageState();
}

class _SmartAddPageState extends ConsumerState<SmartAddPage> {
  // ── 照片默认来源（用户可设置，持久化到 SharedPreferences） ──
  static const String _prefPhotoSourceKey = 'smart_add_default_photo_source';
  String _defaultPhotoSource = 'camera'; // 'camera' | 'gallery'

  // ── 常用位置记忆（上次成功入库的位置） ──
  static const String _prefLastLocationKey = 'smart_add_last_location';
  Map<String, String?>? _lastLocationCache;

  // ── 描述输入与解析 ──
  final _descController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _parseDebounce;

  // 多件物品草稿（每件一张可编辑卡片）
  List<_ItemDraft> _drafts = [];

  // ── 位置 ──
  /// 用户手动选择的位置节点（优先于解析结果）
  StorageLocationNode? _selectedNode;
  _LocationPlan? _plan;

  // ── 照片 ──
  final List<PhotoEntry> _photos = [];
  bool _isPicking = false;

  // ── 语音 ──
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // ── 保存 ──
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _descController.addListener(_onDescChanged);
    _initSpeech();
    _loadPhotoSourcePref();
    _loadLastLocation();
  }

  @override
  void dispose() {
    _parseDebounce?.cancel();
    _descController.removeListener(_onDescChanged);
    _descController.dispose();
    _scrollController.dispose();
    _disposeDrafts();
    if (_isListening) {
      _speech.stop();
    }
    super.dispose();
  }

  void _disposeDrafts() {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts = [];
  }

  // ==================== 照片默认来源 ====================
  Future<void> _loadPhotoSourcePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _defaultPhotoSource =
            prefs.getString(_prefPhotoSourceKey) ?? _defaultPhotoSource;
      });
    } catch (_) {}
  }

  Future<void> _setDefaultPhotoSource(String value) async {
    setState(() => _defaultPhotoSource = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPhotoSourceKey, value);
    } catch (_) {}
  }

  // ==================== 常用位置记忆 ====================
  Future<void> _loadLastLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefLastLocationKey);
      if (raw == null || !mounted) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        setState(() {
          _lastLocationCache = {
            'slotId': decoded['slotId']?.toString(),
            'pathLabel': decoded['pathLabel']?.toString(),
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLastLocation(StorageLocationNode node) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefLastLocationKey,
        jsonEncode({'slotId': node.id, 'pathLabel': node.pathLabel}),
      );
    } catch (_) {}
  }

  /// 未识别位置且未手动选择时，预选上次入库的位置（常用位置记忆）。
  void _maybeRestoreLastLocation() {
    if (_selectedNode != null || _plan != null) return;
    final slotId = _lastLocationCache?['slotId'];
    if (slotId == null) return;
    final nodes =
        ref.read(storageLocationTreeProvider).value ?? const <StorageLocationNode>[];
    for (final n in nodes) {
      if (n.isSlot && n.id == slotId) {
        _selectedNode = n;
        return;
      }
    }
  }

  // ==================== 语音输入 ====================
  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = ok);
    } catch (_) {
      // 桌面端/无语音服务平台：不支持，隐藏麦克风按钮
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (!_speechAvailable) return;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final text = result.recognizedWords;
          _descController
            ..text = text
            ..selection = TextSelection.collapsed(offset: text.length);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: 'zh_CN',
        ),
      );
      if (mounted) setState(() => _isListening = true);
    } catch (_) {
      if (mounted) ToastUtils.show(context, '语音识别启动失败，请直接打字输入');
    }
  }

  // ==================== 解析 ====================
  void _onDescChanged() {
    _parseDebounce?.cancel();
    _parseDebounce = Timer(const Duration(milliseconds: 300), _reparse);
  }

  void _reparse() {
    final text = _descController.text.trim();
    if (text.isEmpty) {
      if (_drafts.isNotEmpty) {
        setState(() {
          _disposeDrafts();
          _plan = null;
          _selectedNode = null;
        });
      }
      return;
    }
    final dict =
        ref.read(categoryDictProvider).value ?? const <CategoryDictEntry>[];
    final parsed = DescriptionParser.parseAll(
      text: text,
      known: _buildKnownSpaces(),
      categoryDict: dict,
    );
    setState(() {
      _disposeDrafts();
      _drafts = parsed.map(_ItemDraft.fromParsed).toList();
      // 位置：取任一识别到房间的解析结果
      final located = parsed.where((p) => p.room != null).toList();
      _plan = located.isNotEmpty ? _resolvePlan(located.first) : null;
      // 新一轮解析重置手动位置选择，以解析结果为准
      _selectedNode = null;
      if (located.isEmpty) {
        _maybeRestoreLastLocation();
      }
    });
  }

  /// 从现有空间数据构建解析器的存在性索引。
  KnownSpaces _buildKnownSpaces() {
    final rooms = ref.read(roomsProvider).value ?? const <Room>[];
    final nodes =
        ref.read(storageLocationTreeProvider).value ?? const <StorageLocationNode>[];
    final cabinetsOfRoom = <String, Set<String>>{};
    for (final n in nodes) {
      cabinetsOfRoom.putIfAbsent(n.roomName, () => <String>{}).add(n.cabinetName);
    }
    return KnownSpaces(
      roomNames: rooms.map((r) => r.name).where((n) => n.isNotEmpty).toList(),
      cabinetsOfRoom: cabinetsOfRoom
          .map((k, v) => MapEntry(k, v.toList())),
    );
  }

  /// 根据解析结果与现有空间数据，计算保存时要复用/创建的目标位置。
  _LocationPlan? _resolvePlan(ParsedDescription p) {
    final roomRef = p.room!;
    final nodes =
        ref.read(storageLocationTreeProvider).value ?? const <StorageLocationNode>[];
    final roomSlotNodes =
        nodes.where((n) => n.isSlot && n.roomName == roomRef.name).toList();
    final roomCabNodes =
        nodes.where((n) => !n.isSlot && n.roomName == roomRef.name).toList();

    // ── 柜体解析 ──
    String cabinetName;
    bool createCabinet;
    if (p.cabinet != null) {
      cabinetName = p.cabinet!.name;
      createCabinet = !p.cabinet!.exists;
    } else {
      // 主柜体规则：优先「主柜体」→ 首个柜体 → 自动创建「主柜体」
      final mainCab = _firstOrNull(
        roomCabNodes.where((n) => n.name == '主柜体'),
      );
      if (mainCab != null) {
        cabinetName = mainCab.name;
        createCabinet = false;
      } else if (roomCabNodes.isNotEmpty) {
        cabinetName = roomCabNodes.first.name;
        createCabinet = false;
      } else {
        cabinetName = '主柜体';
        createCabinet = true;
      }
    }

    // ── 格子解析 ──
    String slotName;
    bool createSlot;
    StorageLocationNode? slotNode;
    if (createCabinet) {
      slotName = '主区域';
      createSlot = true;
    } else {
      final cabSlotNodes =
          roomSlotNodes.where((n) => n.cabinetName == cabinetName).toList();
      final mainSlot = _firstOrNull(
        cabSlotNodes.where((n) => n.name == '主区域'),
      );
      if (mainSlot != null) {
        slotNode = mainSlot;
        slotName = mainSlot.name;
        createSlot = false;
      } else if (cabSlotNodes.isNotEmpty) {
        slotNode = cabSlotNodes.first;
        slotName = slotNode.name;
        createSlot = false;
      } else {
        slotName = '主区域';
        createSlot = true;
      }
    }

    final roomTag = '${roomRef.name}${roomRef.exists ? '' : '（新建）'}';
    final cabTag = '$cabinetName${createCabinet ? '（新建）' : ''}';
    final slotTag = '$slotName${createSlot ? '（新建）' : ''}';
    return _LocationPlan(
      roomName: roomRef.name,
      createRoom: !roomRef.exists,
      roomEmoji: roomRef.emoji,
      cabinetName: cabinetName,
      createCabinet: createCabinet,
      slotName: slotName,
      createSlot: createSlot,
      slotNode: slotNode,
      label: '$roomTag / $cabTag / $slotTag',
    );
  }

  // ==================== 保存 ====================
  Future<void> _save() async {
    if (_isSaving) return;
    final drafts = _drafts;
    if (drafts.isEmpty) {
      ToastUtils.show(context, '请先输入物品描述');
      return;
    }
    for (var i = 0; i < drafts.length; i++) {
      if (drafts[i].name.text.trim().isEmpty) {
        ToastUtils.show(context, '第 ${i + 1} 件物品缺少名称');
        return;
      }
    }
    setState(() => _isSaving = true);

    try {
      // ── 位置解析（多件物品共用一个位置，只解析一次） ──
      String? cabinetId;
      String? slotId;
      String locationLabel;

      if (_selectedNode != null) {
        cabinetId = _selectedNode!.cabinetId;
        slotId = _selectedNode!.isSlot ? _selectedNode!.id : null;
        locationLabel = _selectedNode!.pathLabel;
      } else {
        final plan = _plan;
        if (plan == null) {
          ToastUtils.show(context, '未能识别收纳位置，请点击位置行手动选择');
          return;
        }
        final resolved = await _ensureSpaces(plan);
        if (resolved == null) return;
        cabinetId = resolved.cabinetId;
        slotId = resolved.slotId;
        locationLabel = resolved.label;
        // 空间有变动时刷新位置树缓存
        ref.invalidate(storageLocationTreeProvider);
      }

      // ── 逐件入库（同名同位置询问合并/新建） ──
      int created = 0;
      int merged = 0;
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        final name = d.name.text.trim();
        final quantityRaw = int.tryParse(d.quantity.text.trim());
        final quantity = (quantityRaw == null || quantityRaw < 1)
            ? 1
            : quantityRaw;
        final unit = d.unit.text.trim();
        final priceRaw = double.tryParse(d.price.text.trim());
        final price = (priceRaw == null || priceRaw < 0) ? 0.0 : priceRaw;
        final brand = d.brand.text.trim();

        // 分类 key 校验：解析出的内置 key 必须在当前分类列表中存在
        final cats = ref.read(availableCategoriesProvider);
        String catKey = d.categoryKey;
        String catLabel = d.categoryLabel;
        if (catKey.isNotEmpty && !cats.any((c) => c.key == catKey)) {
          catKey = '';
          catLabel = '未分类';
        }

        // 重复合并检查：同名且同一格位/柜体
        final allItems = ref.read(itemsProvider).value ?? const <Item>[];
        Item? existing;
        for (final it in allItems) {
          if (it.name != name) continue;
          if (slotId != null && it.slotId == slotId) {
            existing = it;
            break;
          }
          if (slotId == null && it.cabinetId == cabinetId) {
            existing = it;
            break;
          }
        }
        if (existing != null) {
          final choice = await _showDuplicateDialog(existing, quantity, unit);
          if (choice == _DuplicateChoice.cancel) return;
          if (choice == _DuplicateChoice.merge) {
            await ref
                .read(itemsProvider.notifier)
                .updateItem(
                  existing.copyWith(quantity: existing.quantity + quantity),
                );
            merged++;
            continue;
          }
        }

        final item = Item.create(
          name: name,
          price: price,
          emoji: d.emoji,
          category: catLabel,
          categoryKey: catKey,
          location: locationLabel,
          cabinetId: cabinetId,
          slotId: slotId,
          photos: created == 0 && merged == 0 ? _photoPaths() : const [],
          brand: brand,
          note: _descController.text.trim(),
          quantity: quantity,
          unit: unit,
        );
        await ref.read(itemsProvider.notifier).addItem(item);
        created++;
      }

      // 记录常用位置（下次未识别位置时预选）
      if (_selectedNode != null) {
        await _saveLastLocation(_selectedNode!);
      } else if (slotId != null) {
        await _saveLastLocationLabel(slotId, locationLabel);
      }

      if (!mounted) return;
      final summary = drafts.length == 1
          ? '已添加「${drafts.first.name.text.trim()}」'
          : '已入库 $created 件${merged > 0 ? '，合并 $merged 件' : ''}';
      ToastUtils.show(context, summary);
      context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<String> _photoPaths() {
    return _photos
        .where((p) => p.status == PhotoStatus.success)
        .map((p) => p.path)
        .toList();
  }

  /// 按位置计划级联创建缺失的空间；返回最终 cabinetId/slotId/位置标签。
  Future<({_LocationPlan plan, String cabinetId, String? slotId, String label})?>
  _ensureSpaces(_LocationPlan plan) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rooms = ref.read(roomsProvider).value ?? const <Room>[];
    final existingRoom = _firstOrNull(
      rooms.where((r) => r.name == plan.roomName),
    );
    String? cabinetId;
    String? slotId;

    if (plan.createRoom) {
      // 级联创建：房间 → 柜体 → 格子
      final roomId = 'room_$ts';
      await ref
          .read(roomActionsProvider.notifier)
          .addRoom(
            id: roomId,
            name: plan.roomName,
            emoji: plan.roomEmoji,
            color: AppColors.primary,
          );
      final cabId = 'cabinet_${ts}_main';
      await ref
          .read(cabinetActionsProvider.notifier)
          .addCabinet(
            id: cabId,
            name: plan.cabinetName,
            emoji: '🗄️',
            color: AppColors.primary,
            roomId: roomId,
          );
      final slotKey = 'slot_${ts}_main';
      await ref
          .read(slotActionsProvider.notifier)
          .addSlot(
            id: slotKey,
            name: plan.slotName,
            emoji: '📦',
            color: AppColors.primary,
            cabinetId: cabId,
          );
      cabinetId = cabId;
      slotId = slotKey;
    } else if (plan.createCabinet) {
      // 房间已存在，创建柜体（及其区域）
      if (existingRoom == null) {
        ToastUtils.show(context, '未找到房间「${plan.roomName}」，请手动选择位置');
        return null;
      }
      final cabId = 'cabinet_${ts}_main';
      await ref
          .read(cabinetActionsProvider.notifier)
          .addCabinet(
            id: cabId,
            name: plan.cabinetName,
            emoji: '🗄️',
            color: AppColors.primary,
            roomId: existingRoom.id,
          );
      cabinetId = cabId;
      if (plan.createSlot) {
        final slotKey = 'slot_${ts}_main';
        await ref
            .read(slotActionsProvider.notifier)
            .addSlot(
              id: slotKey,
              name: plan.slotName,
              emoji: '📦',
              color: AppColors.primary,
              cabinetId: cabId,
            );
        slotId = slotKey;
      }
    } else {
      // 柜体已存在：从位置树取柜体 id
      final nodes =
          ref.read(storageLocationTreeProvider).value ??
          const <StorageLocationNode>[];
      final cabNode = _firstOrNull(
        nodes.where(
          (n) =>
              !n.isSlot &&
              n.roomName == plan.roomName &&
              n.name == plan.cabinetName,
        ),
      );
      if (cabNode == null) {
        ToastUtils.show(context, '位置信息异常，请点击位置行手动选择');
        return null;
      }
      cabinetId = cabNode.id;
      if (plan.createSlot) {
        final slotKey = 'slot_${ts}_main';
        await ref
            .read(slotActionsProvider.notifier)
            .addSlot(
              id: slotKey,
              name: plan.slotName,
              emoji: '📦',
              color: AppColors.primary,
              cabinetId: cabinetId,
            );
        slotId = slotKey;
      } else if (plan.slotNode != null) {
        slotId = plan.slotNode!.id;
      }
    }

    final label =
        '${plan.roomName} / ${plan.cabinetName} / ${plan.slotName}';
    return (plan: plan, cabinetId: cabinetId, slotId: slotId, label: label);
  }

  /// 保存常用位置（按位置标签手动构造，节点可能尚未在树中刷新）。
  Future<void> _saveLastLocationLabel(String slotId, String pathLabel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefLastLocationKey,
        jsonEncode({'slotId': slotId, 'pathLabel': pathLabel}),
      );
    } catch (_) {}
  }

  // ==================== 重复合并提示 ====================
  Future<_DuplicateChoice?> _showDuplicateDialog(
    Item existing,
    int amount,
    String unit,
  ) {
    return showDialog<_DuplicateChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '物品库已有「${existing.name}」',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            '位于 ${existing.location}，当前 ×${existing.quantity}${existing.unit.isEmpty ? '件' : existing.unit}。\n本次要录入 ×$amount${unit.isEmpty ? '件' : unit}。',
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, _DuplicateChoice.cancel),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textHint),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, _DuplicateChoice.createNew),
              child: const Text(
                '仍新建',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, _DuplicateChoice.merge),
              child: const Text(
                '合并数量',
                style: TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==================== 照片 ====================
  Future<void> _showPhotoSourceSheet() async {
    if (_photos.length >= PhotoService.maxPhotos) {
      ToastUtils.show(context, '最多添加 ${PhotoService.maxPhotos} 张照片');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                '添加照片',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined,
                    color: AppColors.primary),
                title: const Text('拍照', style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _addPhotoFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppColors.primary),
                title: const Text('从相册选择', style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _addPhotosFromGallery();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addPhotoFromCamera() async {
    await _pick(() => PhotoService.instance.pickFromCamera());
  }

  Future<void> _addPhotosFromGallery() async {
    await _pick(
      () => PhotoService.instance.pickFromGallery(
        remaining: PhotoService.maxPhotos - _photos.length,
      ),
    );
  }

  Future<void> _pick(Future<PickResult> Function() pick) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await pick();
      if (!mounted) return;
      if (result.error != null) {
        ToastUtils.show(context, result.error!);
      }
      if (result.entries.isNotEmpty) {
        setState(() => _photos.addAll(result.entries));
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removePhoto(int index) {
    setState(() {
      final removed = _photos.removeAt(index);
      // 非保存中的本地文件直接清理
      if (removed.status == PhotoStatus.success) {
        PhotoService.instance.deleteFile(removed.path);
      }
    });
  }

  // ==================== 分类选择 ====================
  void _openCategoryPicker(_ItemDraft draft) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final cats = ref.watch(availableCategoriesProvider);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    '选择分类',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        _categoryTile(draft: draft, emoji: '📦', label: '未分类', key0: ''),
                        for (final c in cats)
                          _categoryTile(draft: draft, emoji: c.emoji, label: c.label, key0: c.key),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _categoryTile({
    required _ItemDraft draft,
    required String emoji,
    required String label,
    required String key0,
  }) {
    final isSelected = draft.categoryKey == key0;
    return ListTile(
      leading: EmojiText(emoji: emoji, fontSize: 20),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.accentGold, size: 20)
          : null,
      onTap: () {
        Navigator.pop(context);
        setState(() {
          draft.categoryKey = key0;
          draft.categoryLabel = label;
        });
      },
    );
  }

  // ==================== 位置选择 ====================
  void _openLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final asyncNodes = ref.watch(storageLocationTreeProvider);
            final allNodes = asyncNodes.value ?? const [];
            final slotNodes = allNodes.where((n) => n.isSlot).toList();
            return LocationPickerSheet(
              nodes: slotNodes,
              isLoading: asyncNodes.isLoading,
              selectedNode: _selectedNode,
              onPick: (node) {
                setState(() {
                  _selectedNode = node;
                });
                Navigator.pop(ctx);
              },
              onClear: () {
                setState(() {
                  _selectedNode = null;
                });
                Navigator.pop(ctx);
              },
            );
          },
        );
      },
    );
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    // 词库异步加载完成后，对已输入的描述重新解析一次
    ref.listen(categoryDictProvider, (prev, next) {
      if (next.hasValue && _descController.text.trim().isNotEmpty) {
        _reparse();
      }
    });
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoSection(),
                    const SizedBox(height: 14),
                    _buildDescriptionSection(),
                    const SizedBox(height: 14),
                    _buildConfirmSection(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '智能录入',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            // 需要保修/保质期等完整字段时，跳转完整表单
            onTap: () => context.push('/add_item'),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, size: 18, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    '完整表单',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '物品照片（可选）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              _buildPhotoSourceSwitch(),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                if (i == _photos.length) {
                  return _addPhotoTile();
                }
                final photo = _photos[i];
                return _photoThumb(photo, i);
              },
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '点击加号按默认方式添加，长按加号可临时切换来源',
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  /// 默认添加方式切换：拍照 / 相册（持久化到 SharedPreferences）
  Widget _buildPhotoSourceSwitch() {
    Widget chip(String value, String label, IconData icon) {
      final active = _defaultPhotoSource == value;
      return GestureDetector(
        onTap: () => _setDefaultPhotoSource(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF3CC) : AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: active ? AppColors.primaryDark : AppColors.textHint,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primaryDark : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('camera', '默认拍照', Icons.photo_camera_outlined),
        const SizedBox(width: 6),
        chip('gallery', '默认相册', Icons.photo_library_outlined),
      ],
    );
  }

  Widget _addPhotoTile() {
    return GestureDetector(
      // 点击按默认来源添加；长按弹出完整来源选择（拍照/相册）
      onLongPress: _showPhotoSourceSheet,
      onTap: () {
        if (_defaultPhotoSource == 'gallery') {
          _addPhotosFromGallery();
        } else {
          _addPhotoFromCamera();
        }
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: const Icon(
          Icons.add_a_photo_outlined,
          size: 22,
          color: AppColors.textHint,
        ),
      ),
    );
  }

  Widget _photoThumb(PhotoEntry photo, int index) {
    return Stack(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: photo.status == PhotoStatus.uploading
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Image.file(
                    File(photo.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 20),
                    ),
                  ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 10, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '一句话描述',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_isListening)
                const Row(
                  children: [
                    Icon(Icons.mic, size: 14, color: AppColors.danger),
                    SizedBox(width: 4),
                    Text(
                      '正在聆听…',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDescInput(),
          const SizedBox(height: 8),
          const Text(
            '支持多件物品："客厅有纸巾和电池" / "纸巾40包和牙膏2盒"（用"和"、顿号分隔）',
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildDescInput() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: TextField(
        controller: _descController,
        maxLines: 3,
        minLines: 2,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: '物品是什么、在哪里、有多少…',
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 15),
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          border: InputBorder.none,
          suffixIcon: _speechAvailable
              ? IconButton(
                  onPressed: _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? AppColors.danger : AppColors.primary,
                    size: 22,
                  ),
                  tooltip: _isListening ? '停止语音' : '语音输入',
                )
              : null,
        ),
      ),
    );
  }

  // ─── 确认区：位置（共享）+ 逐件物品卡片 ───

  Widget _buildConfirmSection() {
    final hasLocation = _selectedNode != null || _plan != null;
    final children = <Widget>[
      // 状态提示
      if (_drafts.isNotEmpty && _drafts.any((d) => d.name.text.trim().isEmpty))
        _buildHint('⚠️ 有物品未能识别名称，请手动填写', AppColors.warning),
      if (!hasLocation && _drafts.isNotEmpty)
        _buildHint(
          _selectedNode == null
              ? '📍 未识别到收纳位置，可点击下方位置行手动选择'
              : '📍 已默认上次位置，可点击位置行更换',
          _selectedNode == null ? AppColors.warning : AppColors.success,
        ),
      if (_drafts.isEmpty)
        _buildHint('💡 输入描述后自动填好下面这张卡片，确认无误即可入库', AppColors.textHint),
      if (_drafts.length > 1)
        _buildHint('✨ 识别到 ${_drafts.length} 件物品，逐件确认后一次性入库', AppColors.info),

      // 位置（所有物品共用）
      _buildLocationCard(),

      // 逐件物品卡片
      for (var i = 0; i < _drafts.length; i++) ...[
        const SizedBox(height: 12),
        _buildDraftCard(_drafts[i], i),
      ],
    ];

    return Column(children: children);
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '收纳位置（所有物品共用）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          _buildSelectTrigger(
            text: _locationText(),
            emoji: '📍',
            onTap: _openLocationPicker,
          ),
        ],
      ),
    );
  }

  String _locationText() {
    if (_selectedNode != null) return _selectedNode!.pathLabel;
    if (_plan != null) return _plan!.label;
    return '未识别，点击选择';
  }

  Widget _buildDraftCard(_ItemDraft draft, int index) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 序号 + emoji
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '物品名称',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              EmojiText(emoji: draft.emoji, fontSize: 22),
            ],
          ),
          const SizedBox(height: 6),
          _buildInput(controller: draft.name, placeholder: '物品名称'),
          const SizedBox(height: 12),

          // 数量 & 单位 & 价格
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '数量',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildInput(
                      controller: draft.quantity,
                      placeholder: '1',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '单位',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildInput(controller: draft.unit, placeholder: '包/盒'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '价格',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildInput(
                      controller: draft.price,
                      placeholder: '选填',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 品牌 & 分类
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '品牌',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildInput(controller: draft.brand, placeholder: '选填'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '分类',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildSelectTrigger(
                      text: draft.categoryLabel,
                      emoji: '🏷️',
                      onTap: () => _openCategoryPicker(draft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHint(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String placeholder,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildSelectTrigger({
    required String text,
    required String emoji,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(
          children: [
            EmojiText(emoji: emoji, fontSize: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: text.startsWith('未识别') || text == '未分类'
                      ? AppColors.textHint
                      : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.expand_more,
              size: 16,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final canSave =
        _drafts.isNotEmpty &&
        _drafts.every((d) => d.name.text.trim().isNotEmpty) &&
        (_selectedNode != null || _plan != null);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: canSave ? _save : null,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: canSave
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDeep],
                        )
                      : null,
                  color: canSave ? null : AppColors.border,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _drafts.length > 1
                            ? '确认入库（${_drafts.length} 件）'
                            : '确认入库',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: canSave ? Colors.white : AppColors.textHint,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 工具 ──
  static T? _firstOrNull<T>(Iterable<T> it) {
    for (final v in it) {
      return v;
    }
    return null;
  }
}

/// 单件物品的可编辑草稿（由解析结果构建；卡片字段全部可改）。
class _ItemDraft {
  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController price;
  final TextEditingController brand;
  String categoryKey;
  String categoryLabel;
  String emoji;

  _ItemDraft({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.brand,
    required this.categoryKey,
    required this.categoryLabel,
    required this.emoji,
  });

  factory _ItemDraft.fromParsed(ParsedDescription p) {
    return _ItemDraft(
      name: TextEditingController(text: p.name),
      quantity: TextEditingController(text: p.quantity.toString()),
      unit: TextEditingController(text: p.unit),
      price: TextEditingController(
        text: p.price == null ? '' : _formatPriceValue(p.price!),
      ),
      brand: TextEditingController(text: p.brand ?? ''),
      categoryKey: p.categoryKey,
      categoryLabel: p.categoryLabel,
      emoji: p.emoji,
    );
  }

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    price.dispose();
    brand.dispose();
  }
}

/// 价格显示格式：整数去掉小数位（15.0 → "15"）
String _formatPriceValue(double v) {
  return v % 1 == 0 ? v.toInt().toString() : v.toString();
}

/// 保存时要复用/创建的目标位置计划。
class _LocationPlan {
  final String roomName;
  final bool createRoom;
  final String roomEmoji;
  final String cabinetName;
  final bool createCabinet;
  final String slotName;
  final bool createSlot;

  /// 已存在的目标格子节点（用于取 slotId）
  final StorageLocationNode? slotNode;

  /// 展示用路径标签（含"（新建）"标注）
  final String label;

  const _LocationPlan({
    required this.roomName,
    required this.createRoom,
    required this.roomEmoji,
    required this.cabinetName,
    required this.createCabinet,
    required this.slotName,
    required this.createSlot,
    required this.slotNode,
    required this.label,
  });
}

/// 重复合并对话框的选择结果
enum _DuplicateChoice { merge, createNew, cancel }
