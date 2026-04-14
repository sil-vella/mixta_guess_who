import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../utils/consts/config.dart';

class Logger {
  // Private constructor
  Logger._();

  // The single instance of Logger
  static final Logger _instance = Logger._();

  // Factory constructor to return the same instance
  factory Logger() {
    return _instance;
  }

  /// Maps [developer.log] levels to labels expected by `playbooks/frontend/launch_*.sh`
  /// filters and by `mixta_flask/tools/logger/server.log` ingestion.
  static String _levelName(int level) {
    if (level >= 1000) return 'ERROR';
    if (level >= 900) return 'WARNING';
    if (level >= 800) return 'INFO';
    return 'DEBUG';
  }

  /// Single-line prefix so stdout can be parsed after `flutter run` / logcat prefixes:
  /// `[ISO8601] [LEVEL] [AppLogger] …`
  static String _formatLine(
    String name,
    String message,
    int level, {
    Object? error,
  }) {
    final ts = DateTime.now().toIso8601String();
    final lvl = _levelName(level);
    final buf = StringBuffer('[$ts] [$lvl] [$name] $message');
    if (error != null) {
      buf.write(' | error: $error');
    }
    return buf.toString();
  }

  /// General log method that respects `Config.loggerOn`
  void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    if (Config.loggerOn) {
      final line = _formatLine(name, message, level, error: error);
      developer.log(line, name: name, error: error, stackTrace: stackTrace, level: level);
      // Web: `developer.log` is not reliably forwarded to `flutter run` stdout, so
      // playbooks/frontend/launch_chrome.sh cannot pipe into server.log without this.
      if (kIsWeb) print(line);
    }
  }

  /// Log an informational message
  void info(String message) => log(message, level: 800);

  /// Log a debug message
  void debug(String message) => log(message, level: 500);

  /// Log an error message
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(message, level: 1000, error: error, stackTrace: stackTrace);

  /// Force log (logs regardless of `Config.loggerOn`)
  void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    final line = _formatLine(name, message, level, error: error);
    developer.log(line, name: name, error: error, stackTrace: stackTrace, level: level);
    if (kIsWeb) print(line);
  }
}