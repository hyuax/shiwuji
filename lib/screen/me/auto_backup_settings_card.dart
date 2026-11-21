import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import 'package:shi_wu_ji/constants/app_colors.dart';
import 'package:shi_wu_ji/database/database.dart';
import 'package:shi_wu_ji/providers/database_provider.dart';
import 'package:shi_wu_ji/services/auto_backup_service.dart';
import 'package:shi_wu_ji/widgets/toast_utils.dart';

/// 数据备份页的「自动备份」设置卡片：
/// 总开关、备份位置（本地/云端/两者）、退出时备份、间隔天数、上次备份时间。
class AutoBackupSettingsCard extends ConsumerStatefulWidget {
  const AutoBackupSettingsCard({super.key});

  @override
  ConsumerState<AutoBackupSettingsCard> createState() =>
      _AutoBackupSettingsCardState();
}

class _AutoBackupSettingsCardState
    extends ConsumerState<AutoBackupSettingsCard> {
  bool _loading = true;
  bool _enabled = false;
  bool _onExit = true;
  int _intervalDays = 7;
  String _target = 'local'; // local | cloud | both
  DateTime? _lastRun;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(databaseProvider);
      final rows = await db.select(db.settings).get();
      final map = {for (final r in rows) r.key: r.value};
      if (!mounted) return;
      setState(() {
        _enabled = map[AutoBackupService.keyEnabled] == 'true';
        _onExit = map[AutoBackupService.keyOnExit] != 'false';
        _intervalDays =
            int.tryParse(map[AutoBackupService.keyIntervalDays] ?? '') ?? 7;
        _target = map[AutoBackupService.keyTarget] ?? 'local';
        _lastRun = DateTime.tryParse(map[AutoBackupService.keyLastRun] ?? '');
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, String value) async {
    try {
      final db = ref.read(databaseProvider);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: key, value: Value(value)),
          );
    } catch (_) {
      if (mounted) ToastUtils.show(context, '保存失败，请重试');
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _enabled = value);
    await _set(AutoBackupService.keyEnabled, value ? 'true' : 'false');
    if (mounted) {
      ToastUtils.show(context, value ? '自动备份已开启' : '自动备份已关闭');
    }
  }

  Future<void> _toggleOnExit(bool value) async {
    setState(() => _onExit = value);
    await _set(AutoBackupService.keyOnExit, value ? 'true' : 'false');
  }

  Future<void> _setIntervalDays(String raw) async {
    final days = int.tryParse(raw.trim()) ?? 0;
    final safe = days < 0 ? 0 : days;
    setState(() => _intervalDays = safe);
    await _set(AutoBackupService.keyIntervalDays, safe.toString());
  }

  Future<void> _setTarget(String value) async {
    setState(() => _target = value);
    await _set(AutoBackupService.keyTarget, value);
  }

  Future<void> _runNow() async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    try {
      final db = ref.read(databaseProvider);
      final summary = await AutoBackupService.instance.runNow(db);
      if (!mounted) return;
      ToastUtils.show(context, summary);
      setState(() {
        _lastRun = DateTime.now();
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRunning = false);
      ToastUtils.show(context, '备份失败：${e.toString().split('\n').first}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 120,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '自动备份',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Switch(value: _enabled, onChanged: _toggleEnabled),
            ],
          ),
          if (_enabled) ...[
            const Divider(height: 16, color: AppColors.border),
            _buildSectionLabel('备份位置'),
            const SizedBox(height: 8),
            _buildTargetChips(),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.primary,
              title: const Text(
                '退出应用时自动备份',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                '切到后台或关闭应用时触发',
                style: TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
              value: _onExit,
              onChanged: _toggleOnExit,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.primary,
              title: const Text(
                '每隔 X 天自动备份',
                style: TextStyle(fontSize: 13),
              ),
              value: _intervalDays > 0,
              onChanged: (on) => _setIntervalDays(
                (on ? (_intervalDays > 0 ? _intervalDays : 7) : 0).toString(),
              ),
            ),
            if (_intervalDays > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text('间隔天数：', style: TextStyle(fontSize: 13)),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: TextEditingController(
                          text: _intervalDays.toString(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        onSubmitted: _setIntervalDays,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '天（下次启动时检查）',
                      style: TextStyle(fontSize: 12, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16, color: AppColors.border),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _lastRun == null
                        ? '尚未自动备份过'
                        : '上次自动备份：${_lastRun!.month}月${_lastRun!.day}日 ${_lastRun!.hour.toString().padLeft(2, '0')}:${_lastRun!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _runNow,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDeep],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isRunning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '立即备份',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTargetChips() {
    Widget chip(String value, String label, IconData icon) {
      final active = _target == value;
      return GestureDetector(
        onTap: () => _setTarget(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF3CC) : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
              width: 1.3,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: active ? AppColors.primaryDark : AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primaryDark : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('local', '本地', Icons.phone_android_outlined),
        const SizedBox(width: 8),
        chip('cloud', '云端 WebDAV', Icons.cloud_outlined),
        const SizedBox(width: 8),
        chip('both', '两者都备', Icons.done_all_outlined),
      ],
    );
  }
}
