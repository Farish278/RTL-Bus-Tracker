import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/utils/debug_log.dart';
import 'features/map/data/background/foreground_alert_service.dart';
import 'app/app.dart';

final ValueNotifier<StartupErrorState?> startupErrorNotifier =
    ValueNotifier<StartupErrorState?>(null);
bool _isStartupPhase = true;

class StartupErrorState {
  const StartupErrorState(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      DebugLog.info('App startup begin');

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _reportStartupError(
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        _reportStartupError(error, stack);
        return true;
      };

      runApp(const ProviderScope(child: RtlBusTrackerBootstrap()));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isStartupPhase = false;
      });
      DebugLog.info('App startup first frame scheduled');
    },
    (error, stack) {
      _reportStartupError(error, stack);
    },
  );
}

void _reportStartupError(Object error, StackTrace stack) {
  if (_isStartupPhase) {
    DebugLog.info('Startup error: $error');
    startupErrorNotifier.value = StartupErrorState(error, stack);
    return;
  }
  DebugLog.info('Runtime error (non-startup): $error');
  DebugLog.info('Runtime stack: $stack');
}

class RtlBusTrackerBootstrap extends StatefulWidget {
  const RtlBusTrackerBootstrap({super.key});

  @override
  State<RtlBusTrackerBootstrap> createState() => _RtlBusTrackerBootstrapState();
}

class _RtlBusTrackerBootstrapState extends State<RtlBusTrackerBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
      unawaited(
        ForegroundAlertService.initialize().catchError((e, st) {
          _reportStartupError(e, st);
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const RtlBusTrackerApp();
}
