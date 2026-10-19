import 'dart:convert';
import 'package:dio/dio.dart';

/// Session counters. Content-Length is encoded payload size when supplied by
/// the server; decoded JSON size is tracked separately, not called wire bytes.
class NetworkMetrics {
  static final shared = NetworkMetrics();
  final Map<String, EndpointMetrics> endpoints = {};
  void request(RequestOptions options) {
    final metric = endpoints.putIfAbsent(options.path, EndpointMetrics.new);
    metric.requests++;
    options.extra['metricsStart'] = DateTime.now();
  }

  void finish(
    RequestOptions options, {
    Response<dynamic>? response,
    DioException? error,
  }) {
    final metric = endpoints.putIfAbsent(options.path, EndpointMetrics.new);
    if (error != null) {
      if (CancelToken.isCancel(error)) {
        metric.cancellations++;
      } else {
        metric.failures++;
      }
    }
    final start = options.extra['metricsStart'] as DateTime?;
    if (start != null) {
      metric.totalMilliseconds += DateTime.now()
          .difference(start)
          .inMilliseconds;
    }
    if (response != null) {
      metric.contentLengthBytes +=
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      try {
        metric.decodedBytes += utf8.encode(jsonEncode(response.data)).length;
      } catch (_) {}
    }
  }
}

class EndpointMetrics {
  int requests = 0, failures = 0, cancellations = 0;
  int contentLengthBytes = 0, decodedBytes = 0, totalMilliseconds = 0;
}
