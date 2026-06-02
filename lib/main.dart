import 'package:admindoorstep/app_constants.dart';
import 'package:admindoorstep/app_routes.dart';
import 'package:admindoorstep/providers.dart';
import 'package:admindoorstep/services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:admindoorstep/app_logger.dart';
import 'package:admindoorstep/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supaBaseUrl,
    anonKey: AppConstants.supaBaseAnonKey,
  );

  if (await _initializeFirebase()) {
    // Register background message handler for FCM. This must be a top-level
    // function and registered before background messages can be handled.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await NotificationService().initialize();
  } else {
    AppLogger().warning(
      'Firebase Messaging skipped: Firebase options are not configured.',
    );
  }

  runApp(const AdminDoorstepApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!await _initializeFirebase()) {
    return;
  }

  // Log background message
  try {
    AppLogger().info(
      'FCM background message received',
      data: {
        'messageId': message.messageId,
        'data': message.data,
        'title': message.notification?.title,
        'body': message.notification?.body,
      },
    );
  } catch (_) {}
}

Future<bool> _initializeFirebase() async {
  if (Firebase.apps.isNotEmpty) {
    return true;
  }

  try {
    if (DefaultFirebaseOptions.isConfigured) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return true;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Firebase.initializeApp();
      return true;
    }
  } catch (error, stackTrace) {
    AppLogger().warning(
      'Firebase initialization failed. Add android/app/google-services.json '
      'or run flutterfire configure.',
      data: {'error': error.toString(), 'stackTrace': stackTrace.toString()},
    );
    return false;
  }

  return false;
}

class AdminDoorstepApp extends StatelessWidget {
  const AdminDoorstepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppProviders.providers,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'admindoorstep',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
          scaffoldBackgroundColor: const Color(0xFFF3F7F6),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        initialRoute: AppRoutes.login,
        routes: AppRoutes.routes,
      ),
    );
  }
}
