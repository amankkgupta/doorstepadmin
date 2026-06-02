import 'package:admindoorstep/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static final AppLogger _logger = AppLogger();
  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'admin_high_importance_channel',
        'Admin notifications',
        description: 'High priority notifications for admin updates.',
        importance: Importance.high,
      );
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _localNotificationsInitialized = false;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> initialize() async {
    try {
      _logger.info('Initializing Firebase Messaging');

      await _initializeLocalNotifications();

      // Request permission for iOS/macOS and recent Android versions.
      if (!kIsWeb) {
        NotificationSettings settings = await FirebaseMessaging.instance
            .requestPermission(
              alert: true,
              announcement: false,
              badge: true,
              provisional: false,
              sound: true,
            );

        _logger.info(
          'Notification permission granted: ${settings.authorizationStatus}',
        );
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logger.info(
          'Foreground message received',
          data: {
            'title': message.notification?.title,
            'body': message.notification?.body,
            'data': message.data,
          },
        );

        if (message.notification != null) {
          _showForegroundNotification(message);
        }
      });

      // Handle background message tap when app is terminated or in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _logger.info(
          'Notification opened from background',
          data: {'title': message.notification?.title},
        );
        _handleNotificationTap(message);
      });

      _logger.info('Firebase Messaging initialized successfully');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to initialize Firebase Messaging',
        data: {'error': e.toString()},
        stackTrace: stackTrace,
      );
    }
  }

  Future<String?> getFCMToken() async {
    if (Firebase.apps.isEmpty) {
      _logger.warning('FCM token skipped: Firebase is not initialized.');
      return null;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      _logger.info('FCM token retrieved', data: {'hasToken': token != null});
      return token;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to get FCM token',
        data: {'error': e.toString()},
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        _logger.info(
          'Local notification opened',
          data: {'payload': response.payload},
        );
      },
    );

    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidNotifications?.createNotificationChannel(_androidChannel);
    await androidNotifications?.requestNotificationsPermission();

    _localNotificationsInitialized = true;
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      _logger.info(
        'Showing foreground notification',
        data: {'title': notification.title, 'body': notification.body},
      );

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _localNotifications.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: message.data.isEmpty ? null : message.data.toString(),
        );
      }
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    _logger.info(
      'Handling notification tap',
      data: {'title': message.notification?.title, 'data': message.data},
    );

    // TODO: Navigate to relevant screen based on notification data
    // Example: if (message.data['type'] == 'message') { navigate to chat }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      _logger.info('Subscribed to topic: $topic');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to subscribe to topic',
        data: {'topic': topic, 'error': e.toString()},
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      _logger.info('Unsubscribed from topic: $topic');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to unsubscribe from topic',
        data: {'topic': topic, 'error': e.toString()},
        stackTrace: stackTrace,
      );
    }
  }
}
