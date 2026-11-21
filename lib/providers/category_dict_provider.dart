import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/category_dictionary.dart';
import '../services/description_parser.dart';
import 'database_provider.dart';

part 'generated/category_dict_provider.g.dart';

/// 合并后的分类识别词库（内置 + 用户自定义）。
/// 一句话解析与添加页自动分类共用；自定义词条写入 settings 表。
@Riverpod(keepAlive: true)
Future<List<CategoryDictEntry>> categoryDict(Ref ref) async {
  final dao = ref.watch(settingsDaoProvider);
  final raw = await dao.getValue(CategoryDictionary.settingsKey);
  return [
    ...CategoryDictionary.builtIn,
    ...CategoryDictionary.decodeCustom(raw),
  ];
}

/// 仅用户自定义的词条（词库管理页展示/删除用）。
@Riverpod(keepAlive: true)
Future<List<CategoryDictEntry>> customCategoryDict(Ref ref) async {
  final dao = ref.watch(settingsDaoProvider);
  final raw = await dao.getValue(CategoryDictionary.settingsKey);
  return CategoryDictionary.decodeCustom(raw);
}

/// 词库管理动作（新增/删除自定义词条）。
/// keepAlive：调用方只用 ref.read(...notifier) 触发操作、不监听。
@Riverpod(keepAlive: true)
class CategoryDictActions extends _$CategoryDictActions {
  @override
  Future<void> build() async {}

  /// 新增（或覆盖同关键词的）自定义词条
  Future<void> addEntry({
    required String keyword,
    required String categoryKey,
    required String categoryLabel,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final raw = await dao.getValue(CategoryDictionary.settingsKey);
    final custom = [...CategoryDictionary.decodeCustom(raw)];
    custom.removeWhere((e) => e.keyword == keyword);
    custom.add(
      CategoryDictEntry(
        keyword: keyword,
        categoryKey: categoryKey,
        categoryLabel: categoryLabel,
      ),
    );
    await dao.setValue(
      CategoryDictionary.settingsKey,
      CategoryDictionary.encodeCustom(custom),
    );
    ref
      ..invalidate(categoryDictProvider)
      ..invalidate(customCategoryDictProvider);
  }

  /// 删除自定义词条（仅影响自定义；内置词库不受影响）
  Future<void> removeEntry(String keyword) async {
    final dao = ref.read(settingsDaoProvider);
    final raw = await dao.getValue(CategoryDictionary.settingsKey);
    final custom =
        [...CategoryDictionary.decodeCustom(raw)]
          ..removeWhere((e) => e.keyword == keyword);
    await dao.setValue(
      CategoryDictionary.settingsKey,
      CategoryDictionary.encodeCustom(custom),
    );
    ref
      ..invalidate(categoryDictProvider)
      ..invalidate(customCategoryDictProvider);
  }
}
