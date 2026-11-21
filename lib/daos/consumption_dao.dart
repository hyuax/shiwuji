import 'package:drift/drift.dart';
import '../database/database.dart';

part 'generated/consumption_dao.g.dart';

@DriftAccessor(tables: [ConsumptionRecords])
class ConsumptionDao extends DatabaseAccessor<AppDatabase>
    with _$ConsumptionDaoMixin {
  ConsumptionDao(super.db);

  /// 写入一条消耗流水
  Future<int> insertRecord(ConsumptionRecordsCompanion record) {
    return into(consumptionRecords).insert(record);
  }

  /// 按物品倒序查询消耗记录（最近的在前）
  Future<List<ConsumptionRecord>> getByItem(String itemId) {
    return (select(consumptionRecords)
          ..where((t) => t.itemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// 删除物品的全部消耗流水（物品删除时调用）
  Future<int> deleteByItem(String itemId) {
    return (delete(consumptionRecords)..where((t) => t.itemId.equals(itemId)))
        .go();
  }
}
