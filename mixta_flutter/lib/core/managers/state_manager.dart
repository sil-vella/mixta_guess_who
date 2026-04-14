import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';

class PluginState {
  final Map<String, dynamic> state;

  PluginState({required this.state});

  /// Ensures all keys are Strings and values are valid JSON types
  factory PluginState.fromDynamic(Map<dynamic, dynamic> rawState) {
    return PluginState(
      state: rawState.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  /// Merges the new state with the existing one
  PluginState merge(Map<String, dynamic> newState) {
    return PluginState(state: {...state, ...newState});
  }
}

class StateManager with ChangeNotifier {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods
  static StateManager? _instance;

  final Map<String, PluginState> _pluginStates = {}; // Stores structured plugin states
  Map<String, dynamic> _mainAppState = {'main_state': 'idle'}; // Default main app state


  StateManager._internal() {
    _log.info('StateManager instance created.');
  }

  /// Factory method to provide the singleton instance
  factory StateManager() {
    _instance ??= StateManager._internal();
    return _instance!;
  }

  // ------ Plugin State Methods ------

  bool isPluginStateRegistered(String pluginKey) {
    return _pluginStates.containsKey(pluginKey);
  }

  /// ✅ Strictly register plugin states with `PluginState` structure
  void registerPluginState(String pluginKey, Map<String, dynamic> initialState) {
    if (!_pluginStates.containsKey(pluginKey)) {
      _pluginStates[pluginKey] = PluginState(state: initialState);
      _log.info("✅ Registered plugin state for key: $pluginKey");
      notifyListeners();
    } else {
      _log.error("⚠️ Plugin state for '$pluginKey' is already registered.");
    }
  }

  /// ✅ Unregister plugin state
  void unregisterPluginState(String pluginKey) {
    if (_pluginStates.containsKey(pluginKey)) {
      _pluginStates.remove(pluginKey);
      _log.info("🗑 Unregistered state for key: $pluginKey");
      notifyListeners();
    } else {
      _log.error("⚠️ Plugin state for '$pluginKey' does not exist.");
    }
  }

  T? getPluginState<T>(String pluginKey) {
    final PluginState? storedState = _pluginStates[pluginKey];

    if (storedState == null) {
      return null; // Ensure we don't attempt to access a null object
    }

    if (T == Map<String, dynamic>) {
      // Ensure that all keys are Strings and cast properly
      return storedState.state.map((key, value) => MapEntry(key.toString(), value)) as T;
    }

    if (storedState.state is T) {
      return storedState.state as T;
    }

    _log.error("❌ Type mismatch: Requested '$T' but found '${storedState.state.runtimeType}' for plugin '$pluginKey'");
    return null;
  }

  void updatePluginState(String pluginKey, Map<String, dynamic> newState, {bool force = false}) {
    if (!_pluginStates.containsKey(pluginKey)) {
      _log.error("❌ Cannot update state for '$pluginKey' - it is not registered.");
      return;
    }

    final existingState = _pluginStates[pluginKey];

    if (existingState != null) {
      // ✅ Ensure `merge` exists (assuming it's a custom method)
      final newMergedState = existingState.merge(newState);

      // ✅ More reliable state comparison
      if (force || !mapEquals(existingState.state, newMergedState.state)) {
        _pluginStates[pluginKey] = newMergedState;
        _log.info("✅ Updated state for '$pluginKey': ${_pluginStates[pluginKey]!.state} (force: $force)");

        // ✅ Notify immediately for real-time updates
        notifyListeners();
      } else {
        _log.info("🔁 No change detected for '$pluginKey', skipping notify. (force: $force)");
      }
    }
  }


  // ------ Main App State Methods ------

  void setMainAppState(Map<String, dynamic> initialState) {
    _mainAppState = {'main_state': 'idle', ...initialState};
    _log.info("📌 Main app state initialized: $_mainAppState");
    notifyListeners();
  }

  Map<String, dynamic> get mainAppState => _mainAppState;

  void updateMainAppState(String key, dynamic value) {
    _mainAppState[key] = value;
    _log.info("📌 Main app state updated: key=$key, value=$value");
    notifyListeners();
  }

  T? getMainAppState<T>(String key) {
    return _mainAppState[key] as T?;
  }
}
