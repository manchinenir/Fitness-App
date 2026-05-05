import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthEmailService {
  static const String _functionsBaseUrl =
      'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api';

  static Future<void> sendVerificationEmail({
    required String email,
    String? displayName,
  }) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/auth/send-verification-email'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String details = '';
      String code = '';
      try {
        final data = jsonDecode(response.body);
        if (data is Map) {
          if (data['error'] != null) {
            details = data['error'].toString();
          }
          if (data['code'] != null) {
            code = data['code'].toString();
          }
        }
      } catch (_) {
        // Ignore JSON parse failures and fallback to status text only.
      }

      final normalized = '$code $details'.toUpperCase();
      if (response.statusCode == 429 ||
          normalized.contains('TOO_MANY_ATTEMPTS_TRY_LATER') ||
          normalized.contains('TOO-MANY-REQUESTS')) {
        throw Exception('Too many attempts. Please wait a few minutes and try again.');
      }

      if (normalized.contains('INVALID-EMAIL') || normalized.contains('INVALID_EMAIL')) {
        throw Exception('Please enter a valid email address.');
      }

      if (normalized.contains('USER-NOT-FOUND') || normalized.contains('USER_NOT_FOUND')) {
        throw Exception('No account found for this email.');
      }

      final suffix = details.isNotEmpty ? ': $details' : '';
      throw Exception(
        'Verification email request failed (HTTP ${response.statusCode})$suffix',
      );
    }
  }

  static Future<void> sendPasswordResetEmail({
    required String email,
    String? displayName,
  }) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/auth/send-password-reset-email'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String details = '';
      String code = '';
      try {
        final data = jsonDecode(response.body);
        if (data is Map) {
          if (data['error'] != null) {
            details = data['error'].toString();
          }
          if (data['code'] != null) {
            code = data['code'].toString();
          }
        }
      } catch (_) {
        // Ignore JSON parse failures and fallback to status text only.
      }

      final normalized = '$code $details'.toUpperCase();
      if (normalized.contains('INVALID-EMAIL') || normalized.contains('INVALID_EMAIL')) {
        throw Exception('Please enter a valid email address.');
      }

      if (normalized.contains('USER-NOT-FOUND') || normalized.contains('USER_NOT_FOUND')) {
        throw Exception('No account found for this email.');
      }

      final suffix = details.isNotEmpty ? ': $details' : '';
      throw Exception(
        'Password reset email request failed (HTTP ${response.statusCode})$suffix',
      );
    }
  }
}
