import 'package:flutter_test/flutter_test.dart';
import 'package:shi_wu_ji/models/emoji_classifier.dart';
import 'package:shi_wu_ji/services/description_parser.dart';

void main() {
  group('DescriptionParser 数量提取', () {
    test('阿拉伯数字 + 量词（物品在前）', () {
      final r = DescriptionParser.parse(text: '纸巾在楼梯有40包');
      expect(r.name, '纸巾');
      expect(r.quantity, 40);
      expect(r.unit, '包');
      expect(r.room?.name, '楼梯');
      expect(r.room?.exists, false);
      expect(r.cabinet, isNull);
      expect(r.rawText, '纸巾在楼梯有40包');
    });

    test('语序反转：位置在前', () {
      final r = DescriptionParser.parse(text: '楼梯有40包纸巾');
      expect(r.name, '纸巾');
      expect(r.quantity, 40);
      expect(r.unit, '包');
      expect(r.room?.name, '楼梯');
    });

    test('中文数字转换（位置在前）', () {
      final r = DescriptionParser.parse(text: '客厅茶几上有两盒茶叶');
      expect(r.name, '茶叶');
      expect(r.quantity, 2);
      expect(r.unit, '盒');
      expect(r.room?.name, '客厅');
      expect(r.cabinet?.name, '茶几');
      expect(r.cabinet?.exists, false);
    });

    test('中文数字语序反转（物品在前）', () {
      final r = DescriptionParser.parse(text: '两盒茶叶在客厅茶几上');
      expect(r.name, '茶叶');
      expect(r.quantity, 2);
      expect(r.cabinet?.name, '茶几');
    });

    test('无数量默认为 1、家具柜体与自动分类', () {
      final r = DescriptionParser.parse(text: '数据线放在书房书架上');
      expect(r.quantity, 1);
      expect(r.unit, '');
      expect(r.name, '数据线');
      expect(r.room?.name, '书房');
      expect(r.cabinet?.name, '书架');
      expect(r.categoryKey, 'digital');
    });

    test('「十五」等中文数字与收纳箱兜底', () {
      // 无物品名残留时，识别到的"柜体名词"回退为物品本身
      final r = DescriptionParser.parse(text: '储物间有十五个收纳箱');
      expect(r.quantity, 15);
      expect(r.unit, '个');
      expect(r.name, '收纳箱');
      expect(r.cabinet, isNull);
      expect(r.room?.name, '储物间');
    });

    test('纯中文数字（含两）', () {
      final r = DescriptionParser.parse(text: '厨房有两把雨伞');
      expect(r.quantity, 2);
      expect(r.unit, '把');
      expect(r.name, '雨伞');
      expect(r.room?.name, '厨房');
    });
  });

  group('DescriptionParser 位置匹配', () {
    test('现有房间识别为已存在', () {
      final r = DescriptionParser.parse(
        text: '纸巾在卧室有3包',
        known: const KnownSpaces(roomNames: ['卧室', '客厅', '厨房']),
      );
      expect(r.room?.name, '卧室');
      expect(r.room?.exists, true);
      expect(r.quantity, 3);
    });

    test('现有房间下的现有柜体直接复用', () {
      final r = DescriptionParser.parse(
        text: '茶叶放在厨房橱柜里有两罐',
        known: const KnownSpaces(
          roomNames: ['厨房'],
          cabinetsOfRoom: {
            '厨房': ['主柜体', '橱柜'],
          },
        ),
      );
      expect(r.room?.name, '厨房');
      expect(r.cabinet?.name, '橱柜');
      expect(r.cabinet?.exists, true);
      expect(r.name, '茶叶');
      expect(r.quantity, 2);
      expect(r.unit, '罐');
    });

    test('未提房间但柜体已存在时反推房间归属', () {
      final r = DescriptionParser.parse(
        text: '冰箱里还有三瓶可乐',
        known: const KnownSpaces(
          roomNames: ['厨房', '客厅'],
          cabinetsOfRoom: {
            '厨房': ['主柜体', '冰箱'],
            '客厅': ['主柜体'],
          },
        ),
      );
      expect(r.cabinet?.name, '冰箱');
      expect(r.cabinet?.exists, true);
      expect(r.room?.name, '厨房');
      expect(r.room?.exists, true);
      expect(r.name, '可乐');
      expect(r.quantity, 3);
      expect(r.unit, '瓶');
    });

    test('主柜体作为现有柜体被识别', () {
      final r = DescriptionParser.parse(
        text: '纸巾放在楼梯主柜体有5包',
        known: const KnownSpaces(
          roomNames: ['楼梯'],
          cabinetsOfRoom: {
            '楼梯': ['主柜体'],
          },
        ),
      );
      expect(r.room?.name, '楼梯');
      expect(r.cabinet?.name, '主柜体');
      expect(r.cabinet?.exists, true);
      expect(r.name, '纸巾');
    });

    test('无位置信息时房间与柜体为空', () {
      final r = DescriptionParser.parse(text: '买了一包纸巾');
      expect(r.name, '纸巾');
      expect(r.quantity, 1);
      expect(r.unit, '包');
      expect(r.room, isNull);
      expect(r.cabinet, isNull);
    });

    test('空输入兜底', () {
      final r = DescriptionParser.parse(text: '   ');
      expect(r.name, '未命名物品');
      expect(r.hasName, false);
      expect(r.quantity, 1);
      expect(r.room, isNull);
    });
  });

  group('DescriptionParser 分类推断', () {
    test('物品名命中数码类', () {
      final r = DescriptionParser.parse(text: 'iPad 放在书房主柜体');
      expect(r.categoryKey, 'digital');
      expect(r.categoryLabel, '数码');
      expect(r.emoji, isNotEmpty);
    });

    test('未命中关键词归入未分类', () {
      final r = DescriptionParser.parse(text: '纸巾在楼梯有40包');
      expect(r.categoryKey, '');
      expect(r.categoryLabel, '未分类');
    });
  });

  group('EmojiClassifier.classifyMain 全局推断', () {
    test('最长关键词消歧：笔记本电脑 → digital', () {
      final m = EmojiClassifier.classifyMain('笔记本电脑');
      expect(m?.mainKey, 'digital');
    });

    test('裸「笔记本」按优先级归 digital', () {
      final m = EmojiClassifier.classifyMain('笔记本');
      expect(m?.mainKey, 'digital');
    });

    test('口红 → skincare', () {
      final m = EmojiClassifier.classifyMain('口红');
      expect(m?.mainKey, 'skincare');
      expect(m?.emoji, isNotEmpty);
    });

    test('未命中返回 null', () {
      expect(EmojiClassifier.classifyMain('纸巾'), isNull);
      expect(EmojiClassifier.classifyMain(''), isNull);
    });
  });

  group('DescriptionParser 价格提取', () {
    test('"15元" → 价格 15', () {
      final r = DescriptionParser.parse(text: '纸巾15元放在客厅');
      expect(r.price, 15);
      expect(r.name, '纸巾');
      expect(r.room?.name, '客厅');
      expect(r.quantity, 1);
    });

    test('"40包15块钱" → 数量与价格同时识别', () {
      final r = DescriptionParser.parse(text: '楼梯有40包纸巾15块钱');
      expect(r.quantity, 40);
      expect(r.unit, '包');
      expect(r.price, 15);
      expect(r.name, '纸巾');
    });

    test('"￥25" → 价格 25', () {
      final r = DescriptionParser.parse(text: '￥25的洗发水放在浴室');
      expect(r.price, 25);
      expect(r.name, '洗发水');
    });

    test('裸"块"仍按量词处理（不误判为金额）', () {
      final r = DescriptionParser.parse(text: '厨房有三块糖');
      expect(r.quantity, 3);
      expect(r.unit, '块');
      expect(r.price, isNull);
    });

    test('无价格时为 null', () {
      final r = DescriptionParser.parse(text: '纸巾在楼梯有40包');
      expect(r.price, isNull);
    });
  });

  group('DescriptionParser 品牌提取（出现"品牌"二字才识别）', () {
    // 与真实调用一致：页面总会传入合并词库（内置含"纸巾"）
    const dict = [
      CategoryDictEntry(keyword: '纸巾', categoryKey: 'storage', categoryLabel: '收纳'),
    ];

    test('"纸巾品牌心相印" → 品牌=心相印，物品=纸巾', () {
      final r = DescriptionParser.parse(text: '纸巾品牌心相印放在客厅', categoryDict: dict);
      expect(r.brand, '心相印');
      expect(r.name, '纸巾');
      expect(r.room?.name, '客厅');
    });

    test('"维达品牌纸巾" → 品牌=维达，物品=纸巾', () {
      final r = DescriptionParser.parse(text: '维达品牌纸巾在楼梯有5包');
      expect(r.brand, '维达');
      expect(r.name, '纸巾');
      expect(r.quantity, 5);
    });

    test('"品牌是A" → 品牌=A', () {
      final r = DescriptionParser.parse(text: '纸巾品牌是清风放在楼梯');
      expect(r.brand, '清风');
      expect(r.name, '纸巾');
    });

    test('未出现"品牌"二字不识别品牌', () {
      final r = DescriptionParser.parse(text: '维达纸巾在楼梯有5包');
      expect(r.brand, isNull);
      expect(r.name, '维达纸巾');
    });
  });

  group('DescriptionParser 分类词库', () {
    const dict = [
      CategoryDictEntry(keyword: '纸巾', categoryKey: 'storage', categoryLabel: '收纳'),
      CategoryDictEntry(keyword: '心相印', categoryKey: 'storage', categoryLabel: '收纳'),
    ];

    test('词库关键词优先于 EmojiClassifier', () {
      final r = DescriptionParser.parse(text: '纸巾在楼梯有40包', categoryDict: dict);
      expect(r.categoryKey, 'storage');
      expect(r.categoryLabel, '收纳');
    });

    test('词库最长关键词优先', () {
      const dict2 = [
        CategoryDictEntry(keyword: '充电', categoryKey: 'digital', categoryLabel: '数码'),
        CategoryDictEntry(keyword: '充电线', categoryKey: 'tools', categoryLabel: '工具'),
      ];
      final r = DescriptionParser.parse(text: '充电线放在书房', categoryDict: dict2);
      expect(r.categoryLabel, '工具');
    });

    test('无词库命中时回退 EmojiClassifier', () {
      final r = DescriptionParser.parse(text: '数据线放在书房', categoryDict: dict);
      expect(r.categoryKey, 'digital');
      expect(r.categoryLabel, '数码');
    });

    test('词库与分类器都未命中 → 未分类', () {
      final r = DescriptionParser.parse(text: '纸巾在楼梯有40包');
      expect(r.categoryKey, '');
      expect(r.categoryLabel, '未分类');
    });
  });

  group('DescriptionParser.inferCategory（添加页共用）', () {
    test('词库命中返回分类', () {
      final r = DescriptionParser.inferCategory(
        name: '牙膏',
        dict: const [
          CategoryDictEntry(keyword: '牙膏', categoryKey: 'skincare', categoryLabel: '护肤'),
        ],
      );
      expect(r?.key, 'skincare');
      expect(r?.label, '护肤');
      expect(r?.source, 'dict');
    });

    test('未命中词库回退分类器并映射内置分类', () {
      final r = DescriptionParser.inferCategory(name: '口红');
      expect(r?.key, 'skincare');
      expect(r?.source, 'classifier');
    });

    test('完全未命中返回 null', () {
      expect(DescriptionParser.inferCategory(name: '纸巾'), isNull);
    });
  });

  group('DescriptionParser.parseAll（一句话多物品）', () {
    test('连词切分并继承位置', () {
      final items = DescriptionParser.parseAll(text: '客厅有纸巾和电池');
      expect(items.length, 2);
      expect(items[0].name, '纸巾');
      expect(items[1].name, '电池');
      expect(items[0].room?.name, '客厅');
      expect(items[1].room?.name, '客厅');
    });

    test('标点切分且各段自带位置', () {
      final items = DescriptionParser.parseAll(text: '楼梯有40包纸巾，书房有3节电池');
      expect(items.length, 2);
      expect(items[0].name, '纸巾');
      expect(items[0].quantity, 40);
      expect(items[0].room?.name, '楼梯');
      expect(items[1].name, '电池');
      expect(items[1].quantity, 3);
      expect(items[1].room?.name, '书房');
    });

    test('各段自带数量', () {
      final items = DescriptionParser.parseAll(text: '纸巾40包和牙膏2盒');
      expect(items.length, 2);
      expect(items[0].name, '纸巾');
      expect(items[0].quantity, 40);
      expect(items[1].name, '牙膏');
      expect(items[1].quantity, 2);
    });

    test('"调和油"被"和"误切时回退单物品解析', () {
      final items = DescriptionParser.parseAll(text: '调和油在厨房有2桶');
      expect(items.length, 1);
      expect(items[0].name, '调和油');
      expect(items[0].quantity, 2);
      expect(items[0].room?.name, '厨房');
    });

    test('单物品描述仍返回单元素列表', () {
      final items = DescriptionParser.parseAll(text: '纸巾在楼梯有40包');
      expect(items.length, 1);
      expect(items[0].name, '纸巾');
      expect(items[0].quantity, 40);
    });

    test('空输入返回单个兜底结果', () {
      final items = DescriptionParser.parseAll(text: '');
      expect(items.length, 1);
      expect(items[0].name, '未命名物品');
    });
  });
}
