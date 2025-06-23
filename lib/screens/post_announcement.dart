// post_announcement.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PostAnnouncementScreen extends StatefulWidget {
  const PostAnnouncementScreen({super.key});

  @override
  State<PostAnnouncementScreen> createState() => _PostAnnouncementScreenState();
}

class _PostAnnouncementScreenState extends State<PostAnnouncementScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isLoading = false;

  Future<void> _postAnnouncement() async {
    final String title = _titleController.text.trim();
    final String message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': title,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement posted successfully')),
      );
      _titleController.clear();
      _messageController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post Announcement')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _postAnnouncement,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Post Announcement'),
            )
          ],
        ),
      ),
    );
  }
}
