import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Initializes timezone data and native local notification settings
  Future<void> init() async {
    tz.initializeTimeZones();
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
    );
  }

  /// Explicitly requests post notification permissions (critical for Android 13+)
  Future<bool> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      final bool? granted = await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  /// Sends an instant high-priority notification to the shade
  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'deep_work_channel',
      'Deep Work Alerts',
      channelDescription: 'Alerts and triggers for Deep Work Broker Focus Sessions',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details);
  }

  /// Schedules an exact alarm notification to fire when the focus session timer reaches zero
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required int secondsFromNow,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'deep_work_timer_channel',
      'Deep Work Timer Alerts',
      channelDescription: 'Notifications for focus session timer completions',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.now(tz.local).add(Duration(seconds: secondsFromNow)),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels a specific pending notification
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  /// Cancels all pending notifications
  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }
}
