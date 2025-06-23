import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController emailController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String message = '';
  bool isLoading = false;

  Future<void> _sendResetEmail() async {
    setState(() {
      isLoading = true;
      message = '';
    });

    try {
      await _auth.setLanguageCode('en');
      await _auth.sendPasswordResetEmail(email: emailController.text.trim());
      setState(() => message = 'Password reset email sent!');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        setState(() => message = 'No user found with this email.');
      } else {
        setState(() => message = 'Error: ${e.message}');
      }
    } catch (e) {
      setState(() => message = 'Unexpected error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Enter your email'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _sendResetEmail,
              child: isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Send Email'),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(message),
              ),
          ],
        ),
      ),
    );
  }
}
