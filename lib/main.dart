import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'auth/admin_access.dart';
import 'auth/login_page.dart';
import 'auth/sign_up_page.dart';
import 'auth/reset_password_page.dart';

import 'screens/splash_screen.dart';
import 'screens/client_dashboard.dart' as client;
import 'screens/admin_dashboard.dart' as admin;
import 'screens/client_workout_screen.dart';
import 'screens/admin_workout_screen.dart';
import 'screens/checkout_webview.dart';

const AndroidNotificationChannel _flexChannel = AndroidNotificationChannel(
  'flex_high_importance',
  'Flex Notifications',
  description: 'Session reminders and booking updates.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Create the high-importance Android notification channel
  await _flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_flexChannel);

  // 🔔 Optional: FCM setup (you already had this)
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    String? token = await messaging.getToken();
    print('FCM Token: $token');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received foreground notification: ${message.notification?.title}');
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print('FCM init error: $e');
  }

  // Keep FCM token synced to Firestore whenever auth state/token changes.
  _setupGlobalFcmTokenSync();

  runApp(const MyApp());
}

void _setupGlobalFcmTokenSync() {
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _upsertUserFcmToken(user.uid, token);
      }
    } catch (e) {
      print('Global FCM sync (auth change) error: $e');
    }
  });

  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _upsertUserFcmToken(user.uid, token);
    } catch (e) {
      print('Global FCM sync (token refresh) error: $e');
    }
  });
}

Future<void> _upsertUserFcmToken(String uid, String token) async {
  await FirebaseFirestore.instance.collection('users').doc(uid).set(
    {'fcm_token': token},
    SetOptions(merge: true),
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Received background notification: ${message.notification?.title}');
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

  Future<User?> _getVerifiedUser(User? user) async {
    if (user == null) return null;

    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;

    if (refreshedUser == null || !refreshedUser.emailVerified) {
      await FirebaseAuth.instance.signOut();
      return null;
    }

    return refreshedUser;
  }

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
          return FutureBuilder<User?>(
            future: _getVerifiedUser(snapshot.data),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final verifiedUser = userSnapshot.data;
              if (verifiedUser == null) {
                return const LoginPage();
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(verifiedUser.uid)
                    .get(),
                builder: (context, roleSnapshot) {
                  if (roleSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (roleSnapshot.hasData && roleSnapshot.data!.exists) {
                    final data = roleSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                    final role = data['role'] ?? 'client';
                    final email = data['email'] ?? '';
                    final userName = email.toString().split('@').first;

                    if (role == 'admin') {
                      if (!AdminAccess.isAllowedAdminEmail(email.toString())) {
                        FirebaseAuth.instance.signOut();
                        return const LoginPage();
                      }

                      return admin.AdminDashboard(userName: userName);
                    }

                    return const client.ClientDashboard();
                  }

                  return const LoginPage();
                },
              );
            },
          );
        } else {
          return const LoginPage();
        }
      },
    );
  }
}
