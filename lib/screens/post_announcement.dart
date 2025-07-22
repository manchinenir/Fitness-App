import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PostAnnouncementScreen extends StatelessWidget {
  const PostAnnouncementScreen({super.key});

  Future<void> _addComment(String announcementId, String comment) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final username =
        userDoc.exists ? (userDoc.data()?['name'] ?? 'User') : 'User';

    await FirebaseFirestore.instance
        .collection('announcements')
        .doc(announcementId)
        .update({
      'comments': FieldValue.arrayUnion([
        {
          'userId': uid,
          'username': username,
          'text': comment,
          'timestamp': Timestamp.now(),
        }
      ])
    });
  }

  Future<void> _toggleReaction(String announcementId, String? selectedEmoji) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final docRef = FirebaseFirestore.instance.collection('announcements').doc(announcementId);
    final docSnap = await docRef.get();

    Map<String, dynamic> reactions = {};
    final rawReactions = docSnap.data()?['reactions'];
    if (rawReactions != null && rawReactions is Map) {
      reactions = Map<String, dynamic>.from(rawReactions);
    }

    if (selectedEmoji == null || reactions[uid] == selectedEmoji) {
      reactions.remove(uid);
    } else {
      reactions[uid] = selectedEmoji;
    }

    await docRef.update({'reactions': reactions});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], // Body background
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade900, // Top blue header
        title: const Text('Announcements'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('announcements')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final announcements = snapshot.data!.docs;

          return ListView.builder(
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final data = announcements[index].data() as Map<String, dynamic>;
              final docId = announcements[index].id;
              final comments = (data['comments'] ?? []) as List<dynamic>;

              final rawReactions = data['reactions'] ?? {};
              final reactions = Map<String, dynamic>.from(rawReactions);
              final currentUser = FirebaseAuth.instance.currentUser!.uid;
              final currentReaction = reactions[currentUser];

              final TextEditingController commentController = TextEditingController();

              final Timestamp timestamp = data['timestamp'];
              final postTime = timestamp.toDate();
              final isNew = DateTime.now().difference(postTime).inHours < 24;

              // Choose card background
              final cardColor = isNew
                  ? Colors.pink[50]       // New = light pink
                  : Colors.green[50];     // Old = light green

              return Card(
                margin: const EdgeInsets.all(12),
                color: cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['title'] ?? '',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(data['message'] ?? ''),

                      if (data['imageUrl'] != null &&
                          (data['imageUrl'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Image.network(
                            data['imageUrl'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Text('Image failed to load'),
                          ),
                        ),

                      if (data['pdfUrl'] != null &&
                          (data['pdfUrl'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: GestureDetector(
                            onTap: () async {
                              final pdfUrl = data['pdfUrl'];
                              try {
                                await launchUrl(Uri.parse(pdfUrl),
                                    mode: LaunchMode.externalApplication);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Could not open PDF: $e')),
                                );
                              }
                            },
                            child: const Row(
                              children: [
                                Icon(Icons.picture_as_pdf, color: Colors.red),
                                SizedBox(width: 8),
                                Text('View PDF',
                                    style: TextStyle(
                                        decoration: TextDecoration.underline)),
                              ],
                            ),
                          ),
                        ),

                      Text('Priority: ${data['priority'] ?? ''}'),
                      Text('Category: ${data['category'] ?? ''}'),
                      Text('Time: ${postTime.toLocal().toString().split('.')[0]}'),

                      const Divider(),

                      const Text("Comments:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ...comments.map((comment) {
                        return ListTile(
                          title: Text(comment['username'] ?? 'Anonymous'),
                          subtitle: Text(comment['text'] ?? ''),
                          trailing: Text((comment['timestamp'] as Timestamp)
                              .toDate()
                              .toLocal()
                              .toString()
                              .split('.')[0]),
                        );
                      }),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentController,
                              decoration:
                                  const InputDecoration(hintText: 'Add a comment'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () {
                              if (commentController.text.trim().isNotEmpty) {
                                _addComment(
                                    docId, commentController.text.trim());
                                commentController.clear();
                              }
                            },
                          )
                        ],
                      ),

                      const SizedBox(height: 12),

                      const Text("React:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: ['👍', '❤️', '🎉', '👏'].map((emoji) {
                          final isSelected = currentReaction == emoji;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () => _toggleReaction(
                                  docId, isSelected ? null : emoji),
                              child: Text(
                                emoji,
                                style: TextStyle(
                                  fontSize: 24,
                                  backgroundColor: isSelected
                                      ? Colors.yellow.shade100
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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