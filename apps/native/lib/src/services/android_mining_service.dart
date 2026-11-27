import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void mineMeForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(MineMeMiningTaskHandler());
}

class MineMeMiningTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({'type': 'foreground-started'});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'foreground-heartbeat',
      'at': timestamp.toIso8601String(),
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    FlutterForegroundTask.sendDataToMain({'type': 'foreground-destroyed'});
  }
}

class AndroidMiningService {
  static bool _initialised = false;

  static void initialise() {
    if (!Platform.isAndroid || _initialised) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mine_me_randomx',
        channelName: 'MINE-ME · Minage',
        channelDescription: 'Indique lorsqu’une session de calcul MINE-ME est active.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialised = true;
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    initialise();
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      final requested = await FlutterForegroundTask.requestNotificationPermission();
      if (requested != NotificationPermission.granted) {
        throw Exception('Autorisez la notification persistante pour démarrer le minage Android.');
      }
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 671,
      serviceTypes: const [ForegroundServiceTypes.specialUse],
      notificationTitle: 'MINE-ME · Calcul actif',
      notificationText: 'Votre appareil contribue au pool central HashVault.',
      callback: mineMeForegroundCallback,
    );
    if (result is ServiceRequestFailure) {
      throw Exception('Android n’a pas autorisé le service de minage en premier plan.');
    }
  }

  static Future<void> update(String text) async {
    if (!Platform.isAndroid || !await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(notificationText: text);
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid || !await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}
