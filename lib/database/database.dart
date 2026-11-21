import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

// 表定义（part files）
part 'tables/items_table.dart';
part 'tables/rooms_table.dart';
part 'tables/cabinets_table.dart';
part 'tables/slots_table.dart';
part 'tables/space_items_table.dart';
part 'tables/import_history_table.dart';
part 'tables/categories_table.dart';
part 'tables/settings_table.dart';
part 'tables/consumption_records_table.dart';

// 种子数据
part 'seed_data.dart';

// 代码生成
part 'generated/database.g.dart';

@DriftDatabase(
  tables: [
    Items,
    Rooms,
    Cabinets,
    Slots,
    SpaceItems,
    ImportHistory,
    Categories,
    Settings,
    ConsumptionRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedDefaultData();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v2: 新增「是否借出」字段（is_borrowed，布尔，默认 false）
      // addColumn 为单条 DDL 且带默认值，幂等安全。
      if (from < 2) {
        await m.addColumn(items, items.isBorrowed);
      }
      // v3: 新增数量与单位字段（智能录入"40包纸巾"类场景）
      if (from < 3) {
        await m.addColumn(items, items.quantity);
        await m.addColumn(items, items.unit);
      }
      // v4: 新增物品消耗记录表（数量扣减流水）
      if (from < 4) {
        await m.createTable(consumptionRecords);
      }
      // v5: 新增低库存提醒阈值（0 = 未启用）
      if (from < 5) {
        await m.addColumn(items, items.lowStockThreshold);
      }
    },
  );

  /// 首次安装时写入默认种子数据：
  /// - 12 个内置分类
  /// - 2 项默认用户设置
  /// - 3 个默认收纳空间（卧室、厨房、客厅），含柜体结构和区域划分
  ///
  /// 不预置任何物品（Items）、空间物品（SpaceItems）或导入历史（ImportHistory）。
  Future<void> _seedDefaultData() async {
    await batch((b) {
      b.insertAll(categories, SeedData.categories);
      b.insertAll(settings, SeedData.settings);
      b.insertAll(rooms, SeedData.defaultRooms);
      b.insertAll(cabinets, SeedData.defaultCabinets);
      b.insertAll(slots, SeedData.defaultSlots);
    });
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'shiwuji',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
