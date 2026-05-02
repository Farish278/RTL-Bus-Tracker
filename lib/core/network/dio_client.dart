import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

class DioClient {
  DioClient()
    : dio = Dio(
        BaseOptions(
          baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
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
        onRequest: (options, handler) {
          options.extra['start'] = DateTime.now().millisecondsSinceEpoch;
          handler.next(options);
        },
        onResponse: (response, handler) {
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
