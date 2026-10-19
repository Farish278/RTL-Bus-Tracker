import 'dart:async';
import 'package:dio/dio.dart';

/// UI and service reserve two slots each while the service is running.
class RequestScheduler {
  RequestScheduler({this.limit = 4});
  static final shared = RequestScheduler(limit: 2);
  int limit;
  int _active = 0;
  final List<Completer<void>> _serviceReservations = [];
  final List<_Pending> _queue = [];

  /// Drain excess UI work before a second isolate starts its two-slot pool.
  Future<void> reserveForService() async {
    limit = 2;
    if (_active <= 2) return;
    final ready = Completer<void>();
    _serviceReservations.add(ready);
    await ready.future;
  }

  Future<T> run<T>(
    Future<T> Function() job, {
    int priority = 1,
    CancelToken? cancelToken,
  }) async {
    final pending = _Pending(priority);
    _queue.add(pending);
    _queue.sort((a, b) => a.priority.compareTo(b.priority));
    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancel.then((error) {
          if (_queue.remove(pending)) pending.ready.completeError(error);
        }),
      );
    }
    _drain();
    await pending.ready.future;
    try {
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      return await job();
    } finally {
      _active--;
      _drain();
    }
  }

  void _drain() {
    if (_active <= 2) {
      for (final ready in _serviceReservations) {
        ready.complete();
      }
      _serviceReservations.clear();
    }
    while (_active < limit && _queue.isNotEmpty) {
      _active++;
      _queue.removeAt(0).ready.complete();
    }
  }
}

class _Pending {
  _Pending(this.priority);
  final int priority;
  final ready = Completer<void>();
}
