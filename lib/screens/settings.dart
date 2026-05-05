import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

const Color kPrimary = Color(0xFF1C2D5E);
const Color kBackground = Color(0xFFF5F8FF);
const Color kCardBackground = Color(0xFFFFFFFF);
const Color kAccent = Color(0xFFFF6B35);
const Color kSuccess = Color(0xFF4CAF50);
const Color kWarning = Color(0xFFFFC107);
const Color kError = Color(0xFFF44336);

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

  // Client management
  String? _selectedClientId;
  Map<String, dynamic>? _selectedClientData;
  bool _showClientManagement = false;

  // Privacy & Security management
  bool _showPrivacySecurity = false;

  // Tab controller
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProfile();
    _loadBranding();
    _loadAppSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _welcomeCtrl.dispose();
    _bookingCtrl.dispose();
    _policyCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
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

  // Clients
  Stream<QuerySnapshot<Map<String, dynamic>>> _clientStream() {
    return _fs.collection('users').where('role', isEqualTo: 'client').snapshots();
  }

  Future<void> _logAccountAction(String userId, String action, String performedBy) async {
    await _fs.collection('audit_logs').add({
      'userId': userId,
      'action': action,
      'performedBy': performedBy,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleClientActive(String uid, bool isActive, String clientName) async {
    await _fs.collection('users').doc(uid).set({
      'isActive': isActive,
      'deactivatedBy': isActive ? null : 'admin',
      'deactivatedAt': isActive ? null : FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    await _logAccountAction(uid, isActive ? 'account_activated' : 'account_deactivated', 'admin_${_auth.currentUser?.uid}');
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${clientName.isEmpty ? 'Client' : clientName} '
          '${isActive ? 'activated' : 'deactivated'}')),
    );
  }

  Future<void> _toggleClientTabAccess(String uid, String tab, bool isEnabled, String clientName) async {
    await _fs.collection('users').doc(uid).set({
      'disabledTabs': isEnabled 
        ? FieldValue.arrayRemove([tab])
        : FieldValue.arrayUnion([tab]),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    await _logAccountAction(uid, 'tab_access_${isEnabled ? 'enabled' : 'disabled'}_$tab', 'admin_${_auth.currentUser?.uid}');
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${clientName.isEmpty ? 'Client' : clientName} '
          '${isEnabled ? 'enabled' : 'disabled'} $tab access')),
    );
  }

  void _selectClient(String clientId, Map<String, dynamic> clientData) {
    setState(() {
      _selectedClientId = clientId;
      _selectedClientData = clientData;
    });
  }

  void _clearClientSelection() {
    setState(() {
      _selectedClientId = null;
      _selectedClientData = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          backgroundColor: kPrimary,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Admin Settings', style: TextStyle(color: Colors.white)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Container(
              color: kPrimary,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                isScrollable: false,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
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
          controller: _tabController,
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

  Widget _buildProfileTab() {
    if (_profileLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Admin Name'),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter your name',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              _label('Phone'),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter phone number',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              _label('Email'),
              const SizedBox(height: 10),
              TextField(
                controller: TextEditingController(text: _email),
                readOnly: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text('Save Profile', style: TextStyle(color: Colors.white, fontSize: 16)),
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
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final uid = docs[i].id;
            final name = (d['name'] ?? '').toString();
            final email = (d['email'] ?? '').toString();
            final isActive = (d['isActive'] ?? true) as bool;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: _card(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: kPrimary.withOpacity(0.12),
                      radius: 24,
                      child: const Icon(Icons.person, color: kPrimary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.isEmpty ? 'Trainer' : name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 6),
                          Text(email, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Switch(
                      value: isActive,
                      activeColor: kPrimary,
                      onChanged: (v) => _toggleTrainerActive(uid, v, name),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBrandingTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Logo'),
              const SizedBox(height: 16),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 160,
                    height: 160,
                    color: Colors.grey.shade200,
                    child: _logoUrl == null
                        ? const Icon(Icons.image, size: 56, color: Colors.grey)
                        : Image.network(_logoUrl!, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                  icon: _uploadingLogo
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload, size: 20),
                  label: Text(_uploadingLogo ? 'Uploading...' : 'Upload Logo', 
                    style: const TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recommended: square PNG, 512×512. Stored at settings/branding.logoUrl',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppSettingsTab() {
    if (_showClientManagement) {
      return _buildClientManagementView();
    }
    
    if (_showPrivacySecurity) {
      return _buildPrivacySecurityView();
    }
    
    return Column(
      children: [
        const SizedBox(height: 30),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 👥 Client Management Card
              _buildSettingsCard(
                icon: Icons.people,
                title: 'Client Management',
                subtitle: 'Manage client accounts, access controls, and permissions',
                onTap: () {
                  setState(() {
                    _showClientManagement = true;
                  });
                },
              ),
              
              const SizedBox(height: 20),
              
              // 🔒 Privacy & Security Card
              _buildSettingsCard(
                icon: Icons.security,
                title: 'Privacy & Security',
                subtitle: 'View privacy policy and terms & conditions',
                onTap: () {
                  setState(() {
                    _showPrivacySecurity = true;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: kPrimary.withOpacity(0.1),
                child: Icon(icon, color: kPrimary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientManagementView() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _clientStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        
        if (_selectedClientId != null && _selectedClientData != null) {
          return _buildClientDetailView(_selectedClientId!, _selectedClientData!);
        }
        
        if (docs.isEmpty) {
          return const Center(child: Text('No client accounts found.'));
        }
        
        return Scaffold(
          backgroundColor: kBackground,
          appBar: AppBar(
            backgroundColor: kPrimary,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Client Management', style: TextStyle(color: Colors.white)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                setState(() {
                  _showClientManagement = false;
                  _selectedClientId = null;
                  _selectedClientData = null;
                });
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Client Management',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kPrimary),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Select a client to manage their account status and dashboard access',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (context, index) => const Divider(height: 20),
                      itemBuilder: (context, i) {
                        final d = docs[i].data();
                        final uid = docs[i].id;
                        final name = (d['name'] ?? '').toString();
                        final email = (d['email'] ?? '').toString();
                        final isActive = (d['isActive'] ?? true) as bool;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: kPrimary.withOpacity(0.12),
                            radius: 24,
                            child: const Icon(Icons.person, color: kPrimary, size: 24),
                          ),
                          title: Text(
                            name.isEmpty ? 'Client' : name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                          ),
                          subtitle: Text(email, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive ? kSuccess : Colors.grey[300],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Deactivated',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          onTap: () => _selectClient(uid, d),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClientDetailView(String clientId, Map<String, dynamic> clientData) {
    final name = (clientData['name'] ?? '').toString();
    final email = (clientData['email'] ?? '').toString();
    final isActive = (clientData['isActive'] ?? true) as bool;
    final disabledTabs = List<String>.from(clientData['disabledTabs'] ?? []);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Client Settings', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _clearClientSelection,
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _fs.collection('users').doc(clientId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            final updatedData = snapshot.data!.data()!;
            final updatedIsActive = (updatedData['isActive'] ?? true) as bool;
            final updatedDisabledTabs = List<String>.from(updatedData['disabledTabs'] ?? []);
            
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: kPrimary.withOpacity(0.12),
                              child: Icon(Icons.person, size: 48, color: kPrimary),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              name.isEmpty ? 'Client' : name,
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kPrimary),
                            ),
                            const SizedBox(height: 8),
                            Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
                
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account Status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPrimary)),
                      const SizedBox(height: 12),
                      Text('Control whether this client can login to the App', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Login Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                const SizedBox(height: 4),
                                Text(updatedIsActive ? 'Client can access' : 'Client access is blocked', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: updatedIsActive ? kSuccess.withOpacity(0.1) : kError.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: updatedIsActive ? kSuccess : kError, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _toggleClientActive(clientId, true, name),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: updatedIsActive ? kSuccess : Colors.transparent,
                                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
                                    ),
                                    child: Text('Active', style: TextStyle(color: updatedIsActive ? Colors.white : kSuccess, fontWeight: FontWeight.w600, fontSize: 14)),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _toggleClientActive(clientId, false, name),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: !updatedIsActive ? kError : Colors.transparent,
                                      borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                                    ),
                                    child: Text('Deactive', style: TextStyle(color: !updatedIsActive ? Colors.white : kError, fontWeight: FontWeight.w600, fontSize: 14)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard Access Control', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPrimary)),
                      const SizedBox(height: 12),
                      Text('Enable or disable specific dashboard tabs for this client', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _buildTabToggle(clientId, 'schedule', 'My Schedule', updatedDisabledTabs.contains('schedule'), name),
                          _buildTabToggle(clientId, 'booking', 'Book Session', updatedDisabledTabs.contains('booking'), name),
                          _buildTabToggle(clientId, 'plans', 'Plans', updatedDisabledTabs.contains('plans'), name),
                          _buildTabToggle(clientId, 'workouts', 'Workouts', updatedDisabledTabs.contains('workouts'), name),
                          _buildTabToggle(clientId, 'profile', 'Profile', updatedDisabledTabs.contains('profile'), name),
                          _buildTabToggle(clientId, 'announcements', 'Announcements', updatedDisabledTabs.contains('announcements'), name),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
      ),
    );
  }

  Widget _buildPrivacySecurityView() {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Privacy & Security', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _showPrivacySecurity = false;
            });
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildLegalCard(
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            subtitle: 'View our privacy policy',
            onTap: () => _showPrivacyPolicyDialog(),
          ),
          const SizedBox(height: 16),
          _buildLegalCard(
            icon: Icons.description,
            title: 'Terms & Conditions',
            subtitle: 'View our terms and conditions',
            onTap: () => _showTermsDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: kPrimary.withOpacity(0.1), child: Icon(icon, color: kPrimary)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Data Collection & Usage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('We collect basic account information including name and email address. Data is stored securely in Firebase. We do not share personal data with third parties.'),
                const SizedBox(height: 16),
                const Text('Legal Basis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('• Consent: You have given clear consent\n• Contract: Processing is necessary for service delivery\n• Legal obligation: Compliance with applicable laws'),
                const SizedBox(height: 16),
                const Text('Data Subject Rights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('• Right to Access (Art. 15)\n• Right to Rectification (Art. 16)\n• Right to Erasure (Art. 17)\n• Right to Restrict Processing (Art. 18)\n• Right to Data Portability (Art. 20)'),
                const SizedBox(height: 16),
                const Text('Contact Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Email: archengservices2022@gmail.com\nAddress: 315 Lemay Ferry Road, Suit 135, Saint Louis, MO 63125'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms & Conditions'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('1. Acceptance of Terms', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 8),
                Text('By using this application, you agree to be bound by these Terms & Conditions.'),
                SizedBox(height: 16),
                Text('2. User Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 8),
                Text('You are responsible for maintaining the confidentiality of your account credentials.'),
                SizedBox(height: 16),
                Text('3. Prohibited Activities', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 8),
                Text('You agree not to misuse the app, including hacking, spamming, or violating laws.'),
                SizedBox(height: 16),
                Text('4. Compliance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 8),
                Text('We process your data in accordance with regulations. You have the right to access, rectify, and delete your data.'),
                SizedBox(height: 16),
                Text('5. Contact Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 8),
                Text('Email: archengservices2022@gmail.com\nAddress: 315 Lemay Ferry Road, Suit 135, Saint Louis, MO 63125'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildTabToggle(String uid, String tabKey, String tabName, bool isDisabled, String clientName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDisabled ? Colors.grey[200] : kSuccess.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDisabled ? Colors.grey[300]! : kSuccess, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tabName, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: isDisabled ? Colors.grey[600] : Colors.black87)),
          Switch(
            value: !isDisabled,
            activeColor: kSuccess,
            inactiveThumbColor: Colors.grey[500],
            inactiveTrackColor: Colors.grey[300],
            onChanged: (selected) => _toggleClientTabAccess(uid, tabKey, selected, clientName),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kCardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, color: kPrimary, fontSize: 18),
      );
}