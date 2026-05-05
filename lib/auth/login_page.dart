import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'admin_access.dart';
import 'auth_email_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      final available = await auth.getAvailableBiometrics();
      setState(() {
        _canCheckBiometrics = canCheck;
        _hasBiometrics = available.isNotEmpty;
        _biometricError = '';
      });
    } on PlatformException catch (e) {
      setState(() {
        _canCheckBiometrics = false;
        _hasBiometrics = false;
        _biometricError = e.message ?? 'Biometric error';
      });
    }
  }
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool _canCheckBiometrics = false;
  bool _hasBiometrics = false;
  String _biometricError = '';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool isSendingResetEmail = false;
  bool isSendingVerificationEmail = false;
  String errorMessage = '';
  String successMessage = '';
  bool _obscurePassword = true;

  final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$',
  );

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

  Future<bool> _isEmailVerifiedStrict(User user) async {
    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) return false;

    final tokenResult = await refreshedUser.getIdTokenResult(true);
    final tokenVerified = tokenResult.claims?['email_verified'] == true;
    return refreshedUser.emailVerified && tokenVerified;
  }

  Future<bool> _verifyEmailWithAPI(String email) async {
    const bool isDebugMode = bool.fromEnvironment('dart.vm.product');
    if (isDebugMode) return true;

    const apiKey = 'YOUR_API_KEY';
    final url = Uri.parse(
        'https://emailvalidation.abstractapi.com/v1/?api_key=$apiKey&email=$email');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isValid = data['is_valid_format']['value'] ?? true;
        final isDisposable =
            data['is_disposable_email']['value'] ?? false;
        return isValid && !isDisposable;
      }
      return _isValidEmail(email);
    } catch (e) {
      return _isValidEmail(email);
    }
  }

  Future<User> _requireVerifiedUser(User user) async {
    final refreshedUser = _auth.currentUser;

    if (refreshedUser == null) {
      throw Exception('Authentication failed. Please try again.');
    }

    final verified = await _isEmailVerifiedStrict(refreshedUser);
    if (!verified) {
      try {
        final currentEmail = refreshedUser.email;
        if (currentEmail != null && currentEmail.trim().isNotEmpty) {
          await AuthEmailService.sendVerificationEmail(
            email: currentEmail,
          );
        }
      } catch (_) {
        // Best effort only; user can still use explicit resend.
      }
      await _auth.signOut();
      throw Exception('Please verify your email before logging in. A new verification email has been sent.');
    }

    return refreshedUser;
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
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      if (e is FirebaseAuthException) {
        setState(() => errorMessage = _getErrorMessage(e.code));
      } else if (msg.contains('credential') || msg.contains('malformed')) {
        setState(() => errorMessage = 'Incorrect email or password. Please check your details and try again.');
      } else {
        setState(() => errorMessage = msg.isNotEmpty
            ? msg
            : 'Something went wrong. Please try again.');
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
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      // Save credentials securely for Face ID/Touch ID auto-login
      await secureStorage.write(key: 'email', value: email);
      await secureStorage.write(key: 'password', value: password);

      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final verifiedUser =
          await _requireVerifiedUser(userCredential.user!);

      // Double-check immediately before route navigation.
      final stillVerified = await _isEmailVerifiedStrict(verifiedUser);
      if (!stillVerified) {
        await _auth.signOut();
        throw Exception('Please verify your email before logging in.');
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(verifiedUser.uid)
          .get();

      if (!userDoc.exists) {
        await _auth.signOut();
        throw Exception("User record not found");
      }

      final data = userDoc.data() as Map<String, dynamic>? ?? {};

      final isActive = data['isActive'] ?? true;
      if (!isActive) {
        await _auth.signOut();
        throw Exception("Your account has been deactivated. Please contact support.");
      }

      final role = data['role'] ?? 'client';
      final emailFromDoc = (data['email'] ?? verifiedUser.email ?? '').toString();
      final userName = emailFromDoc.split('@').first;

      await _navigateBasedOnRole(role, userName, emailFromDoc);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      if (e is FirebaseAuthException) {
        setState(() => errorMessage = _getErrorMessage(e.code));
      } else if (msg.contains('credential') || msg.contains('malformed')) {
        setState(() => errorMessage = 'Incorrect email or password. Please check your details and try again.');
      } else if (msg.toLowerCase().contains('deactivated')) {
        setState(() => errorMessage =
            'Your account has been deactivated. Please contact support.');
      } else if (msg.toLowerCase().contains('verify your email')) {
        setState(() => errorMessage = msg);
      } else {
        setState(() => errorMessage = msg.isNotEmpty
            ? msg
            : 'Something went wrong. Please try again.');
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _navigateBasedOnRole(
    String role,
    String userName,
    String email,
  ) async {
    if (role == 'client') {
      Navigator.pushReplacementNamed(context, '/client');
    } else if (role == 'admin') {
      if (!AdminAccess.isAllowedAdminEmail(email)) {
        await _auth.signOut();
        if (!mounted) return;

        setState(() {
          errorMessage = 'This account is not allowed to access the admin side.';
        });
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        '/admin',
        arguments: userName,
      );
    } else {
      setState(() {
        errorMessage = 'Access denied.';
      });
      _auth.signOut();
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
      await AuthEmailService.sendPasswordResetEmail(email: email);

      setState(() {
        successMessage = 'Password reset email sent to $email';
        _showSuccessSnackbar(
          'Password reset email sent! Check your inbox or spam folder.',
        );
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
    final email = emailController.text.trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      setState(() => errorMessage = 'Please enter a valid email');
      return;
    }

    setState(() {
      isSendingVerificationEmail = true;
      errorMessage = '';
      successMessage = '';
    });

    try {
      await AuthEmailService.sendVerificationEmail(email: email);

      setState(() {
        successMessage = 'Verification email sent to $email';
      });
      _showSuccessSnackbar(
        'Verification email sent! Check inbox, spam, or Promotions tab.',
      );
    } catch (apiError) {
      final details = apiError.toString().replaceFirst('Exception: ', '').trim();
      setState(() => errorMessage = details.isNotEmpty
          ? details
          : 'Failed to send verification email.');
      _showErrorSnackbar(details.isNotEmpty
          ? details
          : 'Failed to send verification email.');
    } finally {
      setState(() => isSendingVerificationEmail = false);
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address. Please check and try again.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Incorrect email or password. Please check your details and try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-disabled':
        return 'Your account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      case 'operation-not-allowed':
        return 'Email/password login is not enabled. Please contact support.';
      default:
        return 'Login failed. Please check your email and password.';
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  final Color navyBlue = const Color(0xFF1C2D5E);

  @override
  Widget build(BuildContext context) {


      Future<void> _authenticateWithBiometrics() async {
        setState(() { errorMessage = ''; });
        try {
          final didAuthenticate = await auth.authenticate(
            localizedReason: 'Authenticate with Face ID / Touch ID / biometrics',
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );
          if (didAuthenticate) {
            // Retrieve credentials and auto-login
            final email = await secureStorage.read(key: 'email') ?? '';
            final password = await secureStorage.read(key: 'password') ?? '';
            if (email.isNotEmpty && password.isNotEmpty) {
              emailController.text = email;
              passwordController.text = password;
              await _handleAuthentication();
            } else {
              setState(() { errorMessage = 'No credentials found. Please login once with email and password.'; });
            }
          } else {
            setState(() { errorMessage = 'Biometric authentication failed.'; });
          }
        } on PlatformException catch (e) {
          setState(() { errorMessage = e.message ?? 'Biometric error'; });
        }
      }
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
                  Container(
                    width: 150,
                    height: 150,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      image: DecorationImage(
                        image: AssetImage('assets/images/flex_login/logo.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: navyBlue, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter an email';
                        }
                        final domain = value.split('@').last.toLowerCase();
                        if (!_emailRegex.hasMatch(value)) {
                          return 'Invalid email format';
                        }
                        if (_disposableDomains.contains(domain)) {
                          return 'Disposable emails not allowed';
                        }
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
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: navyBlue,
                          ),
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: navyBlue, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password too short';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                isSendingResetEmail ? null : _resetPassword,
                            child: isSendingResetEmail
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: navyBlue,
                                    ),
                                  )
                                : Text(
                                    'Forgot Password?',
                                    style: TextStyle(color: navyBlue),
                                  ),
                          ),
                          TextButton(
                            onPressed: isSendingVerificationEmail
                                ? null
                                : _resendVerificationEmail,
                            child: isSendingVerificationEmail
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: navyBlue,
                                    ),
                                  )
                                : Text(
                                    'Resend Verification Email',
                                    style: TextStyle(color: navyBlue),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_canCheckBiometrics && _hasBiometrics)
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.fingerprint, size: 28),
                              label: const Text(
                                'Login with Face ID / Touch ID',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: navyBlue,
                                side: BorderSide(color: navyBlue, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: isLoading ? null : _authenticateWithBiometrics,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed:
                            isLoading ? null : _handleAuthentication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: navyBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Log in',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/signup'),
                          child: Text(
                            'Sign Up',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: navyBlue,
                            ),
                          ),
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
                              Icon(Icons.error_outline,
                                  color: Colors.red[800]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage,
                                  style:
                                      TextStyle(color: Colors.red[800]),
                                ),
                              ),
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
                            border:
                                Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: Colors.green[800]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  successMessage,
                                  style: TextStyle(
                                      color: Colors.green[800]),
                                ),
                              ),
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
