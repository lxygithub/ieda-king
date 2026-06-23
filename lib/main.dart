import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'l10n/app_localizations.dart';
import 'providers/timeline_provider.dart';
import 'screens/timeline_screen.dart';
import 'services/remote_db_service.dart';
import 'services/s3_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initS3();
  await _initMySQL();
  runApp(const ShareTimelineApp());
}

Future<void> _initMySQL() async {
  await RemoteDbService.saveConfig(const MySQLConfig(
      host: '192.227.212.20',
      port: 15639,
      user: 'root',
      password: 'mysql_ktXzzs',
      database: 'idea_king',
    ));
}

Future<void> _initS3() async {
  final s3 = S3Service();
  await s3.loadConfig();
  if (!s3.isConfigured) {
    await s3.saveConfig(const S3Config(
      endpoint: 'http://192.227.212.20:13900',
      accessKey: 'GKcda0ccd3a856a1c1e1bd46b7',
      secretKey: '61a143bedcaa3379ced011172aae03ce1048e2b4ed44c8394a418f03af4db00a',
      bucket: 'idea-king',
      region: 'garage',
    ));
  }
}

class ShareTimelineApp extends StatelessWidget {
  const ShareTimelineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TimelineProvider(),
      child: MaterialApp(
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
        home: const _ShareReceiver(),
      ),
    );
  }
}

/// Listens to share intents and forwards to TimelineProvider
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
      // Mark as handled so they don't repeat
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
    if (files.isEmpty) return;
    if (!mounted) return;
    final provider = context.read<TimelineProvider>();

    // Separate text and file shares
    final textShares =
        files.where((f) => f.type == SharedMediaType.text || f.type == SharedMediaType.url).toList();
    final fileShares =
        files.where((f) => f.type == SharedMediaType.file || f.type == SharedMediaType.image || f.type == SharedMediaType.video).toList();

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
