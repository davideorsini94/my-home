import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preferences.
///
/// The reminder hour is deliberately per device rather than per house: within
/// one family, one person may want the reminder at 19:00 and another at 21:00,
/// and neither should impose it on the other.
class AppSettings {
  const AppSettings({
    this.notificationHour = 20,
    this.notificationMinute = 0,
    this.notificationsEnabled = true,
    this.exactAlarms = false,
    this.themeMode = ThemeMode.system,
  });

  final int notificationHour;
  final int notificationMinute;
  final bool notificationsEnabled;
  final bool exactAlarms;
  final ThemeMode themeMode;

  TimeOfDay get notificationTime =>
      TimeOfDay(hour: notificationHour, minute: notificationMinute);

  AppSettings copyWith({
    int? notificationHour,
    int? notificationMinute,
    bool? notificationsEnabled,
    bool? exactAlarms,
    ThemeMode? themeMode,
  }) => AppSettings(
    notificationHour: notificationHour ?? this.notificationHour,
    notificationMinute: notificationMinute ?? this.notificationMinute,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    exactAlarms: exactAlarms ?? this.exactAlarms,
    themeMode: themeMode ?? this.themeMode,
  );
}

class SettingsService {
  const SettingsService();

  static const _hourKey = 'notification_hour';
  static const _minuteKey = 'notification_minute';
  static const _enabledKey = 'notifications_enabled';
  static const _exactKey = 'exact_alarms';
  static const _themeKey = 'theme_mode';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      notificationHour: prefs.getInt(_hourKey) ?? 20,
      notificationMinute: prefs.getInt(_minuteKey) ?? 0,
      notificationsEnabled: prefs.getBool(_enabledKey) ?? true,
      exactAlarms: prefs.getBool(_exactKey) ?? false,
      themeMode: _themeFromName(prefs.getString(_themeKey)),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, settings.notificationHour);
    await prefs.setInt(_minuteKey, settings.notificationMinute);
    await prefs.setBool(_enabledKey, settings.notificationsEnabled);
    await prefs.setBool(_exactKey, settings.exactAlarms);
    await prefs.setString(_themeKey, settings.themeMode.name);
  }

  ThemeMode _themeFromName(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
