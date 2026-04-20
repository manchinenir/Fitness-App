import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'auth/login_page.dart';
import 'auth/sign_up_page.dart';
import 'auth/reset_password_page.dart';

import 'screens/splash_screen.dart';
import 'screens/client_dashboard.dart' as client;
import 'screens/admin_dashboard.dart' as admin;
import 'screens/client_workout_screen.dart';
import 'screens/admin_workout_screen.dart';
import 'screens/checkout_webview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 🔥 Crashlytics: catch all Flutter framework errors
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // 🔔 FCM setup
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    String? token = await messaging.getToken();
    debugPrint('FCM Token: $token');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground notification: ${message.notification?.title}');
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
    debugPrint('FCM init error: $e');
  }

  runApp(const MyApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background notification: ${message.notification?.title}');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flex Facility App',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const SplashScreen(), // or const RootPage() if you want auto-login
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/reset-password': (context) => const ResetPasswordPage(),

        // Client
        '/client': (context) => const client.ClientDashboard(),
        '/clientWorkout': (context) => const ClientWorkoutScreen(),

        // Admin
        '/admin': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          final userName =
              (args is String && args.isNotEmpty) ? args : 'Admin';
          return admin.AdminDashboard(userName: userName);
        },
        '/adminWorkoutMulti': (context) => const AdminWorkoutScreen(),

        // Checkout WebView
        '/checkout': (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final url = args?['url'] as String? ??
              'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api/checkout?amountCents=2500';
          return CheckoutWebView(url: url);
        },
      },
    );
  }
}

/// Optional: auto-redirect based on logged-in user role
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData) {
          final user = snapshot.data!;
          final uid = user.uid;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final data =
                    userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                final role = data['role'] ?? 'client';
                final email = data['email'] ?? '';
                final userName = email.toString().split('@').first;

                if (role == 'admin') {
                  return admin.AdminDashboard(userName: userName);
                } else {
                  return const client.ClientDashboard();
                }
              } else {
                return const LoginPage();
              }
            },
          );
        } else {
          return const LoginPage();
        }
      },
    );
  }
}
