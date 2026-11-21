// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../consumption_dao.dart';

// ignore_for_file: type=lint
mixin _$ConsumptionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ConsumptionRecordsTable get consumptionRecords =>
      attachedDatabase.consumptionRecords;
  ConsumptionDaoManager get managers => ConsumptionDaoManager(this);
}

class ConsumptionDaoManager {
  final _$ConsumptionDaoMixin _db;
  ConsumptionDaoManager(this._db);
  $$ConsumptionRecordsTableTableManager get consumptionRecords =>
      $$ConsumptionRecordsTableTableManager(
        _db.attachedDatabase,
        _db.consumptionRecords,
      );
}
