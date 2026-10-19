import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'network_metrics.dart';

class DioClient {
  DioClient({Dio? transport})
    : dio =
          transport ??
          Dio(
            BaseOptions(
              baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              headers: const {
                'accept': 'application/json, text/plain, */*',
                'content-type': 'application/json',
                'origin': 'https://rtl.mv',
                'referer': 'https://rtl.mv/',
              },
            ),
          ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          NetworkMetrics.shared.finish(
            error.requestOptions,
            response: error.response,
            error: error,
          );
          handler.next(error);
        },
        onRequest: (options, handler) {
          NetworkMetrics.shared.request(options);
          options.extra['start'] = DateTime.now().millisecondsSinceEpoch;
          handler.next(options);
        },
        onResponse: (response, handler) {
          NetworkMetrics.shared.finish(
            response.requestOptions,
            response: response,
          );
          final start = response.requestOptions.extra['start'] as int?;
          if (kDebugMode && start != null) {
            final ms = DateTime.now().millisecondsSinceEpoch - start;
            log(
              '[API] ${response.requestOptions.method} ${response.requestOptions.path} ${response.statusCode} ${ms}ms',
            );
          }
          handler.next(response);
        },
      ),
    );
  }

  final Dio dio;
}
