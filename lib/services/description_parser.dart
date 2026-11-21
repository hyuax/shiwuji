/// 一句话描述解析服务（内置规则模型，不调用外部 AI）。
///
/// 设计目标：用户在智能录入页输入一句自然描述（如「纸巾在楼梯有40包」、
/// 「客厅茶几上有两盒茶叶」），本服务用规则解析出：
/// - 物品名称（去除位置/数量短语后的最长名词段）
/// - 数量与单位（阿拉伯数字与中文数字，如「两盒」→ 2 盒）
/// - 位置（房间 + 柜体；与现有空间做存在性匹配，不存在则由页面在保存时自动创建）
/// - 分类与 emoji（复用 [EmojiClassifier] 的物品关键词表做跨大类推断）
///
/// 位置规则（"用户说有就有"）：
/// - 提到的房间/柜体已存在 → 直接复用（柜体已存在但未提房间时，房间跟随柜体归属）；
/// - 不存在 → 解析结果标记 `exists=false`，由页面在保存时按
///   `主柜体 / 主区域` 级联创建；
/// - 只提房间未提柜体 → 页面默认放入该房间的「主柜体 / 主区域」。
library;

import 'package:shi_wu_ji/models/emoji_classifier.dart';

/// 现有空间索引（供解析器做存在性匹配，由页面从数据库数据构建）。
class KnownSpaces {
  /// 现有房间名列表
  final List<String> roomNames;

  /// 房间名 → 该房间下现有柜体名列表
  final Map<String, List<String>> cabinetsOfRoom;

  const KnownSpaces({
    this.roomNames = const [],
    this.cabinetsOfRoom = const {},
  });
}

/// 位置引用（房间或柜体）的解析结果。
class ParsedSpaceRef {
  final String name;

  /// 是否已存在于数据库（false = 保存时需自动创建）
  final bool exists;

  /// 自动创建时使用的 emoji
  final String emoji;

  const ParsedSpaceRef({
    required this.name,
    required this.exists,
    required this.emoji,
  });
}

/// 分类词库条目：关键词 → 内置/自定义分类。
/// 由 [DescriptionParser.inferCategory] 做最长关键词优先匹配。
class CategoryDictEntry {
  final String keyword;
  final String categoryKey;
  final String categoryLabel;

  const CategoryDictEntry({
    required this.keyword,
    required this.categoryKey,
    required this.categoryLabel,
  });
}

/// 一句话描述的结构化解析结果。
class ParsedDescription {
  /// 物品名称（解析失败时为兜底名「未命名物品」）
  final String name;

  /// 是否解析出有效物品名（false 表示兜底，建议用户手动修改）
  final bool hasName;

  /// 数量（未识别时为 1）
  final int quantity;

  /// 数量单位（包/盒/箱等，未识别为空字符串）
  final String unit;

  /// 房间（未识别为 null）
  final ParsedSpaceRef? room;

  /// 柜体（null 表示用户未提柜体，走「主柜体」默认规则）
  final ParsedSpaceRef? cabinet;

  /// 推断出的内置分类 key（'' = 未分类）
  final String categoryKey;

  /// 推断出的内置分类 label（'未分类'）
  final String categoryLabel;

  /// 物品 emoji（命中关键词的专属 emoji，未命中为 📦）
  final String emoji;

  /// 识别到的价格（描述中出现"15元/15块钱/￥15"时非空）
  final double? price;

  /// 识别到的品牌（仅当描述中出现"品牌"二字时非空）
  final String? brand;

  /// 原始输入（存入物品备注，便于回溯）
  final String rawText;

  const ParsedDescription({
    required this.name,
    required this.hasName,
    required this.quantity,
    required this.unit,
    required this.room,
    required this.cabinet,
    required this.categoryKey,
    required this.categoryLabel,
    required this.emoji,
    required this.price,
    required this.brand,
    required this.rawText,
  });

