import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_router.dart';
import 'providers/database_provider.dart';
import 'services/app_settings_service.dart';
import 'services/auto_backup_service.dart';
import 'services/notification_service.dart';
import 'services/first_run_service.dart';
import 'services/encryption_service.dart';
import 'utils/package_info_setup_web.dart'
    if (dart.library.io) 'utils/package_info_setup_io.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerPackageInfoPlus();

  // 加载 .env 配置文件（含 BUGSNAG_API_KEY 等敏感信息）
  await dotenv.load(fileName: '.env');

  // 启动 Bugsnag 崩溃监控，API Key 从 .env 读取
  final bugsnagApiKey = dotenv.env['BUGSNAG_API_KEY'] ?? '';
  if (bugsnagApiKey.isNotEmpty) {
    await bugsnag.start(apiKey: bugsnagApiKey);
  }

  await NotificationService().init();
  await FirstRunService.init();
  await EncryptionService.instance.init();
  // 预加载首页背景图，避免首次渲染时闪烁
  await rootBundle.load('assets/icon/background1.jpg');
  runApp(ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  /// 路由：启动页偏好异步加载完成后才创建（加载期间显示过渡 loading）
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRouter();
    // 启动时加载通知偏好（保修/保质期提醒开关与天数），
    // 确保后续新增/编辑物品调度使用用户已保存的配置。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadNotificationPrefs(),
    );
    // 启动后延迟检查"每隔 X 天自动备份"（等首页渲染完再跑，不阻塞启动）
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _autoBackupOnInterval();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台 / 关闭窗口（detached）时触发"退出应用自动备份"
    // （每次应用会话最多执行一次，由服务内部去重）
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoBackupOnExit();
    }
  }

  Future<void> _autoBackupOnExit() async {
    try {
      final db = ref.read(databaseProvider);
      final result = await AutoBackupService.instance.maybeBackupOnExit(db);
      if (result != null) debugPrint('[MyApp] $result');
    } catch (e) {
      debugPrint('[MyApp] 退出自动备份失败: $e');
    }
  }

  Future<void> _autoBackupOnInterval() async {
    try {
      final db = ref.read(databaseProvider);
      final result = await AutoBackupService.instance.maybeBackupOnInterval(db);
      if (result != null) debugPrint('[MyApp] $result');
    } catch (e) {
      debugPrint('[MyApp] 定期自动备份失败: $e');
    }
  }

  /// 创建路由：首次启动走 splash；否则按「应用设置 → 启动页」进入。
  Future<void> _initRouter() async {
    String initialLocation;
    if (FirstRunService.isFirstRun) {
      initialLocation = '/';
    } else {
      try {
        final dao = ref.read(settingsDaoProvider);
        final value = await dao.getValue(AppSettingsService.keyStartupPage);
        initialLocation = AppSettingsService.locationFor(value);
      } catch (_) {
        initialLocation = '/home';
      }
    }
    if (!mounted) return;
    setState(() {
      _router = createAppRouter(initialLocation: initialLocation);
    });
  }

  Future<void> _loadNotificationPrefs() async {
    try {
      final dao = ref.read(settingsDaoProvider);
      await NotificationService().loadPreferences((key) => dao.getValue(key));
      debugPrint('[MyApp] 通知偏好加载完成');
    } catch (e) {
      debugPrint('[MyApp] 加载通知偏好失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (router == null) {
      // 启动页偏好读取期间的过渡页（通常一闪而过）
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp.router(
      title: '拾物记',
      theme: ThemeData(primarySwatch: Colors.amber),
      routerConfig: router,
      // 关闭 debug 构建右上角的 "DEBUG" 横幅
      debugShowCheckedModeBanner: false,
    );
  }
}
