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
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = 'General';
  String _selectedAudience = 'All Users';
  File? _selectedImage;
  File? _selectedPDF;
  String? _existingImageUrl;
  String? _existingPdfUrl;
  bool _isLoading = false;
  List<String> _selectedClientIds = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filteredClients = [];
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
    _searchController.addListener(_filterClients);

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
    _searchController.dispose();
    super.dispose();
  }

  void _filterClients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredClients = List.from(_clients);
      } else {
        _filteredClients = _clients.where((client) {
          final name = client['name'].toString().toLowerCase();
          final email = client['email'].toString().toLowerCase();
          return name.contains(query) || email.contains(query);
        }).toList();
      }
    });
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
        _filteredClients = List.from(_clients);
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
        _existingImageUrl = null; // Clear existing when new image is picked
      });
    }
  }

  Future<void> _pickPDF() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedPDF = File(result.files.single.path!);
        _existingPdfUrl = null; // Clear existing when new PDF is picked
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

    if (_selectedAudience == 'Specific Clients' && _selectedClientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one client')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl = _existingImageUrl;
      String? pdfUrl = _existingPdfUrl;

      if (_selectedImage != null) {
        imageUrl = await _uploadFile(_selectedImage!, 'announcements/images');
        if (imageUrl == null) throw Exception('Image upload failed');
      }

      if (_selectedPDF != null) {
        pdfUrl = await _uploadFile(_selectedPDF!, 'announcements/pdfs');
        if (pdfUrl == null) throw Exception('PDF upload failed');
      }

      final data = {
      'title': title,
      'message': message,
      'category': _selectedCategory,
      'audience': _selectedAudience,
      'imageUrl': imageUrl,
      'pdfUrl': pdfUrl,
      'trainerName': trainerName.isNotEmpty ? trainerName : _trainerEmail,
      'targetClientIds': _selectedAudience == 'Specific Clients' ? _selectedClientIds : [],
    };

    // ONLY for new
    if (docId == null) {
      data['timestamp'] = FieldValue.serverTimestamp();
      data['reactions'] = {};
      data['comments'] = [];
    }
      
      if (docId != null) {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(docId)
            .update(data);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement updated')),
        );

        Navigator.pop(context); // ✅ THIS LINE ADDED
      }else {
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
        _existingImageUrl = null;
        _existingPdfUrl = null;
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
    _existingImageUrl = data['imageUrl'];
    _existingPdfUrl = data['pdfUrl'];
  }

  void _removeExistingImage() {
    setState(() {
      _existingImageUrl = null;
    });
  }

  void _removeExistingPdf() {
    setState(() {
      _existingPdfUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Announcements', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFF1A2B63),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: const [
              Tab(icon: Icon(Icons.campaign), text: 'Announcements'),
              Tab(icon: Icon(Icons.local_offer), text: 'Promotions'),
              Tab(icon: Icon(Icons.share), text: 'Referrals'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _announcementForm(),
            const PromotionsTab(),
            const ReferralsTab(),
          ],
        ),
      ),
    );
  }

  Widget _announcementForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey.shade50],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2B63).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.campaign, color: Color(0xFF1A2B63), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Create New Announcement',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2B63),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Announcement Title',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.title, color: Color(0xFF1A2B63)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _trainerNameController,
                  decoration: InputDecoration(
                    labelText: 'Your Name (shown to users)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.person, color: Color(0xFF1A2B63)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
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
                    prefixIcon: const Icon(Icons.message, color: Color(0xFF1A2B63)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.category, color: Color(0xFF1A2B63)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
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
                    prefixIcon: const Icon(Icons.people, color: Color(0xFF1A2B63)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                    ),
                  ),
                  items: _audiences
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedAudience = v!),
                ),
                if (_selectedAudience == 'Specific Clients') ...[
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Clients (${_selectedClientIds.length} selected)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A2B63),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search by name or email...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        _isLoadingClients
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : Container(
                                constraints: const BoxConstraints(maxHeight: 300),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredClients.length,
                                  itemBuilder: (context, index) {
                                    final client = _filteredClients[index];
                                    final isSelected = _selectedClientIds.contains(client['id']);
                                    return CheckboxListTile(
                                      title: Text(
                                        client['name'],
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(client['email']),
                                      value: isSelected,
                                      activeColor: const Color(0xFF1A2B63),
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
                                  },
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Attachments',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A2B63)),
                ),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(
                            color: Color(0xFF1A2B63), 
                            width: 1.5,
                          ),
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1A2B63),
                          elevation: 0,
                        ).copyWith(
                          side: MaterialStateProperty.resolveWith<BorderSide>(
                            (Set<MaterialState> states) {
                              if (states.contains(MaterialState.pressed)) {
                                return const BorderSide(
                                  color: Color(0xFF1A2B63),
                                  width: 2.0,
                                );
                              }
                              return const BorderSide(
                                color: Color(0xFF1A2B63),
                                width: 1.5,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickPDF,
                        icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF1A2B63)),
                        label: const Text('Add PDF',
                            style: TextStyle(color: Color(0xFF1A2B63))),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(
                            color: Color(0xFF1A2B63), 
                            width: 1.5,
                          ),
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1A2B63),
                          elevation: 0,
                        ).copyWith(
                          side: MaterialStateProperty.resolveWith<BorderSide>(
                            (Set<MaterialState> states) {
                              if (states.contains(MaterialState.pressed)) {
                                return const BorderSide(
                                  color: Color(0xFF1A2B63),
                                  width: 2.0,
                                );
                              }
                              return const BorderSide(
                                color: Color(0xFF1A2B63),
                                width: 1.5,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_existingImageUrl != null || _existingPdfUrl != null || _selectedImage != null || _selectedPDF != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_existingImageUrl != null)
                          Chip(
                            avatar: const Icon(Icons.image, size: 16),
                            label: Text('Existing Image'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: _removeExistingImage,
                            backgroundColor: Colors.white,
                          ),
                        if (_selectedImage != null)
                          Chip(
                            avatar: const Icon(Icons.image, size: 16),
                            label: Text(_selectedImage!.path.split('/').last),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(() => _selectedImage = null),
                            backgroundColor: Colors.white,
                          ),
                        if (_existingPdfUrl != null)
                          Chip(
                            avatar: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.red),
                            label: Text('Existing PDF'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: _removeExistingPdf,
                            backgroundColor: Colors.white,
                          ),
                        if (_selectedPDF != null)
                          Chip(
                            avatar: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.red),
                            label: Text(_selectedPDF!.path.split('/').last),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(() => _selectedPDF = null),
                            backgroundColor: Colors.white,
                          ),
                      ],
                    ),
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
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white, // ✅ ADD THIS
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (c) => const PostedAnnouncementsScreen()));
                    },
                    icon: const Icon(Icons.view_list, color: Color(0xFF1A2B63)),
                    label: const Text(
                      'View All Announcements',
                      style: TextStyle(
                        color: Color(0xFF1A2B63),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
      'after they complete their first workout plan';

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
      'https://apps.apple.com/us/app/flex-facility/id6755446262';
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF1A2B63), const Color(0xFF2A3B73)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emoji_events, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Text(
                      'Refer & Earn Rewards',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Invite friends and earn exciting rewards!',
                  style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.grey.shade50],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Reward',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2B63),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2B63).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.card_giftcard, 
                              color: Color(0xFF1A2B63), size: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _rewardTitle,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2B63),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _rewardDescription,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
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
            ),
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.grey.shade50],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Referral Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2B63),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Referral Link',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _referralLink.length > 40
                                          ? '${_referralLink.substring(0, 40)}...'
                                          : _referralLink,
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Color(0xFF1A2B63)),
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      _referralCode,
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Color(0xFF1A2B63)),
                                onPressed: () =>
                                    _copyToClipboard(_referralCode, 'Code'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share Now'),
              onPressed: _shareLink,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF1A2B63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.grey.shade50],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2B63).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_offer, 
                                color: Color(0xFF1A2B63), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _editPromoId != null ? 'Edit Promotion' : 'Create Promotion',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2B63),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _promoTitleController,
                        decoration: InputDecoration(
                          labelText: 'Promotion Title',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.title, color: Color(0xFF1A2B63)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Title is required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _promoDescController,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.description, color: Color(0xFF1A2B63)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                          ),
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
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.percent, color: Color(0xFF1A2B63)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Offer is required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _promoCodeController,
                        decoration: InputDecoration(
                          labelText: 'Promo Code',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.code, color: Color(0xFF1A2B63)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF1A2B63), width: 2),
                          ),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SwitchListTile(
                          title: const Text(
                            'Active Promotion',
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
          ),
          const SizedBox(height: 24),
          const Text(
            'Active Promotions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A2B63),
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
                return Center(
                  child: Column(
                    children: [
                      const Icon(Icons.local_offer, size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No promotions yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
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
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.white, Colors.grey.shade50],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    m['title'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Color(0xFF1A2B63),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: (m['active'] ?? false)
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (m['active'] ?? false) ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      color: (m['active'] ?? false)
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
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2B63).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_offer, 
                                      color: Color(0xFF1A2B63), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${m['offer']} • Code: ${m['code']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A2B63),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, 
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  '${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit, 
                                        color: Colors.blue, size: 20),
                                  ),
                                  onPressed: () => _loadPromo(m),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.delete,
                                        color: Colors.red, size: 20),
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Delete Promotion'),
                                        content: const Text(
                                            'Do you want to delete this promotion?'),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(c, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(c, true),
                                            child: const Text('Delete',
                                                style: TextStyle(color: Colors.red)),
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
  final String? initialAnnouncementId;

  const PostedAnnouncementsScreen({super.key, this.initialAnnouncementId});
  
  @override
  State<PostedAnnouncementsScreen> createState() =>
      _PostedAnnouncementsScreenState();
}

class _PostedAnnouncementsScreenState extends State<PostedAnnouncementsScreen> {
  String _selectedFilter = 'All';
  String? _selectedAnnouncementId;
  Map<String, TextEditingController> _replyControllers = {};

  @override
  void initState() {
    super.initState();
    _selectedAnnouncementId = widget.initialAnnouncementId;
  }

  @override
  void dispose() {
    _replyControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _addReply(String announcementId, String commentId, String replyText) async {
    if (replyText.trim().isEmpty) return;

    try {
      final announcementRef = FirebaseFirestore.instance
          .collection('announcements')
          .doc(announcementId);
      
      final announcementDoc = await announcementRef.get();
      final announcementData = announcementDoc.data()!;
      final comments = List<Map<String, dynamic>>.from(announcementData['comments'] ?? []);
      
      final commentIndex = comments.indexWhere((c) => 
        c['timestamp'] != null && 
        (c['timestamp'] as Timestamp).millisecondsSinceEpoch.toString() == commentId
      );

      if (commentIndex != -1) {
        final replies = List<Map<String, dynamic>>.from(comments[commentIndex]['replies'] ?? []);
        
        replies.add({
          'userId': FirebaseAuth.instance.currentUser!.uid,
          'username': 'Admin',
          'text': replyText,
          'timestamp': Timestamp.now(),
          'isAdmin': true,
        });

        comments[commentIndex]['replies'] = replies;
        
        await announcementRef.update({'comments': comments});
        
        _replyControllers[commentId]?.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding reply: $e')),
      );
    }
  }

  Future<void> _deleteComment(String announcementId, String commentId) async {
    try {
      final announcementRef = FirebaseFirestore.instance
          .collection('announcements')
          .doc(announcementId);
      
      final announcementDoc = await announcementRef.get();
      final comments = List<Map<String, dynamic>>.from(announcementDoc.data()?['comments'] ?? []);
      
      comments.removeWhere((c) => 
        c['timestamp'] != null && 
        (c['timestamp'] as Timestamp).millisecondsSinceEpoch.toString() == commentId
      );
      
      await announcementRef.update({'comments': comments});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting comment: $e')),
      );
    }
  }

  Future<void> _deleteReply(String announcementId, String commentId, String replyTimestamp) async {
    try {
      final announcementRef = FirebaseFirestore.instance
          .collection('announcements')
          .doc(announcementId);
      
      final announcementDoc = await announcementRef.get();
      final comments = List<Map<String, dynamic>>.from(announcementDoc.data()?['comments'] ?? []);
      
      final commentIndex = comments.indexWhere((c) => 
        c['timestamp'] != null && 
        (c['timestamp'] as Timestamp).millisecondsSinceEpoch.toString() == commentId
      );

      if (commentIndex != -1) {
        final replies = List<Map<String, dynamic>>.from(comments[commentIndex]['replies'] ?? []);
        
        replies.removeWhere((r) => 
          r['timestamp'] != null && 
          (r['timestamp'] as Timestamp).millisecondsSinceEpoch.toString() == replyTimestamp
        );
        
        comments[commentIndex]['replies'] = replies;
        await announcementRef.update({'comments': comments});
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply deleted successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting reply: $e')),
      );
    }
  }

  Widget _buildReactionSummary(Map<String, dynamic> reactions) {
    Map<String, int> reactionCounts = {};
    reactions.forEach((userId, emoji) {
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
    });

    if (reactionCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 4,
      children: reactionCounts.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.key,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              Text(
                '${entry.value}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCommentSection(String announcementId, List<dynamic> comments) {
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'No comments yet',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        final commentTimestamp = comment['timestamp'] as Timestamp?;
        final commentId = commentTimestamp?.millisecondsSinceEpoch.toString() ?? 'comment_$index';
        
        if (!_replyControllers.containsKey(commentId)) {
          _replyControllers[commentId] = TextEditingController();
        }

        final replies = List<Map<String, dynamic>>.from(comment['replies'] ?? []);

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main comment
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User avatar
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: comment['isAdmin'] == true
                          ? const Color(0xFF1A2B63)
                          : Colors.grey.shade300,
                      child: Text(
                        comment['username']?[0]?.toUpperCase() ?? 'U',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: comment['isAdmin'] == true 
                              ? Colors.white 
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Comment content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Username and admin badge
                          Row(
                            children: [
                              Text(
                                comment['username'] ?? 'User',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF1A2B63),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (comment['isAdmin'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A2B63),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ADMIN',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              // Delete button for non-admin comments
                              if (comment['isAdmin'] != true)
                                IconButton(
                                  icon: Icon(Icons.delete_outline, 
                                      size: 18, color: Colors.red.shade300),
                                  onPressed: () => _deleteComment(announcementId, commentId),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          
                          // Comment text
                          const SizedBox(height: 6),
                          Text(
                            comment['text'] ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          
                          // Timestamp
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.access_time, 
                                  size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                commentTimestamp != null
                                    ? DateFormat('MMM dd, yyyy • hh:mm a').format(commentTimestamp.toDate())
                                    : 'Just now',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Replies section
              if (replies.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Column(
                    children: replies.map((reply) {
                      final replyTimestamp = reply['timestamp'] as Timestamp?;
                      final replyId = replyTimestamp?.millisecondsSinceEpoch.toString() ?? '';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: reply['isAdmin'] == true
                              ? const Color(0xFF1A2B63).withOpacity(0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: reply['isAdmin'] == true
                                ? const Color(0xFF1A2B63).withOpacity(0.2)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Reply avatar
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: reply['isAdmin'] == true
                                  ? const Color(0xFF1A2B63)
                                  : Colors.grey.shade300,
                              child: Text(
                                reply['username']?[0]?.toUpperCase() ?? 'R',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: reply['isAdmin'] == true 
                                      ? Colors.white 
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            
                            // Reply content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Username and admin badge
                                  Row(
                                    children: [
                                      Text(
                                        reply['username'] ?? 'Reply',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: reply['isAdmin'] == true
                                              ? const Color(0xFF1A2B63)
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (reply['isAdmin'] == true) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A2B63),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: const Text(
                                            'Admin',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 7,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      // Delete reply button
                                      IconButton(
                                        icon: Icon(Icons.close, 
                                            size: 14, color: Colors.grey.shade400),
                                        onPressed: () => _deleteReply(
                                            announcementId, commentId, replyId),
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                  
                                  // Reply text
                                  const SizedBox(height: 4),
                                  Text(
                                    reply['text'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  
                                  // Timestamp
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, 
                                          size: 10, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Text(
                                        replyTimestamp != null
                                            ? DateFormat('MMM dd, hh:mm a').format(replyTimestamp.toDate())
                                            : 'Just now',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              // Reply input for admin
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextField(
                          controller: _replyControllers[commentId],
                          decoration: InputDecoration(
                            hintText: 'Reply as admin...',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2B63),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1A2B63).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        onPressed: () {
                          if (_replyControllers[commentId]!.text.trim().isNotEmpty) {
                            _addReply(
                              announcementId,
                              commentId,
                              _replyControllers[commentId]!.text.trim(),
                            );
                          }
                        },
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A2B63),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: DropdownButton<String>(
              dropdownColor: const Color(0xFF1A2B63),
              value: _selectedFilter,
              underline: const SizedBox(),
              icon: const Icon(Icons.filter_list, color: Colors.white, size: 20),
              items: ['All', 'General', 'Birthday', 'Event', 'Important']
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat, 
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
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
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.campaign, size: 50, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No $_selectedFilter announcements',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
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
              final isSelected = _selectedAnnouncementId == d.id;
              final reactions = Map<String, dynamic>.from(m['reactions'] ?? {});
              final comments = List<dynamic>.from(m['comments'] ?? []);

              return Card(
                elevation: isSelected ? 8 : 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        isSelected ? const Color(0xFF1A2B63).withOpacity(0.02) : Colors.white,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Main announcement content
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedAnnouncementId = null;
                            } else {
                              _selectedAnnouncementId = d.id;
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A2B63).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        m['trainerName']?[0]?.toUpperCase() ?? 'A',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xFF1A2B63),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                m['title'] ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: Color(0xFF1A2B63),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Posted by ${m['trainerName'] ?? 'Unknown'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                m['message'] ?? '',
                                style: const TextStyle(fontSize: 15, height: 1.5),
                              ),
                              if (m['imageUrl'] != null) ...[
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    m['imageUrl'],
                                    height: 200,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              
                              // Stats row (reactions and comments)
                              Row(
                                children: [
                                  // Reactions summary
                                  if (reactions.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.emoji_emotions,
                                              size: 14, color: Colors.orange),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${reactions.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  // Comments count
                                  if (comments.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.comment,
                                              size: 14, color: Colors.blue.shade400),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${comments.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const Spacer(),
                                  // Category chip
                                  _buildCategoryChip(m['category'] ?? 'General'),
                                  const SizedBox(width: 12),
                                  // Time
                                  Text(
                                    DateFormat.yMMMd().add_jm().format(dt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Expanded section with comments and actions
                      if (isSelected) ...[
                        const Divider(height: 1),
                        Container(
                          color: Colors.grey.shade50,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Reactions summary detailed
                              if (reactions.isNotEmpty) ...[
                                const Text(
                                  'Reactions',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A2B63),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildReactionSummary(reactions),
                                const SizedBox(height: 16),
                              ],
                              
                              // Comments section
                              const Text(
                                'Comments',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2B63),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildCommentSection(d.id, comments),
                              
                              const SizedBox(height: 16),
                              
                              // Action buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
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
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Edit'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
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
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete Announcement'),
                                          content: const Text(
                                              'Are you sure you want to delete this announcement?'),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                FirebaseFirestore.instance
                                                    .collection('announcements')
                                                    .doc(d.id)
                                                    .delete();
                                                Navigator.pop(ctx);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                      content: Text('Announcement deleted')),
                                                );
                                              },
                                              child: const Text('Delete',
                                                  style: TextStyle(color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.delete, size: 16),
                                    label: const Text('Delete'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
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
                      ],
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
    Color textColor;
    IconData icon;
    
    switch (category) {
      case 'Birthday':
        backgroundColor = Colors.pink.shade50;
        textColor = Colors.pink.shade700;
        icon = Icons.cake;
        break;
      case 'Event':
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        icon = Icons.event;
        break;
      case 'Important':
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        icon = Icons.priority_high;
        break;
      default:
        backgroundColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            category,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ClientPromotionsScreen extends StatelessWidget {
  const ClientPromotionsScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotions', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.local_offer, size: 50, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No promotions available',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                ],
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
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Colors.grey.shade50],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
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
                                color: isActive 
                                    ? Colors.green.shade50 
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(20),
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2B63).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_offer, 
                                  color: Color(0xFF1A2B63), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${m['offer']} • Code: ${m['code']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A2B63),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, 
                                size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              'Valid: ${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: isActive ? () {} : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A2B63),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Claim Offer',
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}