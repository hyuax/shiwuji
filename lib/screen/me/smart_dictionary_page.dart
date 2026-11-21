import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shi_wu_ji/constants/app_colors.dart';
import 'package:shi_wu_ji/models/category.dart';
import 'package:shi_wu_ji/providers/category_dict_provider.dart';
import 'package:shi_wu_ji/providers/category_provider.dart';
import 'package:shi_wu_ji/services/category_dictionary.dart';
import 'package:shi_wu_ji/services/description_parser.dart';
import 'package:shi_wu_ji/widgets/toast_utils.dart';

/// 识别词库管理页：一句话录入的分类依据。
/// 内置词条只读；用户可添加/删除自定义词条（关键词 → 分类）。
class SmartDictionaryPage extends ConsumerStatefulWidget {
  const SmartDictionaryPage({super.key});

  @override
  ConsumerState<SmartDictionaryPage> createState() =>
      _SmartDictionaryPageState();
}

class _SmartDictionaryPageState extends ConsumerState<SmartDictionaryPage> {
  // ── 词库试算（输入一句话看解析效果） ──
  final _tryController = TextEditingController();
  List<ParsedDescription>? _tryResults;

  @override
  void dispose() {
    _tryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customAsync = ref.watch(customCategoryDictProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  _buildHintCard(),
                  const SizedBox(height: 14),
                  _buildTryoutCard(),
                  const SizedBox(height: 14),
                  _buildSectionTitle('我的词库'),
                  const SizedBox(height: 8),
                  _buildCustomSection(customAsync),
                  const SizedBox(height: 14),
                  _buildSectionTitle('内置词库（不可删除）'),
                  const SizedBox(height: 8),
                  _buildBuiltInSection(),
                ],
              ),
            ),
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
            '识别词库',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHintCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        '智能录入和添加物品时，会按这里的「关键词 → 分类」自动识别分类。\n'
        '例如添加「纸巾」关键词后，输入"纸巾在楼梯有40包"就会自动归入对应分类。'
        '同关键词的自定义词条会覆盖内置词条。',
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }

  // ─── 词库试算：输入一句话看解析效果 ──────────────

  Widget _buildTryoutCard() {
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
            '词库试算',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '输入一句话，即时预览智能录入的解析效果',
            style: TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tryController,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '例如：客厅有纸巾和电池',
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _runTryout,
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDeep],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '解析预览',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_tryResults != null) ...[
            const SizedBox(height: 10),
            if (_tryResults!.isEmpty)
              const Text(
                '（输入为空）',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              )
            else
              ..._tryResults!.map(_buildTryoutRow),
          ],
        ],
      ),
    );
  }

  Future<void> _runTryout() async {
    final dict =
        ref.read(categoryDictProvider).value ?? const <CategoryDictEntry>[];
    final parsed = DescriptionParser.parseAll(
      text: _tryController.text,
      categoryDict: dict,
    );
    setState(() => _tryResults = parsed);
  }

  Widget _buildTryoutRow(ParsedDescription p) {
    final parts = <String>[
      '${p.name} ×${p.quantity}${p.unit}',
      if (p.brand != null) '品牌:${p.brand}',
      if (p.price != null) '¥${p.price}',
      if (p.categoryLabel != '未分类') p.categoryLabel,
      if (p.room != null) p.room!.name,
      if (p.cabinet != null) p.cabinet!.name,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        parts.join(' · '),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildCustomSection(AsyncValue<List<CategoryDictEntry>> customAsync) {
    final custom = customAsync.value ?? const <CategoryDictEntry>[];
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
          if (custom.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '还没有自定义词条，点击下方按钮添加。',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            )
          else
            ...custom.map(_buildCustomTile),
          const Divider(height: 16, color: AppColors.border),
          GestureDetector(
            onTap: _openAddSheet,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    '添加词条',
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

  Widget _buildCustomTile(CategoryDictEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: entry.keyword,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: '  →  ${entry.categoryLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              await ref
                  .read(categoryDictActionsProvider.notifier)
                  .removeEntry(entry.keyword);
              if (mounted) ToastUtils.show(context, '已删除「${entry.keyword}」');
            },
            child: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuiltInSection() {
    final entries = CategoryDictionary.builtIn;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: entries
            .map(
              (e) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: e.keyword,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: ' → ${e.categoryLabel}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ─── 添加词条弹层 ──────────────────────────────
  void _openAddSheet() {
    final keywordController = TextEditingController();
    String? selectedKey;
    String selectedLabel = '未分类';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '添加词条',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '关键词（描述中出现的物品名词）',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keywordController,
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '例如：湿巾、酱油、充电线',
                      hintStyle: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 14,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('归入分类', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final picked = await _pickCategory(sheetCtx);
                      if (picked != null) {
                        setSheetState(() {
                          selectedKey = picked.key;
                          selectedLabel = picked.label;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedLabel,
                              style: TextStyle(
                                fontSize: 14,
                                color: selectedKey == null
                                    ? AppColors.textHint
                                    : AppColors.textPrimary,
                              ),
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
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      final keyword = keywordController.text.trim();
                      if (keyword.isEmpty) {
                        ToastUtils.show(sheetCtx, '请填写关键词');
                        return;
                      }
                      if (selectedKey == null) {
                        ToastUtils.show(sheetCtx, '请选择归入的分类');
                        return;
                      }
                      await ref
                          .read(categoryDictActionsProvider.notifier)
                          .addEntry(
                            keyword: keyword,
                            categoryKey: selectedKey!,
                            categoryLabel: selectedLabel,
                          );
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      if (mounted) {
                        ToastUtils.show(context, '已添加「$keyword」→ $selectedLabel');
                      }
                    },
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDeep],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '保存词条',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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

  Future<Category?> _pickCategory(BuildContext sheetCtx) async {
    final cats = ref.read(availableCategoriesProvider);
    return showModalBottomSheet<Category>(
      context: sheetCtx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (pickCtx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '选择分类',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              for (final c in cats)
                ListTile(
                  leading: Text(c.emoji, style: const TextStyle(fontSize: 18)),
                  title: Text(c.label, style: const TextStyle(fontSize: 15)),
                  onTap: () => Navigator.pop(pickCtx, c),
                ),
            ],
          ),
        );
      },
    );
  }
}
