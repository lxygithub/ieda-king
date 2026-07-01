import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/timeline_provider.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/timeline_screen.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';

const _apiBaseUrl = 'http://192.227.212.20:18900';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Immersive status bar — transparent background, dark icons by default
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  await StorageService.instance.initialize();

  // Init API base (quick, no network)
  ApiService.instance.baseUrl = _apiBaseUrl;

  // Init auth (load persisted token from local storage only, no network)
  final authProvider = AuthProvider();
  await authProvider.init(); // Returns immediately after loading local token

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => TimelineProvider()),
      ],
      child: const ShareTimelineApp(),
    ),
  );

  // Init foreground task after UI is shown (non-blocking)
  // ignore: invalid_use_of_visible_for_testing_member
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'idea_king_upload',
        channelName: 'File Upload',
        channelDescription: 'Shows file upload progress',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  });
}

class ShareTimelineApp extends StatelessWidget {
  const ShareTimelineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Idea King',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ).copyWith(
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ).copyWith(
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const _AppEntry(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
      },
    );
  }
}

/// Shows a splash while AuthProvider initializes,
/// then routes to login or the main timeline.
class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(builder: (context, auth, _) {
      if (!auth.initialized) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      if (!auth.isLoggedIn) {
        return const LoginScreen();
      }
      return const _ShareReceiver();
    });
  }
}

/// Listens to share intents and forwards to TimelineProvider.
class _ShareReceiver extends StatefulWidget {
  const _ShareReceiver();

  @override
  State<_ShareReceiver> createState() => _ShareReceiverState();
}

class _ShareReceiverState extends State<_ShareReceiver> {
  @override
  void initState() {
    super.initState();
    _initShareListener();
  }

  void _initShareListener() {
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> files) {
      _processSharedFiles(files);
      ReceiveSharingIntent.instance.reset();
    });

    ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> files) {
      _processSharedFiles(files);
    });
  }

  Future<void> _processSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    final provider = context.read<TimelineProvider>();

    final textShares = files
        .where((f) =>
            f.type == SharedMediaType.text || f.type == SharedMediaType.url)
        .toList();
    final fileShares = files
        .where((f) =>
            f.type == SharedMediaType.file ||
            f.type == SharedMediaType.image ||
            f.type == SharedMediaType.video)
        .toList();

    for (final t in textShares) {
      final content = t.path;
      if (content.isNotEmpty) {
        await provider.ingestText(content);
      }
    }

    if (fileShares.isNotEmpty) {
      final paths = fileShares.map((f) => f.path).toList();
      await provider.ingestMultipleFiles(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const TimelineScreen();
  }
}
