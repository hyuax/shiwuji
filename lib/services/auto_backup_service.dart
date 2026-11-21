import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database.dart';
import 'webdav_service.dart';

/// 自动备份服务：退出应用时备份 / 每隔 X 天备份。
///
/// 备份位置可选：本地文件（应用文档目录 auto_backups/，保留最近 10 份）
/// 与 WebDAV 云端（复用 [WebDavService]，配置读取 settings 表 webdav_*）。
/// 所有配置持久化在 settings 表，由数据备份页的「自动备份」卡片管理。
class AutoBackupService {
  AutoBackupService._();
  static final AutoBackupService instance = AutoBackupService._();

  // ─── settings 表 key ───
  static const keyEnabled = 'auto_backup_enabled'; // 'true'/'false'，默认 false
  static const keyOnExit = 'auto_backup_on_exit'; // 退出/进入后台时备份
  static const keyIntervalDays = 'auto_backup_interval_days'; // 0 = 关闭
  static const keyTarget = 'auto_backup_target'; // local | cloud | both
  static const keyLastRun = 'last_auto_backup_at'; // ISO 时间

  /// 本地自动备份保留份数
  static const _localKeepCount = 10;

  /// 本次应用会话内是否已执行过退出备份（防止反复触发）
  bool _exitHandledThisSession = false;

  /// 读取 settings 表配置（key → value）
  Future<Map<String, String>> _readConfig(AppDatabase db) async {
    final rows = await db.select(db.settings).get();
    return {for (final r in rows) r.key: r.value};
  }

  Future<bool> _readEnabled(AppDatabase db) async {
    final cfg = await _readConfig(db);
    return cfg[keyEnabled] == 'true';
  }

  /// 上次自动备份时间（无记录为 null）
  Future<DateTime?> lastRunAt(AppDatabase db) async {
    final cfg = await _readConfig(db);
    return DateTime.tryParse(cfg[keyLastRun] ?? '');
  }

  /// 退出应用（进入后台/关闭窗口）时调用。
  /// 每次应用会话最多触发一次；未开启"退出时备份"则跳过。
  /// 返回结果描述（未触发/成功/失败原因），用于日志。
  Future<String?> maybeBackupOnExit(AppDatabase db) async {
    if (_exitHandledThisSession) return null;
    _exitHandledThisSession = true;
    if (!await _readEnabled(db)) return null;
    final cfg = await _readConfig(db);
    if (cfg[keyOnExit] != 'true') return null;
    return _run(db, reason: 'exit');
  }

  /// 应用启动时调用：距上次自动备份超过设定天数则执行。
  /// 返回结果描述（未触发/成功/失败原因），用于日志。
  Future<String?> maybeBackupOnInterval(AppDatabase db) async {
    if (!await _readEnabled(db)) return null;
    final cfg = await _readConfig(db);
    final days = int.tryParse(cfg[keyIntervalDays] ?? '') ?? 0;
    if (days <= 0) return null;
    final last = DateTime.tryParse(cfg[keyLastRun] ?? '');
    if (last != null &&
        DateTime.now().difference(last) < Duration(days: days)) {
      return null;
    }
    return _run(db, reason: 'interval');
  }

  /// 立即执行一次自动备份（备份页手动触发用）。
  Future<String> runNow(AppDatabase db) => _run(db, reason: 'manual');

  /// 执行备份：按 target 分别写本地文件 / 上传 WebDAV。
  /// 返回结果描述；任一目标失败会汇总在描述中。
  Future<String> _run(AppDatabase db, {required String reason}) async {
    final cfg = await _readConfig(db);
    final target = cfg[keyTarget] ?? 'local';
    final results = <String>[];

    // ─── 本地备份 ───
    if (target == 'local' || target == 'both') {
      try {
        final filename = await _backupLocal(db);
        results.add('本地：$filename');
      } catch (e) {
        debugPrint('[AutoBackup] 本地备份失败: $e');
        results.add('本地失败');
      }
    }

    // ─── 云端备份（WebDAV）───
    if (target == 'cloud' || target == 'both') {
      try {
        final webdav = WebDavService();
        final url = cfg['webdav_url'] ?? '';
        if (url.isEmpty) {
          results.add('云端：未配置 WebDAV');
        } else {
          webdav.configure(
            url,
            cfg['webdav_user'] ?? '',
            cfg['webdav_password'] ?? '',
            dir: cfg['webdav_dir']?.isEmpty ?? true ? null : cfg['webdav_dir'],
          );
          final filename = await webdav.backup(db);
          results.add('云端：$filename');
        }
      } catch (e) {
        debugPrint('[AutoBackup] 云端备份失败: $e');
        results.add('云端失败');
      }
    }

    // 记录本次执行时间（仅在有任一成功时）
    final anySuccess = results.any((r) => !r.contains('失败'));
    if (anySuccess) {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: keyLastRun,
              value: Value(DateTime.now().toIso8601String()),
            ),
          );
    }
    final summary = '自动备份($reason)：${results.join("；")}';
    debugPrint('[AutoBackup] $summary');
    return summary;
  }

  /// 本地备份：打包 ZIP 写入文档目录 auto_backups/，并清理旧备份（保留 10 份）。
  Future<String> _backupLocal(AppDatabase db) async {
    final data = await WebDavService().collectData(db);
    final itemCount = (data['items'] as List?)?.length ?? 0;
    final now = DateTime.now();
    final filename =
        'shiwuji_auto_backup_${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}'
        '_n$itemCount.zip';

    final docs = await getApplicationDocumentsDirectory();
    final dir = io.Directory('${docs.path}/auto_backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final archive = Archive();
    archive.addFile(
      ArchiveFile.string('data.json', jsonEncode(data)),
    );
    final zipBytes = ZipEncoder().encode(archive);
    final file = io.File('${dir.path}/$filename');
    await file.writeAsBytes(zipBytes);

    // 清理旧备份，只保留最近 [_localKeepCount] 份
    final files = dir
        .listSync()
        .whereType<io.File>()
        .where((f) => f.path.endsWith('.zip'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (var i = _localKeepCount; i < files.length; i++) {
      try {
        files[i].deleteSync();
      } catch (_) {}
    }
    debugPrint('[AutoBackup] 本地备份完成: $filename');
    return filename;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
