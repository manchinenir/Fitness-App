import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart'; // For opening PDFs

class PostAnnouncementScreen extends StatefulWidget {
  const PostAnnouncementScreen({super.key});

  @override
  State<PostAnnouncementScreen> createState() => _PostAnnouncementScreenState();
}

class _PostAnnouncementScreenState extends State<PostAnnouncementScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _trainerNameController = TextEditingController();

  String _selectedCategory = 'General';
  String _selectedAudience = 'All Users';
  File? _selectedImage;
  File? _selectedPDF;
  bool _isLoading = false;

  final List<String> _categories = ['General', 'Birthday', 'Event', 'Important'];
  final List<String> _audiences = ['All Users', 'Specific Group'];

  String? _editingDocId;
  String _trainerEmail = '';

  @override
  void initState() {
    super.initState();
    _fetchTrainerInfo();
  }

  Future<void> _fetchTrainerInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _trainerEmail = user.email ?? '';
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snapshot.data();
      setState(() {
        final fetchedName = (data != null && data['name'] != null) ? data['name'].toString().trim() : '';
        _trainerNameController.text = fetchedName.isNotEmpty ? fetchedName : _trainerEmail;
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
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedPDF = File(result.files.single.path!);
      });
    }
  }

  Future<String?> _uploadFile(File file, String folder) async {
    try {
      final fileName = '$folder/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putFile(file);
      final downloadURL = await ref.getDownloadURL();
      print("$folder uploaded: $downloadURL");
      return downloadURL;
    } catch (e) {
      print("$folder upload failed: $e");
      return null;
    }
  }

  Future<void> _postAnnouncement({String? docId}) async {
    final String title = _titleController.text.trim();
    final String message = _messageController.text.trim();
    final String trainerName = _trainerNameController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
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
        final existingDoc = await FirebaseFirestore.instance.collection('announcements').doc(docId).get();
        imageUrl = existingDoc.data()?['imageUrl'];
      }

      if (_selectedPDF != null) {
        pdfUrl = await _uploadFile(_selectedPDF!, 'announcements/pdfs');
        if (pdfUrl == null) throw Exception('PDF upload failed');
      } else if (docId != null) {
        final existingDoc = await FirebaseFirestore.instance.collection('announcements').doc(docId).get();
        pdfUrl = existingDoc.data()?['pdfUrl'];
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
        // ✅ priority removed
      };

      if (docId != null) {
        await FirebaseFirestore.instance.collection('announcements').doc(docId).update(data);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement updated')));
      } else {
        await FirebaseFirestore.instance.collection('announcements').add(data);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement posted successfully')));
      }

      _titleController.clear();
      _messageController.clear();
      _trainerNameController.clear();
      setState(() {
        _selectedImage = null;
        _selectedPDF = null;
        _selectedCategory = 'General';
        _selectedAudience = 'All Users';
        _editingDocId = null;
      });
    } catch (e) {
      print('Post error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting: ${e.toString()}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loadForEditing(Map<String, dynamic> data, String docId) {
    setState(() {
      _titleController.text = data['title'];
      _messageController.text = data['message'];
      _selectedCategory = data['category'];
      _selectedAudience = data['audience'];
      _trainerNameController.text = data['trainerName'] ?? '';
      _editingDocId = docId;
    });
  }

  String _emojiFromReaction(String reaction) {
    switch (reaction) {
      case 'like':
        return '👍';
      case 'love':
        return '❤️';
      case 'celebrate':
        return '🎉';
      case 'clap':
        return '👏';
      default:
        return reaction;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Post Announcement',
          style: TextStyle(color: Colors.white), // ✅ Fixed: White text
        ),
        backgroundColor: const Color(0xFF1A2B63),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xFFF5FAFF),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _trainerNameController,
                decoration: const InputDecoration(labelText: 'Your Name (shown to users)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedAudience,
                items: _audiences.map((aud) => DropdownMenuItem(value: aud, child: Text(aud))).toList(),
                onChanged: (val) => setState(() => _selectedAudience = val!),
                decoration: const InputDecoration(labelText: 'Audience'),
              ),
              const SizedBox(height: 12),
              if (_selectedImage != null) Image.file(_selectedImage!, height: 150),
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Pick Image'),
              ),
              const SizedBox(height: 8),
              if (_selectedPDF != null) Text('PDF Selected: ${_selectedPDF!.path.split('/').last}'),
              ElevatedButton(
                onPressed: _pickPDF,
                child: const Text('Pick PDF'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isLoading ? null : () => _postAnnouncement(docId: _editingDocId),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(_editingDocId != null ? 'Update Announcement' : 'Post Announcement'),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const Text('Previous Announcements:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('announcements')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('No announcements found.');
                  }

                  return SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final doc = snapshot.data!.docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final reactions = data['reactions'] as Map<String, dynamic>?;

                        final Timestamp? timestamp = data['timestamp'];
                        final DateTime postTime = timestamp?.toDate() ?? DateTime.now();
                        final Duration difference = DateTime.now().difference(postTime);
                        final bool isNew = difference.inHours < 24;

                        return Card(
                          color: isNew ? const Color(0xFFE0F2FF) : const Color(0xFFFFE4E1),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (data['trainerName'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'Posted by: ${data['trainerName']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                Text(data['title'] ?? ''),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['message'] ?? ''),
                                if (data['imageUrl'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Image.network(
                                      data['imageUrl'],
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                if (data['pdfUrl'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: InkWell(
                                      onTap: () async {
                                        final url = Uri.parse(data['pdfUrl']);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url);
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Could not open PDF')),
                                          );
                                        }
                                      },
                                      child: const Text(
                                        'Open Attached PDF',
                                        style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                                      ),
                                    ),
                                  ),
                                Text('Category: ${data['category']}'),
                                Text('Audience: ${data['audience']}'),
                                if (timestamp != null)
                                  Text('Posted on: ${DateFormat.yMMMd().add_jm().format(postTime)}'),
                                const SizedBox(height: 4),
                                if (reactions != null && reactions.isNotEmpty) ...[
                                  Text('Reacted: ${reactions.values.map((r) => _emojiFromReaction(r)).join(' ')}'),
                                  Text(
                                    'Total Reactions: ${reactions.length}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ] else ...[
                                  const Text('Reacted: -'),
                                  const Text('Total Reactions: 0'),
                                ],
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _loadForEditing(data, doc.id);
                                } else if (value == 'delete') {
                                  FirebaseFirestore.instance.collection('announcements').doc(doc.id).delete();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Announcement deleted')),
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}