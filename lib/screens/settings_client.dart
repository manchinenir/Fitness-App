import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // DELETE ACCOUNT FUNCTION with GDPR compliance
  Future<void> deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // GDPR: Delete user data from Firestore first
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        // Store deletion record for audit
        await FirebaseFirestore.instance.collection('deleted_accounts').doc(user.uid).set({
          'email': user.email,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletionType': 'user_requested',
          'dataRetentionPeriod': '30_days',
        });
        
        // Delete user document
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      }
      
      // Delete auth account
      await user.delete();

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login again and try deleting your account.")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.message}")),
        );
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
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

  // PRIVACY POLICY PAGE
  Widget _privacyPolicyPage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text("Privacy Policy", style: TextStyle(color: Colors.white)),
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Privacy Policy",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              "Last Updated: ${DateTime.now().toLocal().toString().split(' ')[0]}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "1. Information We Collect",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "• Account Information: Name, email address\n"
              "• Usage Data: App interactions, session duration, features used\n"
              "• Device Information: Device type, OS version, unique device identifiers",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "2. How We Use Your Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "• Provide and maintain our services\n"
              "• Notify you about changes to our service\n"
              "• Provide customer support\n"
              "• Gather analysis to improve our service\n"
              "• Monitor usage of our service\n"
              "• Detect, prevent and address technical issues",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "3. Legal Basis for Processing",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "We process your information based on:\n\n"
              "• Your consent - You have given us permission to process your data\n"
              "• Contractual obligations - Processing is necessary for service delivery\n"
              "• Legal requirements - To comply with applicable US laws and regulations\n"
              "• Legitimate interests - To improve and secure our services",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "4. Data Retention",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "We will retain your personal information only for as long as is necessary for the purposes set out in this Privacy Policy. We will retain and use your information to the extent necessary to comply with our legal obligations, resolve disputes, and enforce our legal agreements and policies.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "5. Your Privacy Rights (CCPA/CPRA)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "If you are a California resident or located in the USA, you have the following privacy rights:\n\n"
              "• Right to know - Request information about data collected\n"
              "• Right to delete - Request deletion of your personal data\n"
              "• Right to opt-out - Opt-out of data sales (we do not sell data)\n"
              "• Right to correct - Correct inaccurate information\n"
              "• Right to limit - Limit use of sensitive personal information\n"
              "• Right to non-discrimination - Equal service regardless of rights exercise\n\n"
              "To exercise these rights, contact us using Section 8.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "6. CCPA Privacy Rights (California Residents)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "If you are a California resident, the California Consumer Privacy Act (CCPA) provides you with specific rights regarding your personal information:\n\n"
              "• Right to know about personal information collected, used, shared, or sold\n"
              "• Right to delete personal information held by businesses\n"
              "• Right to opt-out of sale of personal information\n"
              "• Right to non-discrimination for exercising your CCPA rights",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "7. Data Security",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "We use industry-standard encryption (AES-256) for data at rest and TLS 1.3 for data in transit. We regularly perform security audits and access is restricted to authorized personnel only.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "8. Contact Us",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "If you have any questions about this Privacy Policy, please contact us at:\n\n"
              "Email: archengservices2022@gmail.com\n"
              "Address: 315 Lemay Ferry Road, Suit 135, Saint Louis, MO 63125",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // TERMS & CONDITIONS PAGE
  Widget _termsPage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text("Terms & Conditions", style: TextStyle(color: Colors.white)),
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Terms & Conditions",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              "Last Updated: ${DateTime.now().toLocal().toString().split(' ')[0]}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "1. Acceptance of Terms",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "By downloading, accessing, or using this application, you agree to be bound by these Terms & Conditions. If you do not agree to all the terms, please do not use the app.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "2. Eligibility",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "You must be at least 13 years old to use this application. By using the app, you represent and warrant that you meet this age requirement.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "3. User Accounts",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "You are responsible for maintaining the confidentiality of your account credentials. You agree to accept responsibility for all activities that occur under your account.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "4. Prohibited Activities",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "You agree not to:\n\n"
              "• Use the app for any illegal purpose\n"
              "• Attempt to gain unauthorized access to the app or its systems\n"
              "• Interfere with or disrupt the app's servers or networks\n"
              "• Upload viruses or malicious code\n"
              "• Harass, abuse, or harm another person\n"
              "• Impersonate another person or entity",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "5. Intellectual Property",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "The app and its original content, features, and functionality are owned by Arch EngineeringServices and are protected by international copyright, trademark, and other intellectual property laws.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "6. Termination",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "We reserve the right to terminate or suspend your account immediately, without prior notice or liability, for any reason whatsoever. Upon termination, your right to use the app will immediately cease.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "7. Limitation of Liability",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "To the maximum extent permitted by law, Arch Engineering Services shall not be liable for any indirect, punitive, incidental, special, consequential damages arising out of or in connection with the use or inability to use the app.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "8. Governing Law",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "These Terms shall be governed and construed in accordance with the laws of the State of Missouri, without regard to its conflict of law provisions.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "9. Changes to Terms",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "We reserve the right to modify or replace these Terms at any time. Continued use of the app after changes constitutes acceptance of the modified terms.",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "10. Contact Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "If you have any questions about these Terms, please contact us at:\n\n"
              "Email: archengservices2022@gmail.com\n"
              "Address: 315 Lemay Ferry Road, Suit 135, Saint Louis, MO 63125",
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // PRIVACY & SECURITY PAGE
  Widget _privacyAndSecurityPage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text("Privacy & Security", style: TextStyle(color: Colors.white)),
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          // Privacy Policy Tile
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kPrimary.withOpacity(0.1),
                child: const Icon(Icons.privacy_tip, color: kPrimary),
              ),
              title: const Text("Privacy Policy", style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text("Read our privacy policy"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => _privacyPolicyPage()));
              },
            ),
          ),

          // Terms & Conditions Tile
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kPrimary.withOpacity(0.1),
                child: const Icon(Icons.description, color: kPrimary),
              ),
              title: const Text("Terms & Conditions", style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text("Read our terms and conditions"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => _termsPage()));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ACCOUNT ACTIONS PAGE
  Widget _accountActionsPage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text("Account Actions", style: TextStyle(color: Colors.white)),
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          // Logout Tile
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kPrimary.withOpacity(0.1),
                child: const Icon(Icons.logout, color: kPrimary),
              ),
              title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text("Sign out from your account"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => logout(context),
            ),
          ),

          // Delete Account Tile
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.withOpacity(0.1),
                child: const Icon(Icons.delete_forever, color: Colors.red),
              ),
              title: const Text("Delete Account", style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text("Permanently delete your account and all data"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _confirmDelete(context),
            ),
          ),
        ],
      ),
    );
  }

  // SETTINGS TILE
  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, String subtitle, Widget Function(BuildContext) pageBuilder) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: kPrimary.withOpacity(0.1),
          child: Icon(icon, color: kPrimary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => pageBuilder(context)));
        },
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
          _buildSettingsTile(context, Icons.security, "Privacy & Security", "Manage your privacy and security settings", (ctx) => _privacyAndSecurityPage(ctx)),
          const SizedBox(height: 10),
          _buildSettingsTile(context, Icons.account_circle, "Account Actions", "Manage your account (logout, delete)", (ctx) => _accountActionsPage(ctx)),
        ],
      ),
    );
  }
}