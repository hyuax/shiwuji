// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../category_dict_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 合并后的分类识别词库（内置 + 用户自定义）。
/// 一句话解析与添加页自动分类共用；自定义词条写入 settings 表。

@ProviderFor(categoryDict)
final categoryDictProvider = CategoryDictProvider._();

/// 合并后的分类识别词库（内置 + 用户自定义）。
/// 一句话解析与添加页自动分类共用；自定义词条写入 settings 表。

final class CategoryDictProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CategoryDictEntry>>,
          List<CategoryDictEntry>,
          FutureOr<List<CategoryDictEntry>>
        >
    with
        $FutureModifier<List<CategoryDictEntry>>,
        $FutureProvider<List<CategoryDictEntry>> {
  /// 合并后的分类识别词库（内置 + 用户自定义）。
  /// 一句话解析与添加页自动分类共用；自定义词条写入 settings 表。
  CategoryDictProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'categoryDictProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$categoryDictHash();

  @$internal
  @override
  $FutureProviderElement<List<CategoryDictEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CategoryDictEntry>> create(Ref ref) {
    return categoryDict(ref);
  }
}

String _$categoryDictHash() => r'189a6c8abcd7cd30b657b47fb6ca7dd941d05aa5';

/// 仅用户自定义的词条（词库管理页展示/删除用）。

@ProviderFor(customCategoryDict)
final customCategoryDictProvider = CustomCategoryDictProvider._();

/// 仅用户自定义的词条（词库管理页展示/删除用）。

final class CustomCategoryDictProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CategoryDictEntry>>,
          List<CategoryDictEntry>,
          FutureOr<List<CategoryDictEntry>>
        >
    with
        $FutureModifier<List<CategoryDictEntry>>,
        $FutureProvider<List<CategoryDictEntry>> {
  /// 仅用户自定义的词条（词库管理页展示/删除用）。
  CustomCategoryDictProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'customCategoryDictProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$customCategoryDictHash();

  @$internal
  @override
  $FutureProviderElement<List<CategoryDictEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CategoryDictEntry>> create(Ref ref) {
    return customCategoryDict(ref);
  }
}

String _$customCategoryDictHash() =>
    r'44a7e6fb413aa7ce89e818600becc02eb0d3e853';

/// 词库管理动作（新增/删除自定义词条）。
/// keepAlive：调用方只用 ref.read(...notifier) 触发操作、不监听。

@ProviderFor(CategoryDictActions)
final categoryDictActionsProvider = CategoryDictActionsProvider._();

/// 词库管理动作（新增/删除自定义词条）。
/// keepAlive：调用方只用 ref.read(...notifier) 触发操作、不监听。
final class CategoryDictActionsProvider
    extends $AsyncNotifierProvider<CategoryDictActions, void> {
  /// 词库管理动作（新增/删除自定义词条）。
  /// keepAlive：调用方只用 ref.read(...notifier) 触发操作、不监听。
  CategoryDictActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'categoryDictActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$categoryDictActionsHash();

  @$internal
  @override
  CategoryDictActions create() => CategoryDictActions();
}

String _$categoryDictActionsHash() =>
    r'53d972accb250dc3860e2d6f3f36ae934097a600';

/// 词库管理动作（新增/删除自定义词条）。
/// keepAlive：调用方只用 ref.read(...notifier) 触发操作、不监听。

abstract class _$CategoryDictActions extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
