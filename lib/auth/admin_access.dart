class AdminAccess {
  AdminAccess._();

  static const List<String> allowedAdminEmails = [
    'Kenny@flextraining.co',
    'sridharkota17@gmail.com',
  ];

  static bool isAllowedAdminEmail(String? email) {
    final normalized = (email ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;

    return allowedAdminEmails
        .map((entry) => entry.toLowerCase())
        .contains(normalized);
  }
}