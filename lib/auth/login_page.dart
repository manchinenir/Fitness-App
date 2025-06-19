import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
 
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
 
  @override
  State<LoginPage> createState() => _LoginPageState();
}
 
class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
 
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
 
  final _formKey = GlobalKey<FormState>();
  bool isLogin = true;
  bool isLoading = false;
  bool isSendingResetEmail = false;
  bool isVerifyingEmail = false;
  String errorMessage = '';
  String successMessage = '';
  bool _obscurePassword = true;
 
  // Email validation regex
  final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$',
  );
 
  // Updated disposable domains list (only clearly disposable ones)
  final List<String> _disposableDomains = [
    'mailinator.com',
    'guerrillamail.com',
    '10minutemail.com',
    'throwawaymail.com',
    'yopmail.com',
    'trashmail.com',
  ];
 
  bool _isValidEmail(String email) {
    if (!_emailRegex.hasMatch(email)) return false;
    if (email.contains(' ')) return false;
    if (email.startsWith('.') || email.endsWith('.')) return false;
   
    final parts = email.split('@');
    if (parts.length != 2) return false;
   
    final domain = parts[1].toLowerCase();
    final domainParts = domain.split('.');
    if (domainParts.length < 2) return false;
    if (domainParts.any((part) => part.isEmpty)) return false;
   
    return !_disposableDomains.contains(domain);
  }
 
  Future<bool> _verifyEmailWithAPI(String email) async {
    const bool isDebugMode = bool.fromEnvironment('dart.vm.product');
    if (isDebugMode) return true;
 
    const apiKey = 'YOUR_API_KEY';
    final url = Uri.parse('https://emailvalidation.abstractapi.com/v1/?api_key=$apiKey&email=$email');
   
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isValid = data['is_valid_format']['value'] ?? true;
        final isDisposable = data['is_disposable_email']['value'] ?? false;
       
        return isValid && !isDisposable;
      }
      return _isValidEmail(email);
    } catch (e) {
      return _isValidEmail(email);
    }
  }
 
  Future<bool> _isEmailAlreadyRegistered(String email) async {
    try {
      final methods = await _auth.fetchSignInMethodsForEmail(email);
      if (methods.isNotEmpty) return true;
 
      final query = await _firestore.collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
     
      return query.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
 
  
  Future<void> _handleAuthentication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = '';
      successMessage = '';
    });

    try {
      await _login();
    } on FirebaseAuthException catch (e) {
      setState(() => errorMessage = _getErrorMessage(e.code));
    } catch (e) {
      final msg = e.toString();
      if (e is FirebaseAuthException) {
        setState(() => errorMessage = _getErrorMessage(e.code));
      } else if (msg.contains('credential') || msg.contains('malformed')) {
        setState(() => errorMessage = 'Invalid email or password');
      } else if (msg.toLowerCase().contains('email not verified')) {
        setState(() => errorMessage = 'Please verify your email to continue.');
      } else {
        setState(() => errorMessage = 'Something went wrong. Please try again.');
      }
    }

    setState(() => isLoading = false);
  }

  Future<void> _login() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      successMessage = '';
    });
 
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
 
      if (!userCredential.user!.emailVerified) {
        await _auth.signOut();
        throw Exception("Email not verified. Please check your inbox.");
      }
 
      final userDoc = await _firestore.collection('users').doc(userCredential.user!.uid).get();
      if (!userDoc.exists) throw Exception("User record not found");
 
      final role = userDoc['role'];
      _navigateBasedOnRole(role);
    } catch (e) {
      final msg = e.toString();
      if (e is FirebaseAuthException) {
        setState(() => errorMessage = _getErrorMessage(e.code));
      } else if (msg.contains('credential') || msg.contains('malformed')) {
        setState(() => errorMessage = 'Invalid email or password');
      } else if (msg.toLowerCase().contains('email not verified')) {
        setState(() => errorMessage = 'Please verify your email to continue.');
      } else {
        setState(() => errorMessage = 'Something went wrong. Please try again.');
      }
    } finally {
      setState(() => isLoading = false);
    }
  }
 
void _navigateBasedOnRole(String role) {
  if (role == 'admin') {
    Navigator.pushReplacementNamed(context, '/admin');
  } else {
    // Block clients from logging in
    setState(() {
      errorMessage = 'Access denied. Only admins can log in.';
    });
    _auth.signOut(); // Log the user out immediately if not admin
  }
}

 
  Future<void> _resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      setState(() => errorMessage = 'Please enter a valid email');
      return;
    }
 
    setState(() {
      isSendingResetEmail = true;
      errorMessage = '';
      successMessage = '';
    });
 
    try {
      await _auth.sendPasswordResetEmail(email: email);
      setState(() {
        successMessage = 'Password reset email sent to $email';
        _showSuccessSnackbar('Password reset email sent! Check your inbox.');
      });
    } on FirebaseAuthException catch (e) {
      setState(() => errorMessage = _getErrorMessage(e.code));
      _showErrorSnackbar(_getErrorMessage(e.code));
    } catch (e) {
      setState(() => errorMessage = 'Failed to send reset email');
      _showErrorSnackbar('Failed to send reset email');
    } finally {
      setState(() => isSendingResetEmail = false);
    }
  }
 
  Future<void> _resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;
 
    setState(() {
      isVerifyingEmail = true;
      errorMessage = '';
      successMessage = '';
    });
 
    try {
      await user.sendEmailVerification();
      setState(() {
        successMessage = 'Verification email resent! Please check your inbox.';
        _showSuccessSnackbar('Verification email resent!');
      });
    } catch (e) {
      setState(() => errorMessage = 'Failed to resend verification email');
      _showErrorSnackbar('Failed to resend verification email');
    } finally {
      setState(() => isVerifyingEmail = false);
    }
  }
 
  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'Email already in use';
      case 'weak-password':
        return 'Password should be at least 6 characters';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled';
      default:
        return 'Authentication failed: $code';
    }
  }
  
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }
   final Color navyBlue = const Color(0xFF1C2D5E);
 
   @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(
                    'FF',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: navyBlue),
                  ),
                  Text(
                    'FLEX FACILITY',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: navyBlue, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Log in to your account',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        labelStyle: TextStyle(color: Colors.grey[700]),
                        prefixIcon: Icon(Icons.email_outlined, color: navyBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: navyBlue, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Please enter an email';
                        final domain = value.split('@').last.toLowerCase();
                        if (!_emailRegex.hasMatch(value)) return 'Invalid email format';
                        if (_disposableDomains.contains(domain)) return 'Disposable emails not allowed';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: Colors.grey[700]),
                        prefixIcon: Icon(Icons.lock_outline, color: navyBlue),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: navyBlue),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: navyBlue, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter your password';
                        if (value.length < 6) return 'Password too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isSendingResetEmail ? null : _resetPassword,
                        child: isSendingResetEmail
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: navyBlue))
                            : Text('Forgot Password?', style: TextStyle(color: navyBlue)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _handleAuthentication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: navyBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: isLoading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Log in', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account?", style: TextStyle(color: Colors.grey[700])),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/signup'),
                          child: Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold, color: navyBlue)),
                        ),
                      ],
                    ),

                    if (errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red[800]),
                              const SizedBox(width: 8),
                              Expanded(child: Text(errorMessage, style: TextStyle(color: Colors.red[800]))),
                            ],
                          ),
                        ),
                      ),

                    if (successMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.green[800]),
                              const SizedBox(width: 8),
                              Expanded(child: Text(successMessage, style: TextStyle(color: Colors.green[800]))),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
