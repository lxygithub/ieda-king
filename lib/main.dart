import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/timeline_provider.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/timeline_screen.dart';
import 'services/api_service.dart';
import 'services/s3_service.dart';

const _apiBaseUrl = 'http://192.227.212.20:8080';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init S3 config (fire-and-forget; S3Service loads from SharedPrefs)
  try {
    final s3 = S3Service();
    await s3.saveConfig(const S3Config(
      endpoint: '192.227.212.20',
      port: 13900,
      accessKey: 'GKcda0ccd3a856a1c1e1bd46b7',
      secretKey:
          '61a143bedcaa3379ced011172aae03ce1048e2b4ed44c8394a418f03af4db00a',
      bucket: 'idea-king',
      region: 'garage',
    ));
  } catch (e) {
    debugPrint('[init] S3 error: $e');
  }

  // Init API base
  ApiService.instance.baseUrl = _apiBaseUrl;

  // Init auth (load persisted token)
  final authProvider = AuthProvider();
  await authProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => TimelineProvider()),
      ],
      child: const ShareTimelineApp(),
    ),
  );
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
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      // Auth gate: show splash → login → timeline
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
    // Handle share while app was closed (cold start)
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> files) {
      _processSharedFiles(files);
      ReceiveSharingIntent.instance.reset();
    });

    // Handle share while app is running (warm start)
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
