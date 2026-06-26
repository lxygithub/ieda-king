import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';

/// Callback entry point for the foreground service isolate.
/// Runs in a background isolate — keeps process alive while uploads run
/// in the main isolate.
@pragma('vm:entry-point')
void uploadForegroundTaskCallback() {
  FlutterForegroundTaskPlatform.instance.setTaskHandler(UploadTaskHandler());
}

class UploadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Service started — keep alive
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No periodic work; upload runs in main isolate
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Cleanup
  }
}
