part of '../database.dart';

/// 物品消耗记录（数量扣减流水）。
/// itemId 为物品 id 的弱引用：物品删除时由 ItemsProvider.removeItem 清理对应流水。
class ConsumptionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text()();
  // 本次消耗的数量（≥1）
  IntColumn get quantity => integer()();
  // 消耗备注（如"用完了""送人"），可为空
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
