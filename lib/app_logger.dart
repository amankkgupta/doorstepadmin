import 'package:flutter/foundation.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();

  factory AppLogger() {
    return _instance;
  }

  AppLogger._internal();

  void info(String message, {Map<String, dynamic>? data}) {
    _log('INFO', message, data);
  }

  void debug(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log('DEBUG', message, data);
    }
  }

  void warning(String message, {Map<String, dynamic>? data}) {
    _log('WARNING', message, data);
  }

  void error(
    String message, {
    Map<String, dynamic>? data,
    StackTrace? stackTrace,
  }) {
    _log('ERROR', message, data);
    if (stackTrace != null && kDebugMode) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _log(String level, String message, Map<String, dynamic>? data) {
    final timestamp = DateTime.now().toIso8601String();
    final dataStr = data != null ? ' | Data: $data' : '';
    final logMessage = '[admindoorstep] [$timestamp] [$level] $message$dataStr';
    
    if (kDebugMode) {
      debugPrint(logMessage);
    }
  }
}

