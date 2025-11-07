import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

class PostAnnouncementScreen extends StatefulWidget {
  final Map<String, dynamic>? editData;
  final String? editDocId;

  const PostAnnouncementScreen({
    super.key,
    this.editData,
    this.editDocId,
  });

  @override
  State<PostAnnouncementScreen> createState() => _PostAnnouncementScreenState();
}

class _PostAnnouncementScreenState extends State<PostAnnouncementScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _trainerNameController = TextEditingController();

  String _selectedCategory = 'General';
  String _selectedAudience = 'All Users';
  File? _selectedImage;
  File? _selectedPDF;
  bool _isLoading = false;
  List<String> _selectedClientIds = [];
  List<Map<String, dynamic>> _clients = [];
  bool _isLoadingClients = false;

  final List<String> _categories = ['General', 'Birthday', 'Event', 'Important'];
  final List<String> _audiences = ['All Users', 'Specific Clients'];

  String _trainerEmail = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _fetchTrainerInfo();
    _tabController = TabController(length: 3, vsync: this);
    _loadClients();

    if (widget.editData != null && widget.editDocId != null) {
      _loadForEditing(widget.editData!, widget.editDocId!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    _trainerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _isLoadingClients = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .get();
      
      setState(() {
        _clients = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Unknown',
            'email': data['email'] ?? '',
          };
        }).toList();
      });
    } catch (e) {
      print('Error loading clients: $e');
    } finally {
      setState(() => _isLoadingClients = false);
    }
  }

  Future<void> _fetchTrainerInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _trainerEmail = user.email ?? '';
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snapshot.data();
      setState(() {
        final fetchedName = (data != null && data['name'] != null)
            ? data['name'].toString().trim()
            : '';
        _trainerNameController.text =
            fetchedName.isNotEmpty ? fetchedName : _trainerEmail;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<void> _pickPDF() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedPDF = File(result.files.single.path!);
      });
    }
  }

  Future<String?> _uploadFile(File file, String folder) async {
    try {
      final fileName =
          '$folder/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _postAnnouncement({String? docId}) async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    final trainerName = _trainerNameController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    // Validate that at least one client is selected when audience is "Specific Clients"
    if (_selectedAudience == 'Specific Clients' && _selectedClientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one client')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl;
      String? pdfUrl;

      if (_selectedImage != null) {
        imageUrl = await _uploadFile(_selectedImage!, 'announcements/images');
        if (imageUrl == null) throw Exception('Image upload failed');
      } else if (docId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('announcements')
            .doc(docId)
            .get();
        imageUrl = doc.data()?['imageUrl'];
      }

      if (_selectedPDF != null) {
        pdfUrl = await _uploadFile(_selectedPDF!, 'announcements/pdfs');
        if (pdfUrl == null) throw Exception('PDF upload failed');
      } else if (docId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('announcements')
            .doc(docId)
            .get();
        pdfUrl = doc.data()?['pdfUrl'];
      }

      final data = {
        'title': title,
        'message': message,
        'category': _selectedCategory,
        'audience': _selectedAudience,
        'imageUrl': imageUrl,
        'pdfUrl': pdfUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'trainerName': trainerName.isNotEmpty ? trainerName : _trainerEmail,
        // This line ensures targetClientIds is saved correctly:
        'targetClientIds': _selectedAudience == 'Specific Clients' ? _selectedClientIds : [],
      };
      if (docId != null) {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(docId)
            .update(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement updated')),
        );
      } else {
        await FirebaseFirestore.instance
            .collection('announcements')
            .add(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement posted successfully')),
        );
      }

      _titleController.clear();
      _messageController.clear();
      _trainerNameController.clear();
      setState(() {
        _selectedImage = null;
        _selectedPDF = null;
        _selectedCategory = 'General';
        _selectedAudience = 'All Users';
        _selectedClientIds = [];
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loadForEditing(Map<String, dynamic> data, String docId) {
    _titleController.text = data['title'] ?? '';
    _messageController.text = data['message'] ?? '';
    _selectedCategory = data['category'] ?? 'General';
    _selectedAudience = data['audience'] ?? 'All Users';
    _trainerNameController.text = data['trainerName'] ?? '';
    _selectedClientIds = List<String>.from(data['targetClientIds'] ?? []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A2B63),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.announcement), text: 'Announcements'),
            Tab(icon: Icon(Icons.group), text: 'Referrals'),
            Tab(icon: Icon(Icons.local_offer), text: 'Promotions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _announcementForm(),
          const ReferralsTab(),
          const PromotionsTab(),
        ],
      ),
    );
  }

  Widget _announcementForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create Announcement',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B63)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF1A2B63), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _trainerNameController,
                decoration: InputDecoration(
                  labelText: 'Your Name (shown to users)',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF1A2B63), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Message',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF1A2B63), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF1A2B63), width: 2),
                  ),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedAudience,
                decoration: InputDecoration(
                  labelText: 'Audience',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF1A2B63), width: 2),
                  ),
                ),
                items: _audiences
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedAudience = v!),
              ),
              if (_selectedAudience == 'Specific Clients') ...[
                const SizedBox(height: 16),
                const Text('Select Clients',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _isLoadingClients
                    ? const CircularProgressIndicator()
                    : Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ExpansionTile(
                          title: Text(
                            _selectedClientIds.isEmpty
                                ? 'Select clients'
                                : '${_selectedClientIds.length} client(s) selected',
                          ),
                          children: [
                            ..._clients.map((client) {
                              final isSelected = _selectedClientIds.contains(client['id']);
                              return CheckboxListTile(
                                title: Text('${client['name']} (${client['email']})'),
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedClientIds.add(client['id']);
                                    } else {
                                      _selectedClientIds.remove(client['id']);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ],
                        ),
                      ),
              ],
              const SizedBox(height: 20),
              const Text('Attachments',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image, color: Color(0xFF1A2B63)),
                      label: const Text('Add Image',
                          style: TextStyle(color: Color(0xFF1A2B63))),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFF1A2B63)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPDF,
                      icon:
                          const Icon(Icons.picture_as_pdf, color: Color(0xFF1A2B63)),
                      label: const Text('Add PDF',
                          style: TextStyle(color: Color(0xFF1A2B63))),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFF1A2B63)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_selectedImage != null || _selectedPDF != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (_selectedImage != null)
                      Chip(
                        label: Text(_selectedImage!.path.split('/').last),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: () => setState(() => _selectedImage = null),
                      ),
                    if (_selectedPDF != null)
                      Chip(
                        label: Text(_selectedPDF!.path.split('/').last),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: () => setState(() => _selectedPDF = null),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _postAnnouncement(docId: widget.editDocId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A2B63),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.editDocId != null
                              ? 'Update Announcement'
                              : 'Post Announcement',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => const PostedAnnouncementsScreen()));
                  },
                  child: const Text(
                    'View Posted Announcements',
                    style: TextStyle(
                      color: Color(0xFF1A2B63),
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReferralsTab extends StatefulWidget {
  const ReferralsTab({super.key});

  @override
  State<ReferralsTab> createState() => _ReferralsTabState();
}

class _ReferralsTabState extends State<ReferralsTab> {
  String _referralCode = '';
  String _referralLink = '';

  String _rewardTitle = '1 Free Session';
  String _rewardDescription =
      'after they complete their first workout plan in the app.';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadReferralCode();
    _fetchReferralSettings();
  }

  Future<void> _fetchReferralSettings() async {
    final doc =
        await _firestore.collection('referral_settings').doc('global').get();
    if (doc.exists) {
      setState(() {
        _rewardTitle = doc['reward_title'] ?? _rewardTitle;
        _rewardDescription =
            doc['reward_description'] ?? _rewardDescription;
      });
    }
  }

  Future<void> _loadReferralCode() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final userDoc = _firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    if (snapshot.exists && snapshot.data()!['referralCode'] != null) {
      _referralCode = snapshot['referralCode'];
    } else {
      final hash = md5
          .convert(utf8.encode(user.uid))
          .toString()
          .substring(0, 8)
          .toUpperCase();
      await userDoc.update({'referralCode': hash});
      _referralCode = hash;
    }
    _referralLink =
        'https://play.google.com/store/apps/details?id=com.yourfitnessapp&referrer=referral_code%3D$_referralCode';
    setState(() {});
  }

  Future<void> _shareLink() async {
    final message = '''
Join me at Fitness Hub!
Use my referral code: $_referralCode
New members get $_rewardTitle ($_rewardDescription)

$_referralLink
''';
    Share.share(message);
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Refer & Earn',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A2B63),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Invite friends to join and earn exciting rewards!',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reward per Referral',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2B63)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _rewardTitle,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2B63)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _rewardDescription,
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your Referral Details',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2B63)),
          ),
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Referral Link',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              _referralLink,
                              style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () =>
                            _copyToClipboard(_referralLink, 'Link'),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Referral Code',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              _referralCode,
                              style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () =>
                            _copyToClipboard(_referralCode, 'Code'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share Link'),
              onPressed: _shareLink,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFF1A2B63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PromotionsTab extends StatefulWidget {
  const PromotionsTab({super.key});
  @override
  State<PromotionsTab> createState() => _PromotionsTabState();
}

class _PromotionsTabState extends State<PromotionsTab> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _promoTitleController = TextEditingController();
  final TextEditingController _promoDescController = TextEditingController();
  final TextEditingController _promoOfferController = TextEditingController();
  final TextEditingController _promoCodeController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _active = true;
  bool _loading = false;
  String? _editPromoId;

  Future<void> _pickDate(BuildContext ctx, bool isStart) async {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final picked = await showDatePicker(
      context: ctx,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked.toUtc();
        } else {
          _endDate = picked.toUtc();
        }
      });
    }
  }

  String _generateId() => FirebaseFirestore.instance.collection('promotions').doc().id;

  Future<void> _savePromotion() async {
    if (!_formKey.currentState!.validate() || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please complete all fields')));
      return;
    }
    setState(() => _loading = true);
    try {
      final id = _editPromoId ?? _generateId();
      final data = {
        'id': id,
        'title': _promoTitleController.text.trim(),
        'description': _promoDescController.text.trim(),
        'offer': _promoOfferController.text.trim(),
        'code': _promoCodeController.text.trim(),
        'start': Timestamp.fromDate(_startDate!),
        'end': Timestamp.fromDate(_endDate!),
        'active': _active,
      };
      final col = FirebaseFirestore.instance.collection('promotions');
      if (_editPromoId != null) {
        await col.doc(id).update(data);
      } else {
        await col.doc(id).set(data);
      }
      _resetForm();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Promotion saved successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _resetForm() {
    _formKey.currentState!.reset();
    _promoTitleController.clear();
    _promoDescController.clear();
    _promoOfferController.clear();
    _promoCodeController.clear();
    _startDate = null;
    _endDate = null;
    _active = true;
    _editPromoId = null;
  }

  void _loadPromo(Map<String, dynamic> data) {
    setState(() {
      _editPromoId = data['id'];
      _promoTitleController.text = data['title'];
      _promoDescController.text = data['description'];
      _promoOfferController.text = data['offer'];
      _promoCodeController.text = data['code'];
      _startDate = (data['start'] as Timestamp).toDate().toUtc();
      _endDate = (data['end'] as Timestamp).toDate().toUtc();
      _active = data['active'] ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create Promotion',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2B63),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _promoTitleController,
                      decoration: InputDecoration(
                        labelText: 'Promotion Title',
                        labelStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _promoDescController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        labelStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      maxLines: 3,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Description is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _promoOfferController,
                      decoration: InputDecoration(
                        labelText: 'Offer (e.g., 20% off)',
                        labelStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Offer is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _promoCodeController,
                      decoration: InputDecoration(
                        labelText: 'Promo Code',
                        labelStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1A2B63), width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Promo code is required' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(context, true),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: Color(0xFF1A2B63)),
                              backgroundColor: Colors.white,
                            ),
                            child: Text(
                              _startDate == null
                                  ? 'Start Date'
                                  : DateFormat.yMMMd().format(_startDate!.toLocal()),
                              style: const TextStyle(
                                color: Color(0xFF1A2B63),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(context, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: Color(0xFF1A2B63)),
                              backgroundColor: Colors.white,
                            ),
                            child: Text(
                              _endDate == null
                                  ? 'End Date'
                                  : DateFormat.yMMMd().format(_endDate!.toLocal()),
                              style: const TextStyle(
                                color: Color(0xFF1A2B63),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text(
                        'Active',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A2B63),
                        ),
                      ),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                      activeColor: const Color(0xFF1A2B63),
                      activeTrackColor: Colors.blue.shade100,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _savePromotion,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                          backgroundColor: const Color(0xFF1A2B63),
                          foregroundColor: Colors.white,
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _editPromoId != null
                                    ? 'Update Promotion'
                                    : 'Create Promotion',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Existing Promotions',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2B63),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('promotions')
                .orderBy('start', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No promotions yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final d = docs[i];
                  final m = d.data()! as Map<String, dynamic>;
                  final start = (m['start'] as Timestamp).toDate().toLocal();
                  final end = (m['end'] as Timestamp).toDate().toLocal();
                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  m['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFF1A2B63),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            m['description'],
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Offer: ${m['offer']} | Code: ${m['code']}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A2B63),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Valid: ${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(Icons.edit, color: Colors.blue, size: 24),
                                onPressed: () => _loadPromo(m),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red, size: 24),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Delete Promotion'),
                                      content: const Text(
                                          'Do you want to delete this promotion?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await FirebaseFirestore.instance
                                        .collection('promotions')
                                        .doc(m['id'])
                                        .delete();
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class PostedAnnouncementsScreen extends StatefulWidget {
  const PostedAnnouncementsScreen({super.key});
  @override
  State<PostedAnnouncementsScreen> createState() =>
      _PostedAnnouncementsScreenState();
}

class _PostedAnnouncementsScreenState extends State<PostedAnnouncementsScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Posted Announcements', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A2B63),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              dropdownColor: const Color(0xFF1A2B63),
              value: _selectedFilter,
              underline: const SizedBox(),
              icon: const Icon(Icons.filter_list, color: Colors.white),
              items: ['All', 'General', 'Birthday', 'Event', 'Important']
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat, style: const TextStyle(color: Colors.white)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedFilter = v!),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1A2B63),
        onPressed: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (c) => const PostAnnouncementScreen()));
        },
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('announcements')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (c, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          final filtered = _selectedFilter == 'All'
              ? docs
              : docs.where((d) {
                  final m = d.data()! as Map<String, dynamic>;
                  return m['category'] == _selectedFilter;
                }).toList();
          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.announcement, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No $_selectedFilter announcements found',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: filtered.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (ctx, i) {
              final d = filtered[i];
              final m = d.data()! as Map<String, dynamic>;
              final ts = m['timestamp'] as Timestamp?;
              final dt = ts?.toDate().toLocal() ?? DateTime.now();
              final newBadge = DateTime.now().difference(dt).inHours < 24;
              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFF1A2B63),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'By ${m['trainerName'] ?? 'Unknown'}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (newBadge)
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        m['message'] ?? '',
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildCategoryChip(m['category'] ?? 'General'),
                          const Spacer(),
                          Text(
                            DateFormat.yMMMd('en_US').add_jm().format(dt),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => PostAnnouncementScreen(
                                    editData: m,
                                    editDocId: d.id,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A2B63),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              FirebaseFirestore.instance
                                  .collection('announcements')
                                  .doc(d.id)
                                  .delete();
                            },
                            icon: const Icon(Icons.delete, size: 18),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip(String category) {
    Color backgroundColor;
    switch (category) {
      case 'Birthday':
        backgroundColor = Colors.pink.shade100;
        break;
      case 'Event':
        backgroundColor = Colors.green.shade100;
        break;
      case 'Important':
        backgroundColor = Colors.red.shade100;
        break;
      default:
        backgroundColor = Colors.blue.shade100;
    }

    return Chip(
      label: Text(
        category,
        style: TextStyle(
          color: Colors.grey.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: backgroundColor,
      visualDensity: VisualDensity.compact,
    );
  }
}

class ClientPromotionsScreen extends StatelessWidget {
  const ClientPromotionsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotions', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A2B63),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('promotions')
            .orderBy('start', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No promotions available',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i];
              final m = d.data()! as Map<String, dynamic>;
              final start = (m['start'] as Timestamp).toDate().toLocal();
              final end = (m['end'] as Timestamp).toDate().toLocal();
              final isActive = m['active'] ?? false;
              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              m['title'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A2B63),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  isActive ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: isActive
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        m['description'],
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Offer: ${m['offer']} | Code: ${m['code']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A2B63),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Valid: ${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: isActive ? () {} : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A2B63),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Join Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}