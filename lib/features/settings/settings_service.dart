import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How large text and numbers are drawn.
///
/// A multiplier on top of whatever the system is already asking for, never a
/// replacement for it: someone who has turned the iOS or Android font size up
/// keeps that, and this preference moves it further. The large step is modest
/// for the same reason — it compounds with a system setting that may already
/// be at 1.5, and the layouts have to survive the product.
enum AppTextSize {
  small('Piccolo', 0.88),
  medium('Medio', 1),
  large('Grande', 1.18);

  const AppTextSize(this.label, this.scale);

  final String label;
  final double scale;

  static AppTextSize fromName(String? name) => values.firstWhere(
    (size) => size.name == name,
    orElse: () => AppTextSize.medium,
  );
}

/// Device-local preferences.
///
/// The reminder hour is deliberately per device rather than per house: within
/// one family, one person may want the reminder at 19:00 and another at 21:00,
/// and neither should impose it on the other. The text size is per device for
/// the same reason: it is about this pair of eyes and this screen.
class AppSettings {
  const AppSettings({
    this.notificationHour = 20,
    this.notificationMinute = 0,
    this.notificationsEnabled = true,
    this.maintenanceRemindersEnabled = true,
    this.exactAlarms = false,
    this.themeMode = ThemeMode.system,
    this.textSize = AppTextSize.medium,
  });

  final int notificationHour;
  final int notificationMinute;
  final bool notificationsEnabled;

  /// Maintenance reminders can be silenced without losing the waste ones.
  final bool maintenanceRemindersEnabled;
  final bool exactAlarms;
  final ThemeMode themeMode;
  final AppTextSize textSize;

  TimeOfDay get notificationTime =>
      TimeOfDay(hour: notificationHour, minute: notificationMinute);

  AppSettings copyWith({
    int? notificationHour,
    int? notificationMinute,
    bool? notificationsEnabled,
    bool? maintenanceRemindersEnabled,
    bool? exactAlarms,
    ThemeMode? themeMode,
    AppTextSize? textSize,
  }) => AppSettings(
    notificationHour: notificationHour ?? this.notificationHour,
    notificationMinute: notificationMinute ?? this.notificationMinute,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    maintenanceRemindersEnabled:
        maintenanceRemindersEnabled ?? this.maintenanceRemindersEnabled,
    exactAlarms: exactAlarms ?? this.exactAlarms,
    themeMode: themeMode ?? this.themeMode,
    textSize: textSize ?? this.textSize,
  );
}

class SettingsService {
  const SettingsService();

  static const _hourKey = 'notification_hour';
  static const _minuteKey = 'notification_minute';
  static const _enabledKey = 'notifications_enabled';
  static const _maintenanceKey = 'maintenance_reminders_enabled';
  static const _exactKey = 'exact_alarms';
  static const _themeKey = 'theme_mode';
  static const _textSizeKey = 'text_size';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      notificationHour: prefs.getInt(_hourKey) ?? 20,
      notificationMinute: prefs.getInt(_minuteKey) ?? 0,
      notificationsEnabled: prefs.getBool(_enabledKey) ?? true,
      maintenanceRemindersEnabled: prefs.getBool(_maintenanceKey) ?? true,
      exactAlarms: prefs.getBool(_exactKey) ?? false,
      themeMode: _themeFromName(prefs.getString(_themeKey)),
      textSize: AppTextSize.fromName(prefs.getString(_textSizeKey)),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, settings.notificationHour);
    await prefs.setInt(_minuteKey, settings.notificationMinute);
    await prefs.setBool(_enabledKey, settings.notificationsEnabled);
    await prefs.setBool(_maintenanceKey, settings.maintenanceRemindersEnabled);
    await prefs.setBool(_exactKey, settings.exactAlarms);
    await prefs.setString(_themeKey, settings.themeMode.name);
    await prefs.setString(_textSizeKey, settings.textSize.name);
  }

  ThemeMode _themeFromName(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