  /// 复制并覆盖空间字段（多物品切分时的位置继承用）。
  ParsedDescription copyWith({ParsedSpaceRef? room, ParsedSpaceRef? cabinet}) {
    return ParsedDescription(
      name: name,
      hasName: hasName,
      quantity: quantity,
      unit: unit,
      room: room ?? this.room,
      cabinet: cabinet ?? this.cabinet,
      categoryKey: categoryKey,
      categoryLabel: categoryLabel,
      emoji: emoji,
      price: price,
      brand: brand,
      rawText: rawText,
    );
  }
}

/// 内置规则解析器（纯静态、无状态、可单测）。
class DescriptionParser {
  DescriptionParser._();

  /// 常见位置词表（词 → 新建房间时的默认 emoji）。
  /// 覆盖内置快捷标签与常用家庭位置；与现有房间名匹配不上时从这里兜底识别。
  static const Map<String, String> builtinRoomWords = {
    '客厅': '🛋️',
    '卧室': '🛏️',
    '主卧': '🛏️',
    '次卧': '🛏️',
    '厨房': '🍳',
    '浴室': '🚿',
    '卫生间': '🚽',
    '厕所': '🚽',
    '洗手间': '🚽',
    '书房': '💻',
    '阳台': '🌤️',
    '玄关': '👟',
    '储物间': '📦',
    '儿童房': '🧸',
    '楼梯': '🪜',
    '走廊': '🚪',
    '过道': '🚪',
    '车库': '🚗',
    '车里': '🚗',
    '办公室': '🏢',
    '餐厅': '🍽️',
    '洗衣房': '🧺',
    '庭院': '🌳',
    '院子': '🌳',
    '阁楼': '🏠',
    '地下室': '🏠',
  };

  /// 常见家具名词（用于识别"柜体"级描述），匹配时最长优先。
  static const List<String> furnitureWords = [
    // 双字及以上完整名词优先
    '床头柜', '电视柜', '餐边柜', '梳妆台', '置物架', '晾衣架', '毛巾架',
    '书桌', '餐桌', '办公桌', '书架', '花架', '衣柜', '鞋柜', '书柜',
    '酒柜', '碗柜', '冰柜', '冰箱', '橱柜', '吊柜', '地柜', '柜台',
    '货架', '展示架', '衣帽架', '茶几', '角几', '抽屉', '收纳箱', '纸箱',
    '储物箱', '收纳盒', '洗手台', '灶台', '床头', '床底', '床下', '柜子',
    '架子', '桌子', '箱子', '柜体',
    // 单字兜底（最长优先匹配后才会轮到）
    '柜', '架', '桌', '箱', '几', '台',
  ];

  /// 数量量词表（构建正则时按长度降序拼接）。
  static const List<String> measureWords = [
    '个', '只', '包', '盒', '箱', '瓶', '罐', '支', '双', '台', '部',
    '本', '张', '条', '把', '卷', '袋', '提', '枚', '块', '辆', '套',
    '份', '捆', '排', '层', '组', '件', '册', '筒', '副', '对', '束',
    '盘', '碟', '杯', '壶', '听', '打', '匹',
    // 生鲜/日化常用
    '节', '桶', '粒', '根', '朵', '克', '斤', '公斤', '升', '毫升',
  ];

  /// 名称清理时剥离的助词/动词/方位词（前后缀循环剥离）。
  static const List<String> _particleWords = [
    '一共', '还有', '买了些', '买了', '放的', '放在', '放到', '放进',
    '收在', '收进', '摆在', '搁在', '存在', '有', '共', '在', '于',
    '放', '收', '摆', '搁', '存', '是', '把', '被', '给', '和', '与',
    '跟', '了', '着', '的', '都', '也', '就', '还', '已', '到', '进',
    '上', '下', '里', '内', '中', '旁', '边', '面', '头', '侧', '前', '后',
  ];

