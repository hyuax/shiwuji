import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../models/item.dart';
import '../services/notification_service.dart';
import 'database_provider.dart';
import 'item_providers.dart';

part 'generated/consumption_providers.g.dart';

/// 消耗记录展示模型。
/// 不直接暴露 drift 行类型：riverpod_generator 无法转换带前缀的生成类，
/// 同时也让 UI 层与数据库类型解耦。
class ConsumptionEntry {
  final String id;
  final int quantity;
  final String note;
  final DateTime createdAt;

  const ConsumptionEntry({
    required this.id,
    required this.quantity,
    required this.note,
    required this.createdAt,
  });
}

/// 物品的消耗记录（按时间倒序）。
@riverpod
Future<List<ConsumptionEntry>> consumptionRecordsByItem(
  Ref ref,
  String itemId,
) async {
  final rows = await ref.watch(consumptionDaoProvider).getByItem(itemId);
  return rows
      .map(
        (r) => ConsumptionEntry(
          id: r.id,
          quantity: r.quantity,
          note: r.note,
          createdAt: r.createdAt,
        ),
      )
      .toList();
}

/// 消耗动作：写消耗流水 + 扣减物品数量。
/// keepAlive：调用方（详情页）只用 ref.read(...notifier) 触发操作。
@Riverpod(keepAlive: true)
class ConsumptionActions extends _$ConsumptionActions {
  @override
  Future<void> build() async {}

  /// 消耗 [amount] 件；数量不足（amount > 现有数量）或非法时拒绝并返回 false。
  /// 扣减后若数量 ≤ 低库存阈值（阈值 > 0），推送库存不足通知。
  Future<bool> consumeItem({
    required Item item,
    required int amount,
    String note = '',
  }) async {
    if (amount < 1) return false;
    if (amount > item.quantity) return false;
    final dao = ref.read(consumptionDaoProvider);
    await dao.insertRecord(
      db.ConsumptionRecordsCompanion.insert(
        id: const Uuid().v4(),
        itemId: item.id,
        quantity: amount,
        note: Value(note),
        createdAt: DateTime.now(),
      ),
    );
    final updated = item.copyWith(quantity: item.quantity - amount);
    await ref.read(itemsProvider.notifier).updateItem(updated);
    ref.invalidate(consumptionRecordsByItemProvider(item.id));
    if (updated.isLowStock) {
      await NotificationService().showLowStock(updated);
    }
    return true;
  }
}
