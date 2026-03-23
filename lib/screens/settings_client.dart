import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

// IMPORT YOUR LOGIN PAGE
import '../auth/login_page.dart';

const Color kPrimary = Color(0xFF1C2D5E);

class SettingsClient extends StatelessWidget {
  const SettingsClient({super.key});

  // LOGOUT FUNCTION
  Future<void> logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  // DELETE ACCOUNT FUNCTION
  Future<void> deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      String uid = user.uid;

      // Delete Firestore user document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .delete();

      // Delete progress data
      final progress = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('progress')
          .get();

      for (var doc in progress.docs) {
        await doc.reference.delete();
      }

      // Delete profile image
      try {
        await FirebaseStorage.instance
            .ref()
            .child('profile_images/$uid.jpg')
            .delete();
      } catch (_) {}

      // Delete Firebase Auth account
      await user.delete();

      // Go to Login Screen
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginPage(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting account: $e")),
      );
    }
  }

  // CONFIRM DELETE DIALOG
  void _confirmDelete(BuildContext context) {
    final parentContext = context;
    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text(
          "Are you sure you want to permanently delete your account? "
          "This action cannot be undone.",
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              deleteAccount(parentContext);
            },
          ),
        ],
      ),
    );
  }

  // SETTINGS TILE
  Widget _buildTile(
      BuildContext context, IconData icon, String title, VoidCallback onTap,
      {Color? color}) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (color ?? kPrimary).withOpacity(0.1),
          child: Icon(icon, color: color ?? kPrimary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text("Settings", style: TextStyle(color: Colors.white)),
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [

          const SizedBox(height: 20),

          // LOGOUT
          _buildTile(
            context,
            Icons.logout,
            "Logout",
            () => logout(context),
          ),

          const SizedBox(height: 10),

          // DELETE ACCOUNT
          _buildTile(
            context,
            Icons.delete_forever,
            "Delete Account",
            () => _confirmDelete(context),
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}