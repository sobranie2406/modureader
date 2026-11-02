import 'dart:collection';

import 'package:anx_reader/service/dictionary/local_dictionary.dart';

/// In-memory quota bookkeeping for plugin network requests.
///
/// Counters are deliberately **not** persisted (security review Q4): writing
/// them would put I/O on a hot path and pollute settings backups. A restart
/// resetting the daily counter is an accepted trade.
class PluginHttpBudget {
  PluginHttpBudget({
    this.perPluginConcurrency = 1,
    this.perPluginPerMinute = 20,
    this.perPluginPerDay = 300,
    this.globalConcurrency = 4,
    this.globalPerMinute = 60,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int perPluginConcurrency;
  final int perPluginPerMinute;
  final int perPluginPerDay;
  final int globalConcurrency;
  final int globalPerMinute;
  final DateTime Function() _clock;

  int _globalInFlight = 0;
  final _pluginInFlight = <String, int>{};
  final _globalWindow = Queue<DateTime>();
  final _pluginWindows = <String, Queue<DateTime>>{};
  final _dailyCounts = <String, int>{};
  DateTime? _dailyDay;

  int get globalInFlight => _globalInFlight;
  int inFlightFor(String pluginId) => _pluginInFlight[pluginId] ?? 0;

  /// Throws unless the request may proceed; does not reserve anything.
  void check(String pluginId) {
    _rollDay();
    if ((_pluginInFlight[pluginId] ?? 0) >= perPluginConcurrency) {
      throw const DictionaryFailure('rateLimited');
    }
    if (_globalInFlight >= globalConcurrency) {
      throw const DictionaryFailure('rateLimited');
    }
    final now = _clock();
    _pruneWindow(_globalWindow, now);
    if (_globalWindow.length >= globalPerMinute) {
      throw const DictionaryFailure('rateLimited');
    }
    final pluginWindow =
        _pluginWindows.putIfAbsent(pluginId, () => Queue<DateTime>());
    _pruneWindow(pluginWindow, now);
    if (pluginWindow.length >= perPluginPerMinute) {
      throw const DictionaryFailure('rateLimited');
    }
    if ((_dailyCounts[pluginId] ?? 0) >= perPluginPerDay) {
      throw const DictionaryFailure('dailyLimit');
    }
  }

  /// Reserves a slot. Call exactly once per request, then [release].
  void acquire(String pluginId) {
    check(pluginId);
    final now = _clock();
    _globalInFlight++;
    _pluginInFlight[pluginId] = (_pluginInFlight[pluginId] ?? 0) + 1;
    _globalWindow.add(now);
    _pluginWindows.putIfAbsent(pluginId, () => Queue<DateTime>()).add(now);
    _dailyCounts[pluginId] = (_dailyCounts[pluginId] ?? 0) + 1;
  }

  void release(String pluginId) {
    if (_globalInFlight > 0) _globalInFlight--;
    final current = _pluginInFlight[pluginId] ?? 0;
    if (current > 0) _pluginInFlight[pluginId] = current - 1;
  }

  /// Cancellations and configuration errors are not the plugin's fault, so they
  /// are refunded rather than counted against the daily allowance.
  void refund(String pluginId) {
    final current = _dailyCounts[pluginId] ?? 0;
    if (current > 0) _dailyCounts[pluginId] = current - 1;
    _globalWindow.removeLast();
    final pluginWindow = _pluginWindows[pluginId];
    if (pluginWindow != null && pluginWindow.isNotEmpty) {
      pluginWindow.removeLast();
    }
    release(pluginId);
  }

  int dailyCountFor(String pluginId) => _dailyCounts[pluginId] ?? 0;

  void _pruneWindow(Queue<DateTime> window, DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    while (window.isNotEmpty && window.first.isBefore(cutoff)) {
      window.removeFirst();
    }
  }

  void _rollDay() {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    if (_dailyDay == null || _dailyDay != today) {
      _dailyDay = today;
      _dailyCounts.clear();
    }
  }
}

/// Bounded in-memory cache for plugin lookups.
///
/// Never written to disk and never synced: scraped dictionary content must not
/// outlive the session (security review §3 T8).
class PluginLookupCache {
  PluginLookupCache({
    this.maxEntries = 64,
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEntries;
  final Duration ttl;
  final DateTime Function() _clock;
  final _entries = <String, _CacheEntry>{};

  T? read<T>(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_clock().difference(entry.storedAt) > ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  void write(String key, Object? value) {
    _entries.remove(key);
    _entries[key] = _CacheEntry(value, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

class _CacheEntry {
  const _CacheEntry(this.value, this.storedAt);
  final Object? value;
  final DateTime storedAt;
}