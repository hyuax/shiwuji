// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../consumption_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 物品的消耗记录（按时间倒序）。

@ProviderFor(consumptionRecordsByItem)
final consumptionRecordsByItemProvider = ConsumptionRecordsByItemFamily._();

/// 物品的消耗记录（按时间倒序）。

final class ConsumptionRecordsByItemProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ConsumptionEntry>>,
          List<ConsumptionEntry>,
          FutureOr<List<ConsumptionEntry>>
        >
    with
        $FutureModifier<List<ConsumptionEntry>>,
        $FutureProvider<List<ConsumptionEntry>> {
  /// 物品的消耗记录（按时间倒序）。
  ConsumptionRecordsByItemProvider._({
    required ConsumptionRecordsByItemFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'consumptionRecordsByItemProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$consumptionRecordsByItemHash();

  @override
  String toString() {
    return r'consumptionRecordsByItemProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ConsumptionEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ConsumptionEntry>> create(Ref ref) {
    final argument = this.argument as String;
    return consumptionRecordsByItem(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ConsumptionRecordsByItemProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$consumptionRecordsByItemHash() =>
    r'5996f5a35a5fa57f72d88fd7c07bcaf3e2431484';

/// 物品的消耗记录（按时间倒序）。

final class ConsumptionRecordsByItemFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ConsumptionEntry>>, String> {
  ConsumptionRecordsByItemFamily._()
    : super(
        retry: null,
        name: r'consumptionRecordsByItemProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 物品的消耗记录（按时间倒序）。

  ConsumptionRecordsByItemProvider call(String itemId) =>
      ConsumptionRecordsByItemProvider._(argument: itemId, from: this);

  @override
  String toString() => r'consumptionRecordsByItemProvider';
}

/// 消耗动作：写消耗流水 + 扣减物品数量。
/// keepAlive：调用方（详情页）只用 ref.read(...notifier) 触发操作。

@ProviderFor(ConsumptionActions)
final consumptionActionsProvider = ConsumptionActionsProvider._();

/// 消耗动作：写消耗流水 + 扣减物品数量。
/// keepAlive：调用方（详情页）只用 ref.read(...notifier) 触发操作。
final class ConsumptionActionsProvider
    extends $AsyncNotifierProvider<ConsumptionActions, void> {
  /// 消耗动作：写消耗流水 + 扣减物品数量。
  /// keepAlive：调用方（详情页）只用 ref.read(...notifier) 触发操作。
  ConsumptionActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'consumptionActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$consumptionActionsHash();

  @$internal
  @override
  ConsumptionActions create() => ConsumptionActions();
}

String _$consumptionActionsHash() =>
    r'acea03f7afcc5d904a4ed81959b69097694e4488';

/// 消耗动作：写消耗流水 + 扣减物品数量。
/// keepAlive：调用方（详情页）只用 ref.read(...notifier) 触发操作。

abstract class _$ConsumptionActions extends $AsyncNotifier<void> {
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
