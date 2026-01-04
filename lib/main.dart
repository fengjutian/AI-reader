import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/window_info.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/utils/error/common.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:heroine/heroine.dart';
import 'package:provider/provider.dart' as provider;
import 'package:window_manager/window_manager.dart';

/// 全局导航键，用于在整个应用中访问导航器
final navigatorKey = GlobalKey<NavigatorState>();

/// 音频处理器，用于控制TTS（文本转语音）的播放
late AudioHandler audioHandler;

/// Hero动画控制器，用于管理应用中的Hero动画效果
final heroineController = HeroineController();

/// 应用程序的入口点，负责初始化所有核心服务和组件
Future<void> main() async {
  // 初始化Flutter绑定，确保可以访问底层平台功能
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化应用偏好设置，加载用户配置
  await Prefs().initPrefs();

  // Windows平台特定的窗口管理设置
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    // 从偏好设置中恢复窗口大小和位置
    final size = Size(
      Prefs().windowInfo.width,
      Prefs().windowInfo.height,
    );
    final offset = Offset(
      Prefs().windowInfo.x,
      Prefs().windowInfo.y,
    );

    WindowManager.instance.setTitle('Anx Reader');

    // 如果有有效的窗口尺寸，恢复窗口位置和大小
    if (size.width > 0 && size.height > 0) {
      await WindowManager.instance.setPosition(offset);
      await WindowManager.instance.setSize(size);
    }

    // 显示并聚焦窗口
    await WindowManager.instance.show();
    await WindowManager.instance.focus();
  }

  // 初始化应用基础路径
  initBasePath();

  // 初始化日志系统
  AnxLog.init();

  // 初始化错误处理系统
  AnxError.init();

  // 初始化数据库
  await DBHelper().initDB();

  // 启动书籍播放器服务器
  Server().start();

  // 初始化音频服务，用于TTS（文本转语音）功能
  audioHandler = await AudioService.init(
    builder: () => TtsHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.anx.reader.tts.channel.audio',
      androidNotificationChannelName: 'ANX Reader TTS',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  // 配置SmartDialog对话框的样式和动画
  SmartDialog.config.custom = SmartConfigCustom(
    maskColor: Colors.black.withAlpha(35),
    useAnimation: true,
    animationType: SmartAnimationType.centerFade_otherSlide,
  );

  // 启动应用程序，使用ProviderScope提供状态管理
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

/// 应用程序的根组件，负责提供应用的整体结构和状态管理
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _MyAppState();
}

/// MyApp组件的状态类，负责管理应用生命周期和窗口事件
/// 实现了WidgetsBindingObserver接口以监听应用生命周期变化
/// 实现了WindowListener接口以监听Windows平台的窗口事件
class _MyAppState extends ConsumerState<MyApp>
    with WidgetsBindingObserver, WindowListener {
  /// 初始化组件状态
  /// 添加WidgetsBindingObserver监听应用生命周期变化
  /// 添加WindowListener监听Windows平台窗口事件
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
  }

  /// 销毁组件状态
  /// 移除WidgetsBindingObserver，避免内存泄漏
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 窗口移动时触发的回调
  /// 调用_updateWindowInfo保存新的窗口位置
  @override
  Future<void> onWindowMoved() async {
    await _updateWindowInfo();
  }

  /// 窗口大小改变时触发的回调
  /// 调用_updateWindowInfo保存新的窗口大小
  @override
  Future<void> onWindowResized() async {
    await _updateWindowInfo();
  }

  /// 更新窗口信息到偏好设置
  /// 仅在Windows平台上执行
  Future<void> _updateWindowInfo() async {
    if (!Platform.isWindows) {
      return;
    }
    // 获取当前窗口位置和大小
    final windowOffset = await windowManager.getPosition();
    final windowSize = await windowManager.getSize();

    // 保存窗口信息到偏好设置
    Prefs().windowInfo = WindowInfo(
      x: windowOffset.dx,
      y: windowOffset.dy,
      width: windowSize.width,
      height: windowSize.height,
    );

    // 记录窗口信息日志
    AnxLog.info('onWindowClose: Offset: $windowOffset, Size: $windowSize');
  }

  /// 监听应用生命周期状态变化的回调方法
  /// 根据不同的生命周期状态执行相应的操作
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // 当应用进入暂停或隐藏状态时
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // 如果WebDAV功能已启用，则触发双向数据同步
      if (Prefs().webdavStatus) {
        ref
            .read(syncProvider.notifier)
            .syncData(SyncDirection.both, ref, trigger: SyncTrigger.auto);
      }
    }
    // 当应用从后台恢复时
    else if (state == AppLifecycleState.resumed) {
      // 在iOS平台上重启服务器（解决iOS平台后台限制问题）
      if (Platform.isIOS) {
        Server().start();
      }
    }
  }

  /// 构建应用的整体界面结构
  /// 提供应用的主题、本地化、导航等核心配置
  @override
  Widget build(BuildContext context) {
    // 使用MultiProvider提供应用级别的状态管理
    return provider.MultiProvider(
      providers: [
        // 提供偏好设置的ChangeNotifier，使整个应用可以访问用户配置
        provider.ChangeNotifierProvider(
          create: (_) => Prefs(),
        ),
      ],
      // 使用Consumer监听偏好设置变化，实现实时主题和语言切换
      child: provider.Consumer<Prefs>(
        builder: (context, prefsNotifier, child) {
          // MaterialApp是Flutter应用的核心组件，提供应用的基本结构
          return MaterialApp(
            // 隐藏调试横幅
            debugShowCheckedModeBanner: false,
            // 配置滚动行为，使用弹跳滚动效果
            scrollBehavior: ScrollConfiguration.of(context).copyWith(
              physics: const BouncingScrollPhysics(),
              // 注释掉的触摸设备配置，可用于支持更多输入设备
              // dragDevices: {
              //   PointerDeviceKind.touch,
              //   PointerDeviceKind.mouse,
              // },
            ),
            // 导航观察者，用于监控导航事件
            navigatorObservers: [
              FlutterSmartDialog.observer, // SmartDialog对话框的观察者
              heroineController // Hero动画控制器
            ],
            // 配置SmartDialog的构建器
            builder: FlutterSmartDialog.init(),
            // 全局导航键，用于在整个应用中访问导航器
            navigatorKey: navigatorKey,
            // 应用语言设置，从偏好设置中获取
            locale: prefsNotifier.locale,
            // 本地化代理，支持多语言
            localizationsDelegates: L10n.localizationsDelegates,
            // 支持的语言列表
            supportedLocales: L10n.supportedLocales,
            // 应用标题
            title: 'Anx',
            // 主题模式（浅色/深色/跟随系统），从偏好设置中获取
            themeMode: prefsNotifier.themeMode,
            // 浅色主题配置
            theme: colorSchema(prefsNotifier, context, Brightness.light),
            // 深色主题配置
            darkTheme: colorSchema(prefsNotifier, context, Brightness.dark),
            // 应用的主页
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
