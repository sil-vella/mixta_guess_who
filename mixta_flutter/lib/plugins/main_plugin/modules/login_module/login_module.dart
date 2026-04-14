import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mixta_guess_who/core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../connections_module/connections_module.dart';

class LoginModule extends ModuleBase {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  /// ✅ Constructor - No stored instances, dependencies are fetched dynamically
  LoginModule() : super("login_module") {
    _log.info('✅ LoginModule initialized.');
  }

  Future<Map<String, dynamic>> registerUser({
    required BuildContext context,
    required String username,
  }) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final connectionModule = moduleManager.getLatestModule<ConnectionsModule>();
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (connectionModule == null || sharedPref == null) {
      _log.error("❌ Missing required modules.");
      return {"error": "Service not available."};
    }

    try {
      _log.info("⚡ Checking if username exists...");

      final response = await connectionModule.sendPostRequest(
        "/register", // 🔹 Adjust endpoint as needed
        {"username": username},
      );

      if (response?["error"] != null) {
        _log.info("🚫 Username already taken: $username");
        return {"error": response["error"]}; // Return the error message
      } else {
        _log.info("✅ Username is available: $username");

        await sharedPref.setString('username', username);
        final rawId = response?['user_id'];
        if (rawId != null) {
          final id = rawId is int ? rawId : int.tryParse('$rawId');
          if (id != null) {
            await sharedPref.setInt('user_id', id);
          }
        }

        return {"success": "Username is available."};
      }
    } catch (e) {
      _log.error("❌ Error checking username: $e");
      return {"error": "Server error. Check network connection."};
    }
  }

  /// Deletes server-side user row + related rows, then clears local prefs.
  /// If there is no registered username, only local storage is cleared.
  Future<Map<String, dynamic>> deleteMyData({
    required ModuleManager moduleManager,
    required ServicesManager servicesManager,
  }) async {
    _log.info('🗑️ [deleteMyData] start');
    final connectionModule = moduleManager.getLatestModule<ConnectionsModule>();
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error('🗑️ [deleteMyData] abort: SharedPrefManager null');
      return {"error": "Storage not available."};
    }

    final keyCountBefore = sharedPref.getKeys().length;
    final username = sharedPref.getString('username');
    final uid = sharedPref.getInt('user_id');
    _log.info(
      '🗑️ [deleteMyData] prefs snapshot | keys=$keyCountBefore | username=${username ?? "(none)"} | user_id=$uid',
    );

    if (username == null || username.isEmpty) {
      _log.info('🗑️ [deleteMyData] guest path → clear() only (no /delete-user)');
      await sharedPref.clear();
      _log.forceLog('🗑️ [deleteMyData] after clear | keys=${sharedPref.getKeys().length}');
      return {"success": true, "local_only": true};
    }

    if (connectionModule == null) {
      _log.error('🗑️ [deleteMyData] abort: ConnectionsModule null');
      return {"error": "Connection not available."};
    }

    final payload = <String, dynamic>{'username': username};
    if (uid != null) {
      payload['user_id'] = uid;
    }
    _log.info('🗑️ [deleteMyData] POST /delete-user payload keys=${payload.keys.toList()}');

    dynamic response;
    try {
      response = await connectionModule.sendPostRequest('/delete-user', payload);
    } catch (e, st) {
      _log.error('🗑️ [deleteMyData] sendPostRequest threw', error: e, stackTrace: st);
      return {"error": "Request failed: $e"};
    }

    _log.info('🗑️ [deleteMyData] raw response type=${response.runtimeType} | value=$response');

    if (response is! Map) {
      _log.error('🗑️ [deleteMyData] unexpected response shape');
      return {"error": "Unexpected response."};
    }

    final err = response['error'];
    final msg = response['message'];
    final notFound = err != null &&
        err.toString().toLowerCase().contains('not found');

    if (err != null && msg == null && !notFound) {
      _log.error('🗑️ [deleteMyData] server error, not clearing prefs | error=$err');
      return {"error": err.toString()};
    }

    if (notFound) {
      _log.info('🗑️ [deleteMyData] user not found on server → clearing local anyway');
    }

    _log.info('🗑️ [deleteMyData] calling sharedPref.clear() | keys before=${sharedPref.getKeys().length}');
    await sharedPref.clear();
    _log.forceLog('🗑️ [deleteMyData] done | keys after=${sharedPref.getKeys().length}');
    return {"success": true};
  }
}