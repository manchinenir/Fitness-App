import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flex_facility_app/auth/login_page.dart';
import 'package:flex_facility_app/auth/sign_up_page.dart';
import 'package:flex_facility_app/auth/reset_password_page.dart';
import 'package:flex_facility_app/screens/splash_screen.dart';
import 'package:flex_facility_app/screens/admin_dashboard.dart' as admin;
import 'screens/admin_workout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flex Facility App',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: const SplashScreen(), // 🟢 You can change this to RootPage if needed
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/reset-password': (context) => const ResetPasswordPage(),

        '/admin': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          final userName = (args is String && args.isNotEmpty) ? args : 'Admin';
          return admin.AdminDashboard(userName: userName);
        },
         '/adminWorkoutMulti': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          final clientList = args is List<Map<String, dynamic>> ? args : <Map<String, dynamic>>[];
          return AdminWorkoutScreen();
        },
      },
    );
  }
}

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
                final data = userSnapshot.data!.data() as Map<String, dynamic>?;
                final role = data?['role'] ?? 'none';
                final email = data?['email'] ?? '';
                final userName = email.split('@')[0];

                if (role == 'admin') {
                  return admin.AdminDashboard(userName: userName);
                } else {
                  return const LoginPage(); // Only allow admins
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