  /// EmojiClassifier 大类 key → 内置分类 [key, label] 映射。
  /// 只映射与数据库 12 个内置分类对齐的大类；
  /// food/medicine/baby/pet 等未对齐大类归入「未分类」。
  static const Map<String, List<String>> mainKeyToCategory = {
    'digital': ['digital', '数码'],
    'appliance': ['appliance', '家电'],
    'skincare': ['skincare', '护肤'],
    'kitchen': ['kitchen', '厨房'],
    'clothing': ['clothing', '衣物'],
    'books': ['books', '书籍'],
    'storage': ['storage', '收纳'],
    'toy': ['toy', '玩具'],
    'sports': ['sports', '运动'],
    'stationery': ['stationery', '文具'],
    'keys': ['keys', '钥匙'],
    'tools': ['tools', '工具'],
  };

  static const String _fallbackName = '未命名物品';
  static const String _defaultRoomEmoji = '🏠';
  static const String _cabinetEmoji = '🗄️';

  /// 数量正则：阿拉伯数字或中文数字 + 量词（量词按长度降序拼接）。
  static final RegExp _quantityRegex = RegExp(
    '([0-9]+|[零一二两三四五六七八九十百千]+)\\s*(${_sortedByLengthDesc(measureWords).join('|')})',
  );

  /// 价格正则：仅识别明确的货币表述，避免把量词"块"误判为金额。
  /// - "15元" / "15块钱"（阿拉伯数字 + 元/块钱；裸"块"按量词处理）
  /// - "￥15" / "¥15"（货币符号 + 阿拉伯数字）
  static final RegExp _priceRegex = RegExp(
    r'([0-9]+(?:\.[0-9]+)?)\s*(元|块钱)|([￥¥])\s*([0-9]+(?:\.[0-9]+)?)',
  );

  /// 品牌正则（仅当描述中出现"品牌"二字时才提取）：
  /// - "品牌X" / "品牌是X"（品牌后置，X 为懒匹配名词段）
  /// - "X品牌"（品牌前置，如"A品牌"）
  static final RegExp _brandAfterRegex = RegExp(
    '品牌\\s*[是为:：]?\\s*([\u4e00-\u9fa5A-Za-z0-9]{1,10}?)(?=[的是在放了有及和与、，。！？\\s]|\$)',
  );
  static final RegExp _brandBeforeRegex = RegExp(
    '([\u4e00-\u9fa5A-Za-z0-9]{1,10}?)品牌',
  );

  /// 多物品切分：标点（，。；、逗号句号分号换行）与并列连词（和/与/跟/还有/以及）。
  static final RegExp _splitPunctuationRegex = RegExp(r'[，。；;,\n]');
  static final RegExp _splitConjunctionRegex = RegExp(r'还有|以及|和|与|跟');

