import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

const Color kPrimary = Color(0xFF1C2D5E);

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  // Profile
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _email = '';
  bool _profileLoading = true;

  // Branding
  String? _logoUrl;
  bool _uploadingLogo = false;

  // App settings
  final _welcomeCtrl = TextEditingController();
  final _bookingCtrl = TextEditingController();
  final _policyCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  bool _settingsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadBranding();
    _loadAppSettings();
  }

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await _fs.collection('users').doc(user.uid).get();
    if (doc.exists) {
      final d = doc.data()!;
      _nameCtrl.text = (d['name'] ?? '').toString();
      _phoneCtrl.text = (d['phone'] ?? '').toString();
      _email = (d['email'] ?? user.email ?? '').toString();
    } else {
      _email = user.email ?? '';
    }
    setState(() => _profileLoading = false);
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _fs.collection('users').doc(user.uid).set({
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _email,
      'role': 'admin',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved')),
    );
  }

  Future<void> _loadBranding() async {
    final doc = await _fs.collection('settings').doc('branding').get();
    if (doc.exists) {
      _logoUrl = doc.data()!['logoUrl'] as String?;
    }
    setState(() {});
  }

  Future<void> _pickAndUploadLogo() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;

    setState(() => _uploadingLogo = true);
    try {
      final bytes = await File(x.path).readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('branding')
          .child('logo_${DateTime.now().millisecondsSinceEpoch}.png');
      final task = await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      final url = await task.ref.getDownloadURL();
      await _fs.collection('settings').doc('branding').set({
        'logoUrl': url,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _logoUrl = url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _loadAppSettings() async {
    final doc = await _fs.collection('settings').doc('app').get();
    if (doc.exists) {
      final d = doc.data()!;
      _welcomeCtrl.text = (d['welcomeEmail'] ?? '').toString();
      _bookingCtrl.text = (d['bookingEmail'] ?? '').toString();
      _policyCtrl.text = (d['cancellationPolicy'] ?? '').toString();
      _termsCtrl.text = (d['termsOfService'] ?? '').toString();
    }
    setState(() => _settingsLoading = false);
  }

  Future<void> _saveAppSettings() async {
    await _fs.collection('settings').doc('app').set({
      'welcomeEmail': _welcomeCtrl.text.trim(),
      'bookingEmail': _bookingCtrl.text.trim(),
      'cancellationPolicy': _policyCtrl.text.trim(),
      'termsOfService': _termsCtrl.text.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App settings saved')),
    );
  }

  // Trainers
  Stream<QuerySnapshot<Map<String, dynamic>>> _trainerStream() {
    return _fs.collection('users').where('role', isEqualTo: 'trainer').snapshots();
  }

  Future<void> _toggleTrainerActive(
      String uid, bool isActive, String trainerName) async {
    await _fs.collection('users').doc(uid).set({
      'isActive': isActive,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${trainerName.isEmpty ? 'Trainer' : trainerName} '
          '${isActive ? 'activated' : 'deactivated'}')),
    );
  }

  Future<void> _sendReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset email sent to $email')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send reset email: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _welcomeCtrl.dispose();
    _bookingCtrl.dispose();
    _policyCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  return DefaultTabController(
    length: 4,
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Admin Settings', style: TextStyle(color: Colors.white)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: kPrimary,
            child: TabBar(
              // remove white underline + increase font
              indicatorColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Trainers'),
                Tab(text: 'Branding'),
                Tab(text: 'App Settings'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        children: [
          _buildProfileTab(),
          _buildTrainersTab(),
          _buildBrandingTab(),
          _buildAppSettingsTab(),
        ],
      ),
    ),
  );
}


  // -------- Tabs --------

  Widget _buildProfileTab() {
    if (_profileLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Admin Name'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter your name',
                ),
              ),
              const SizedBox(height: 16),
              _label('Phone'),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter phone number',
                ),
              ),
              const SizedBox(height: 16),
              _label('Email'),
              const SizedBox(height: 6),
              TextField(
                controller: TextEditingController(text: _email),
                readOnly: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                  child: const Text('Save Profile', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrainersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _trainerStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No trainer accounts found.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final uid = docs[i].id;
            final name = (d['name'] ?? '').toString();
            final email = (d['email'] ?? '').toString();
            final isActive = (d['isActive'] ?? true) as bool;

            return _card(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kPrimary.withOpacity(0.12),
                    child: const Icon(Icons.person, color: kPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? 'Trainer' : name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(email, style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  Switch(
                    value: isActive,
                    activeColor: kPrimary,
                    onChanged: (v) => _toggleTrainerActive(uid, v, name),
                  ),
                  IconButton(
                    tooltip: 'Send password reset',
                    icon: const Icon(Icons.email_outlined, color: kPrimary),
                    onPressed: email.isEmpty ? null : () => _sendReset(email),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBrandingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Logo'),
              const SizedBox(height: 12),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 140,
                    height: 140,
                    color: Colors.grey.shade200,
                    child: _logoUrl == null
                        ? const Icon(Icons.image, size: 48, color: Colors.grey)
                        : Image.network(_logoUrl!, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                  icon: _uploadingLogo
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload),
                  label: Text(_uploadingLogo ? 'Uploading...' : 'Upload Logo'),
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Recommended: square PNG, 512×512. Stored at settings/branding.logoUrl',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
Widget _buildAppSettingsTab() {
  if (_settingsLoading) {
    return const Center(child: CircularProgressIndicator());
  }
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Cancellation Policy'),
            const SizedBox(height: 6),
            _multiline(
              _policyCtrl,
              minLines: 4,
              hint: 'Write your cancellation policy...',
            ),
            const SizedBox(height: 16),
            _label('Terms of Service'),
            const SizedBox(height: 6),
            _multiline(
              _termsCtrl,
              minLines: 6,
              hint: 'Write your terms of service...',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveAppSettings,
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                child: const Text('Save Settings', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

 
  // -------- UI helpers --------

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: kPrimary,
        ),
      );

  Widget _multiline(TextEditingController c,
          {int minLines = 3, String? hint}) =>
      TextField(
        controller: c,
        minLines: minLines,
        maxLines: 12,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      );
}
