/// 应用通用设置（启动页等），持久化在 Settings 表。
class AppSettingsService {
  AppSettingsService._();

  /// 启动页设置在 settings 表中的存储 key
  static const String keyStartupPage = 'startup_page';

  /// 可选启动页（value, 显示名, emoji）
  static const List<(String, String, String)> startupOptions = [
    ('home', '首页', '🏠'),
    ('inventory', '物品库', '📦'),
    ('storage', '收纳位置', '🗄️'),
    ('me', '我的', '👤'),
  ];

  /// 设置值 → 路由 location；未知值回退首页。
  static String locationFor(String? value) {
    switch (value) {
      case 'inventory':
        return '/inventory';
      case 'storage':
        return '/storage';
      case 'me':
        return '/me';
      case 'home':
      default:
        return '/home';
    }
  }
}