  /// 解析一句话描述为多件物品（"一句话多物品"支持）。
  ///
  /// 以标点与并列连词切分后逐段解析；位置（房间/柜体）在段间共享继承：
  /// 任一段识别到位置，其余未识别位置的段沿用该位置。
  /// 防误切保护：任一段解析不出 ≥2 字的物品名（如"调和油"被"和"切开），
  /// 则放弃切分、回退为整句单物品解析。
  /// 单段或切分失败时返回单个元素的列表，调用方无需区分。
  static List<ParsedDescription> parseAll({
    required String text,
    KnownSpaces known = const KnownSpaces(),
    List<CategoryDictEntry> categoryDict = const [],
  }) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return [parse(text: raw, known: known, categoryDict: categoryDict)];
    }

    final parts = raw
        .split(_splitPunctuationRegex)
        .expand((p) => p.split(_splitConjunctionRegex))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.length <= 1) {
      return [parse(text: raw, known: known, categoryDict: categoryDict)];
    }

    final parsed = <ParsedDescription>[];
    ParsedSpaceRef? sharedRoom;
    ParsedSpaceRef? sharedCabinet;
    for (final part in parts) {
      final r = parse(text: part, known: known, categoryDict: categoryDict);
      // 有效切分：每段都需解析出 ≥2 字的物品名
      if (!r.hasName || r.name.length < 2) {
        return [parse(text: raw, known: known, categoryDict: categoryDict)];
      }
      if (r.room != null) {
        sharedRoom ??= r.room;
        sharedCabinet ??= r.cabinet;
      }
      parsed.add(r);
    }
    if (parsed.isEmpty) {
      return [parse(text: raw, known: known, categoryDict: categoryDict)];
    }
    // 位置继承：未识别位置的段沿用共享位置
    return parsed
        .map(
          (r) => r.room != null
              ? r
              : r.copyWith(room: sharedRoom, cabinet: r.cabinet ?? sharedCabinet),
        )
        .toList();
  }

  /// 解析一句话描述。
  static ParsedDescription parse({
    required String text,
    KnownSpaces known = const KnownSpaces(),
    List<CategoryDictEntry> categoryDict = const [],
  }) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return ParsedDescription(
        name: _fallbackName,
        hasName: false,
        quantity: 1,
        unit: '',
        room: null,
        cabinet: null,
        categoryKey: '',
        categoryLabel: '未分类',
        emoji: '📦',
        price: null,
        brand: null,
        rawText: raw,
      );
    }

    // 规范化：全角数字→半角；标点替换为空格，作为分段分隔符
    var work = _normalize(raw);

    // ── 1. 价格提取（先于数量：避免"15块"被量词抢走）─────────
    double? price;
    final priceMatch = _priceRegex.firstMatch(work);
    if (priceMatch != null) {
      final numRaw = priceMatch.group(1) ?? priceMatch.group(4);
      price = double.tryParse(numRaw ?? '');
      work = _blankOut(work, priceMatch.start, priceMatch.end);
    }

    // ── 2. 数量提取 ──────────────────────────────────────────
    int quantity = 1;
    String unit = '';
    final qtyMatch = _quantityRegex.firstMatch(work);
    if (qtyMatch != null) {
      final numRaw = qtyMatch.group(1)!;
      quantity = int.tryParse(numRaw) ?? _chineseToInt(numRaw) ?? 1;
      unit = qtyMatch.group(2)!;
      work = _blankOut(work, qtyMatch.start, qtyMatch.end);
    }

    // ── 3. 品牌提取（仅当出现"品牌"二字；先于位置提取）───────
    final brandResult = _extractBrand(work, categoryDict);
    final brand = brandResult?.brand;
    if (brandResult != null) {
      work = _blankOut(work, brandResult.start, brandResult.end);
    }

    // ── 4. 房间提取（现有房间优先，其次内置位置词表）──────────
    final roomMatch = _matchRoom(work, known);
    ParsedSpaceRef? room = roomMatch?.ref;
    if (roomMatch != null) work = roomMatch.work;

    // ── 5. 柜体提取（现有柜体优先，其次家具名词）──────────────
    final cabinetToRoom = _buildCabinetToRoom(known);
    var cabinetMatch =
        _matchExistingCabinet(work, cabinetToRoom, room) ??
        _matchFurnitureCabinet(work);
    ParsedSpaceRef? cabinet = cabinetMatch?.ref;
    if (cabinetMatch != null) work = cabinetMatch.work;

    // 房间跟随：未提房间但柜体已存在时，按柜体归属反推房间
    if (room == null && cabinet != null && cabinet.exists) {
      final owner = _ownerRoomOf(cabinet.name, cabinetToRoom);
      if (owner != null) {
        room = ParsedSpaceRef(name: owner, exists: true, emoji: _defaultRoomEmoji);
      }
    }

    // ── 6. 物品名提取（去除已匹配短语后的最长名词段）──────────
    final nameResult = _extractName(work);
    String name = nameResult ?? _fallbackName;
    final bool hasName = nameResult != null;

    // 兜底规则：没有物品名但识别到了柜体名词（如「新冰箱放厨房」、
    // 「储物间有十五个收纳箱」），说明用户口中的"柜体"其实是物品本身。
    if (!hasName && cabinet != null) {
      name = cabinet.name;
      cabinet = null;
    }

    // ── 7. 分类与 emoji 推断（词库优先 → EmojiClassifier 兜底）─
    final inferred = inferCategory(
      name: name,
      fallbackContent: hasName ? '' : raw,
      dict: categoryDict,
    );
    String categoryKey = '';
    String categoryLabel = '未分类';
    String emoji = inferred?.emoji ?? '📦';
    if (inferred != null) {
      categoryKey = inferred.key;
      categoryLabel = inferred.label;
    }

    return ParsedDescription(
      name: name,
      hasName: hasName,
      quantity: quantity,
      unit: unit,
      room: room,
      cabinet: cabinet,
      categoryKey: categoryKey,
      categoryLabel: categoryLabel,
      emoji: emoji,
      price: price,
      brand: brand,
      rawText: raw,
    );
  }

  /// 分类推断（词库最长关键词优先 → EmojiClassifier 全局兜底）。
  ///
  /// [name] 为物品名（优先匹配来源）；[fallbackContent] 为物品名无效时的
  /// 全文兜底来源；[dict] 为内置+自定义词库。
  /// 返回 (key, label, emoji, source)，无法推断时返回 null。
  static ({String key, String label, String emoji, String source})?
      inferCategory({
    required String name,
    String fallbackContent = '',
    List<CategoryDictEntry> dict = const [],
  }) {
    // 1. 词库：物品名优先，兜底内容其次；同长度命中时先声明者优先
    final sources = <String>[
      name,
      if (fallbackContent.isNotEmpty && fallbackContent != name)
        fallbackContent,
    ];
    for (final source in sources) {
      CategoryDictEntry? best;
      for (final e in dict) {
        if (e.keyword.isEmpty || !source.contains(e.keyword)) continue;
        if (best == null || e.keyword.length > best.keyword.length) {
          best = e;
        }
      }
      if (best != null) {
        final emojiMatch = EmojiClassifier.classifyMain(source);
        return (
          key: best.categoryKey,
          label: best.categoryLabel,
          emoji: emojiMatch?.emoji ?? '📦',
          source: 'dict',
        );
      }
    }
    // 2. EmojiClassifier 跨大类全局推断
    final match = EmojiClassifier.classifyMain(name) ??
        (fallbackContent.isNotEmpty && fallbackContent != name
            ? EmojiClassifier.classifyMain(fallbackContent)
            : null);
    if (match != null) {
      final mapped = mainKeyToCategory[match.mainKey];
      return (
        key: mapped?[0] ?? '',
        label: mapped?[1] ?? '未分类',
        emoji: match.emoji,
        source: 'classifier',
      );
    }
    return null;
  }

  // ────────────────── 内部实现 ──────────────────

  /// 全角数字转半角；常见中英文标点替换为空格（分段分隔符）。
  static String _normalize(String text) {
    const fullWidth = '０１２３４５６７８９';
    final sb = StringBuffer();
    for (final ch in text.runes) {
      final c = String.fromCharCode(ch);
      final idx = fullWidth.indexOf(c);
      if (idx >= 0) {
        sb.write(idx.toString());
      } else if ('，。、；：！？,.;:!?~～·""''（）()【】<>《》'.contains(c)) {
        sb.write(' ');
      } else {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  /// 将 [start, end) 区间替换为占位符 ■（保留位置关系、充当分隔符）。
  static String _blankOut(String text, int start, int end) {
    return text.replaceRange(start, end, ' ■ ');
  }

  /// 品牌提取结果（含需抹除的原文区间）。
  static ({String brand, int start, int end})? _extractBrand(
    String work,
    List<CategoryDictEntry> dict,
  ) {
    if (!work.contains('品牌')) return null;

    final after = _brandAfterRegex.firstMatch(work);
    final before = _brandBeforeRegex.firstMatch(work);

    final afterBrand =
        (after != null && (after.group(1)?.isNotEmpty ?? false))
        ? _stripParticles(after.group(1)!)
        : null;
    final beforeBrand =
        (before != null && (before.group(1)?.isNotEmpty ?? false))
        ? _stripParticles(before.group(1)!)
        : null;

    String? brand;
    int start = 0;
    int end = 0;
    if (afterBrand != null && beforeBrand != null) {
      // 两侧候选都存在时的消歧优先级：
      // 1. "品牌是/为/：X" 显式句式 → 品牌后置（最高置信）
      // 2. 一方是"物品名词"（词库/分类器命中）→ 另一方是品牌
      //    （"纸巾品牌心相印"→纸巾是物品→品牌=心相印；"维达品牌纸巾"→品牌=维达）
      // 3. 两可时默认"X品牌"前置（"A品牌纸巾"是最常见说法）
      final matchedText = after!.group(0) ?? '';
      final hasCopula = matchedText.contains('是') ||
          matchedText.contains('为') ||
          matchedText.contains('：') ||
          matchedText.contains(':');
      final beforeIsItem = _isItemLike(beforeBrand, dict);
      final afterIsItem = _isItemLike(afterBrand, dict);
      String? pick;
      if (hasCopula) {
        pick = 'after';
      } else if (beforeIsItem && !afterIsItem) {
        pick = 'after';
      } else if (!beforeIsItem && afterIsItem) {
        pick = 'before';
      } else {
        pick = 'before';
      }
      if (pick == 'before') {
        brand = beforeBrand;
        start = before!.start;
        end = before.end;
      } else {
        brand = afterBrand;
        start = after.start;
        end = after.end;
      }
    } else if (afterBrand != null) {
      brand = afterBrand;
      start = after!.start;
      end = after.end;
    } else if (beforeBrand != null) {
      brand = beforeBrand;
      start = before!.start;
      end = before.end;
    } else {
      return null;
    }
    if (brand.isEmpty) return null;
    return (brand: brand, start: start, end: end);
  }

  /// 候选词是否像"物品名词"（词库命中或 EmojiClassifier 可分类）。
  static bool _isItemLike(String word, List<CategoryDictEntry> dict) {
    if (dict.any((e) => e.keyword == word)) return true;
    return EmojiClassifier.classifyMain(word) != null;
  }

  /// 中文数字转 int（支持 零 至 九千 的常见写法；两 视作 2）。
  static int? _chineseToInt(String raw) {    const digits = {
      '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    };
    const units = {'十': 10, '百': 100, '千': 1000};
    int result = 0;
    int current = 0;
    bool any = false;
    for (final ch in raw.split('')) {
      if (digits.containsKey(ch)) {
        current = digits[ch]!;
        any = true;
      } else if (units.containsKey(ch)) {
        // 「十五」的「十」前面没有数字时视为 1（=15）
        if (current == 0 && ch == '十') current = 1;
        result += current * units[ch]!;
        current = 0;
        any = true;
      } else if (ch == '零') {
        continue;
      } else {
        return null;
      }
    }
    return any ? result + current : null;
  }

  /// 房间匹配：现有房间名（最长优先）→ 内置位置词表（最长优先）。
  /// 返回结果与抹除匹配片段后的工作串。
  static ({ParsedSpaceRef ref, String work})? _matchRoom(
    String work,
    KnownSpaces known,
  ) {
    // 现有房间：存在性为 true
    for (final name in _sortedByLengthDesc(known.roomNames)) {
      if (name.isEmpty) continue;
      final idx = work.indexOf(name);
      if (idx >= 0) {
        return (
          ref: ParsedSpaceRef(
            name: name,
            exists: true,
            emoji: _defaultRoomEmoji,
          ),
          work: _blankOut(work, idx, idx + name.length),
        );
      }
    }
    // 内置词表：不存在，保存时自动创建
    for (final word in _sortedByLengthDesc(builtinRoomWords.keys.toList())) {
      final idx = work.indexOf(word);
      if (idx >= 0) {
        return (
          ref: ParsedSpaceRef(
            name: word,
            exists: false,
            emoji: builtinRoomWords[word] ?? _defaultRoomEmoji,
          ),
          work: _blankOut(work, idx, idx + word.length),
        );
      }
    }
    return null;
  }

  /// 现有柜体名 → 所属房间名 的映射。
  static Map<String, String> _buildCabinetToRoom(KnownSpaces known) {
    final map = <String, String>{};
    known.cabinetsOfRoom.forEach((roomName, cabinets) {
      for (final c in cabinets) {
        if (c.isNotEmpty) map[c] = roomName;
      }
    });
    return map;
  }

  /// 已存在柜体匹配（最长优先）：
  /// - 指定房间时只在该房间的柜体中找；
  /// - 未指定房间时跨全部房间找（房间随后由归属反推）；
  /// - 指定房间与柜体实际归属冲突时跳过（尊重用户口中的房间，视为新建）。
  /// 返回结果与抹除匹配片段后的工作串。
  static ({ParsedSpaceRef ref, String work})? _matchExistingCabinet(
    String work,
    Map<String, String> cabinetToRoom,
    ParsedSpaceRef? room,
  ) {
    for (final name in _sortedByLengthDesc(cabinetToRoom.keys.toList())) {
      final idx = work.indexOf(name);
      if (idx < 0) continue;
      final ownerRoom = cabinetToRoom[name]!;
      if (room != null && ownerRoom != room.name) continue;
      return (
        ref: ParsedSpaceRef(name: name, exists: true, emoji: _cabinetEmoji),
        work: _blankOut(work, idx, idx + name.length),
      );
    }
    return null;
  }

  /// 家具名词匹配（最长优先），命中后向两侧扩展修饰词（红木书桌/白色柜子）。
  /// 命中的均为"不存在"的柜体（保存时创建）。
  /// 返回结果与抹除匹配片段后的工作串。
  static ({ParsedSpaceRef ref, String work})? _matchFurnitureCabinet(
    String work,
  ) {
    for (final word in _sortedByLengthDesc(furnitureWords)) {
      final idx = work.indexOf(word);
      if (idx < 0) continue;
      final span = _extendNoun(work, idx, word.length);
      return (
        ref: ParsedSpaceRef(name: span.noun, exists: false, emoji: _cabinetEmoji),
        work: _blankOut(work, span.start, span.end),
      );
    }
    return null;
  }

  /// 柜体名所属房间查询。
  static String? _ownerRoomOf(
    String cabinetName,
    Map<String, String> cabinetToRoom,
  ) {
    return cabinetToRoom[cabinetName];
  }

  /// 从家具名词命中位置向两侧扩展名词修饰成分（遇占位符/助词/标点停止）。
  /// 返回扩展后的完整区间与名词文本。
  static ({int start, int end, String noun}) _extendNoun(
    String work,
    int start,
    int length,
  ) {
    const stopChars = ' ■，。、的了在有是在上里中旁边后前头内面';
    int left = start;
    while (left > 0) {
      final ch = work[left - 1];
      if (stopChars.contains(ch)) break;
      // 防止吞掉过多内容
      if (start - left >= 4) break;
      left--;
    }
    int right = start + length;
    while (right < work.length) {
      final ch = work[right];
      if (stopChars.contains(ch)) break;
      if (right - (start + length) >= 2) break;
      right++;
    }
    return (start: left, end: right, noun: work.substring(left, right));
  }

  /// 物品名提取：按空白/占位符分段，逐段剥离助词后取最长段。
  static String? _extractName(String work) {
    final segments = work
        .split(RegExp(r'[\s■]+'))
        .map(_stripParticles)
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    segments.sort((a, b) => b.length.compareTo(a.length));
    final name = segments.first;
    return name.isEmpty ? null : name;
  }

  /// 剥离分段首尾的助词/动词/方位词（循环直到稳定）。
  /// 整段恰好是助词时允许剥空（该分段即被丢弃）。
  static String _stripParticles(String segment) {
    String s = segment;
    bool changed = true;
    while (changed && s.isNotEmpty) {
      changed = false;
      for (final p in _particleWords) {
        if (s.startsWith(p)) {
          s = s.substring(p.length);
          changed = true;
        }
        if (s.endsWith(p)) {
          s = s.substring(0, s.length - p.length);
          changed = true;
        }
      }
    }
    return s.trim();
  }

  /// 字符串按长度降序排序（保证最长优先匹配）。
  static List<String> _sortedByLengthDesc(List<String> list) {
    final copy = List<String>.from(list);
    copy.sort((a, b) => b.length.compareTo(a.length));
    return copy;
  }
}
