import 'package:flutter/material.dart';

import 'auth_email_service.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController emailController = TextEditingController();
  String message = '';
  bool isLoading = false;

  Future<void> _sendResetEmail() async {
    setState(() {
      isLoading = true;
      message = '';
    });

    try {
      await AuthEmailService.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );
      setState(() => message = 'Password reset email sent!');
    } on Exception catch (e) {
      setState(() => message = e.toString().replaceFirst('Exception: ', ''));
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
