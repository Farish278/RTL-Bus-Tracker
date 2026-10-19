import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../../../core/network/request_scheduler.dart';
import '../../../../core/utils/debug_log.dart';
import '../../domain/entities/resource_update.dart';
import '../../domain/repositories/map_repository.dart';

/// Transfers polling ownership only after the local subscription is cancelled.
/// The service expires abandoned view leases when the UI process disappears.
class ServiceLiveBridge {
  ServiceLiveBridge(
    this.repository, {
    FlutterBackgroundService? service,
    this.heartbeatInterval = const Duration(seconds: 3),
  }) : _service = service ?? FlutterBackgroundService();
  final Duration heartbeatInterval;
  final MapRepository repository;
  final FlutterBackgroundService _service;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<LiveSnapshot> watch(List<String> routes) {
    if (!supported) return repository.watchLiveSnapshots(routes);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    late StreamController<LiveSnapshot> output;
    StreamSubscription<LiveSnapshot>? local;
    StreamSubscription<Map<String, dynamic>?>? remote;
    Timer? heartbeat;
    var closed = false;
    var checking = false;
    var ownedByService = false;
    Future<void> reconcile() async {
      if (checking || closed) return;
      checking = true;
      try {
        final running = await _service.isRunning();
        if (closed) return;
        if (running) {
          RequestScheduler.shared.limit = 2;
          await local?.cancel();
          local = null;
          if (closed) return;
          ownedByService = true;
          _service.invoke('live_watch', {'id': id, 'routes': routes});
        } else {
          RequestScheduler.shared.limit = 4;
          ownedByService = false;
          local ??= repository
              .watchLiveSnapshots(routes)
              .listen(output.add, onError: output.addError);
        }
      } catch (error) {
        DebugLog.throttled(
          'service_live_handoff',
          'Polling handoff failed: $error',
          interval: const Duration(seconds: 30),
        );
        if (!closed && !ownedByService) {
          local ??= repository
              .watchLiveSnapshots(routes)
              .listen(output.add, onError: output.addError);
        }
      } finally {
        checking = false;
      }
    }

    output = StreamController<LiveSnapshot>(
      onListen: () {
        remote = _service.on('live_snapshot').listen((message) {
          if (closed ||
              !ownedByService ||
              message == null ||
              message['id'] != id) {
            return;
          }
          final snapshot = LiveSnapshot.fromJson(
            Map<String, dynamic>.from(message['snapshot']),
          );
          if (routes.contains(snapshot.routeCode)) output.add(snapshot);
        });
        unawaited(reconcile());
        heartbeat = Timer.periodic(
          heartbeatInterval,
          (_) => unawaited(reconcile()),
        );
      },
      onCancel: () async {
        closed = true;
        heartbeat?.cancel();
        _service.invoke('live_unwatch', {'id': id});
        await local?.cancel();
        await remote?.cancel();
        // The alert service may continue running, so keep the UI's two-slot reserve.
      },
    );
    return output.stream;
  }
}
