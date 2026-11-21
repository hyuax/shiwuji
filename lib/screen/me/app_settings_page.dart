import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shi_wu_ji/constants/app_colors.dart';
import 'package:shi_wu_ji/providers/database_provider.dart';
import 'package:shi_wu_ji/services/app_settings_service.dart';
import 'package:shi_wu_ji/widgets/toast_utils.dart';

/// 应用设置页：启动页等通用偏好。
class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  /// 当前启动页设置值；null = 加载中
  String? _startupPage;

  @override
  void initState() {
    super.initState();
    _loadStartupPage();
  }

  Future<void> _loadStartupPage() async {
    try {
      final dao = ref.read(settingsDaoProvider);
      final value = await dao.getValue(AppSettingsService.keyStartupPage);
      if (!mounted) return;
      setState(() => _startupPage = value ?? 'home');
    } catch (_) {
      if (mounted) setState(() => _startupPage = 'home');
    }
  }

  Future<void> _setStartupPage(String value) async {
    setState(() => _startupPage = value);
    try {
      final dao = ref.read(settingsDaoProvider);
      await dao.setValue(AppSettingsService.keyStartupPage, value);
      if (!mounted) return;
      final name = AppSettingsService.startupOptions
          .firstWhere((o) => o.$1 == value)
          .$2;
      ToastUtils.show(context, '启动页已设为「$name」，下次启动生效');
    } catch (_) {
      if (mounted) ToastUtils.show(context, '保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  _buildSectionTitle('启动页'),
                  const SizedBox(height: 8),
                  _buildStartupCard(),
                  const SizedBox(height: 8),
                  const Text(
                    '设置打开应用后默认进入的页面，下次启动生效。',
                    style: TextStyle(fontSize: 11, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '应用设置',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildStartupCard() {
    // 加载中显示骨架
    if (_startupPage == null) {
      return Container(
        height: 200,
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < AppSettingsService.startupOptions.length; i++)
            ...[
              _buildOptionTile(AppSettingsService.startupOptions[i]),
              if (i < AppSettingsService.startupOptions.length - 1)
                const Divider(height: 1, color: AppColors.border),
            ],
        ],
      ),
    );
  }

  Widget _buildOptionTile((String, String, String) option) {
    final value = option.$1;
    final name = option.$2;
    final emoji = option.$3;
    final isSelected = _startupPage == value;
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 20)),
      title: Text(name, style: const TextStyle(fontSize: 15)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.accentGold, size: 20)
          : null,
      onTap: () => _setStartupPage(value),
    );
  }
}
