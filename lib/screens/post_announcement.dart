// No changes to imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PostAnnouncementScreen extends StatefulWidget {
  const PostAnnouncementScreen({super.key});

  @override
  State<PostAnnouncementScreen> createState() => _PostAnnouncementScreenState();
}

class _PostAnnouncementScreenState extends State<PostAnnouncementScreen> {
  final Set<String> _expandedAnnouncements = {};
  List<String> userBookmarks = [];
  String searchQuery = '';
  List<String> selectedCategories = [];
  Set<String> readAnnouncements = {};
  bool showUnreadOnly = false;

  Future<void> _fetchBookmarks() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    setState(() {
      userBookmarks = List<String>.from(userDoc.data()?['bookmarks'] ?? []);
      readAnnouncements = Set<String>.from(userDoc.data()?['readAnnouncements'] ?? []);
    });
  }

  Future<void> _markAsRead(String announcementId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    setState(() {
      readAnnouncements.add(announcementId);
    });

    await userRef.set({
      'readAnnouncements': FieldValue.arrayUnion([announcementId])
    }, SetOptions(merge: true));
  }

  Future<void> _addComment(String announcementId, String comment) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final username = userDoc.exists ? (userDoc.data()?['name'] ?? 'User') : 'User';

    await FirebaseFirestore.instance.collection('announcements').doc(announcementId).update({
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

  Future<void> _toggleBookmark(String announcementId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final userDoc = await userDocRef.get();

    List<dynamic> bookmarks = userDoc.data()?['bookmarks'] ?? [];

    if (bookmarks.contains(announcementId)) {
      bookmarks.remove(announcementId);
    } else {
      bookmarks.add(announcementId);
    }

    await userDocRef.update({'bookmarks': bookmarks});
    await _fetchBookmarks();
  }

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  String _getCategoryEmoji(String category) {
    switch (category) {
      case 'Important':
        return '⚠️';
      case 'Birthday':
        return '🎂';
      case 'Event':
        return '📅';
      case 'General':
      default:
        return '📢';
    }
  }

  Color _getCardColorByDate(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inHours <= 24) {
      return Colors.pink[50]!;
    } else {
      return Colors.grey[300]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2D5E),
        title: const Text('Announcements', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                if (value == 'all') {
                  selectedCategories = [];
                  searchQuery = '';
                  showUnreadOnly = false;
                } else {
                  showUnreadOnly = value == 'unread';
                }
              });
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(value: 'all', child: Text('All Announcements')),
              const PopupMenuItem<String>(value: 'unread', child: Text('Unread Announcements')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(90),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search announcements...',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) {
                    setState(() {
                      searchQuery = val.toLowerCase();
                    });
                  },
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.filter_list, color: Colors.white),
                label: const Text("Filter Categories", style: TextStyle(color: Colors.white)),
                onPressed: () async {
                  final selected = await showDialog<List<String>>(
                    context: context,
                    builder: (ctx) {
                      final categories = ['Birthday', 'General', 'Event', 'Important'];
                      List<String> tempSelected = [...selectedCategories];

                      return StatefulBuilder(
                        builder: (context, setState) {
                          return AlertDialog(
                            title: const Text("Select Categories"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: categories.map((cat) {
                                return CheckboxListTile(
                                  title: Text(cat),
                                  value: tempSelected.contains(cat),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val!) {
                                        tempSelected.add(cat);
                                      } else {
                                        tempSelected.remove(cat);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx, <String>[]);
                                },
                                child: const Text("Clear All"),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx, tempSelected);
                                },
                                child: const Text("Apply"),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                  if (selected != null) {
                    setState(() {
                      selectedCategories = selected;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('announcements')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final uid = FirebaseAuth.instance.currentUser!.uid;

          List<DocumentSnapshot> filtered = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final docId = doc.id;

            bool matchCategory = selectedCategories.isEmpty || selectedCategories.contains(data['category']);
            bool matchSearch = data['title'].toString().toLowerCase().contains(searchQuery) ||
                data['message'].toString().toLowerCase().contains(searchQuery);
            bool matchUnread = !showUnreadOnly || !readAnnouncements.contains(docId);

            return matchCategory && matchSearch && matchUnread;
          }).toList();

          filtered.sort((a, b) {
            final aTime = (a['timestamp'] as Timestamp).toDate();
            final bTime = (b['timestamp'] as Timestamp).toDate();
            return bTime.compareTo(aTime);
          });

          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final doc = filtered[index];
              final data = doc.data() as Map<String, dynamic>;
              final docId = doc.id;
              final comments = (data['comments'] ?? []) as List<dynamic>;
              final rawReactions = data['reactions'] ?? {};
              final reactions = Map<String, dynamic>.from(rawReactions);
              final currentReaction = reactions[uid];
              final postTime = (data['timestamp'] as Timestamp).toDate();
              final isBookmarked = userBookmarks.contains(docId);
              final category = data['category'] ?? 'General';

              final cardColor = _getCardColorByDate(postTime);
              final emoji = _getCategoryEmoji(category);

              final TextEditingController commentController = TextEditingController();

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Card(
                  margin: const EdgeInsets.all(12),
                  color: cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_expandedAnnouncements.contains(docId)) {
                                _expandedAnnouncements.remove(docId);
                              } else {
                                _expandedAnnouncements.add(docId);
                                _markAsRead(docId);
                              }
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "$emoji ${data['title'] ?? ''}",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: readAnnouncements.contains(docId) ? Colors.black : Colors.black87,
                                  ),
                                ),
                              ),
                              if (!readAnnouncements.contains(docId))
                                const Icon(Icons.brightness_1, color: Colors.blue, size: 10),
                              Icon(_expandedAnnouncements.contains(docId)
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                            ],
                          ),
                        ),
                        if (isBookmarked)
                          const Padding(
                            padding: EdgeInsets.only(top: 4.0),
                            child: Text("🔖 Bookmarked", style: TextStyle(fontSize: 12)),
                          ),
                        if (_expandedAnnouncements.contains(docId)) ...[
                          const SizedBox(height: 6),
                          Text(data['message'] ?? ''),
                          if (data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: GestureDetector(
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      child: Image.network(data['imageUrl']),
                                    ),
                                  );
                                },
                                child: const Text('View Image',
                                    style: TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline)),
                              ),
                            ),
                          if (data['pdfUrl'] != null && (data['pdfUrl'] as String).isNotEmpty)
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
                                      SnackBar(content: Text('Could not open PDF: $e')),
                                    );
                                  }
                                },
                                child: const Row(
                                  children: [
                                    Icon(Icons.picture_as_pdf, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('View PDF',
                                        style: TextStyle(decoration: TextDecoration.underline)),
                                  ],
                                ),
                              ),
                            ),
                          Text('Category: $category'),
                          Text('Time: ${postTime.toLocal().toString().split('.')[0]}'),
                          const Divider(),
                          const Text("Comments:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                                  decoration: const InputDecoration(hintText: 'Add a comment'),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: () {
                                  if (commentController.text.trim().isNotEmpty) {
                                    _addComment(docId, commentController.text.trim());
                                    commentController.clear();
                                  }
                                },
                              )
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text("Reactions:", style: TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: ['👍', '❤️', '🎉', '👏'].map((emoji) {
                              final count = reactions.values.where((v) => v == emoji).length;
                              final isSelected = currentReaction == emoji;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: GestureDetector(
                                  onTap: () => _toggleReaction(docId, isSelected ? null : emoji),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.yellow[100] : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('$emoji $count', style: const TextStyle(fontSize: 18)),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _toggleBookmark(docId),
                                icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                                label: const Text("Bookmark"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple.shade100,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Share.share('${data['title']}\n\n${data['message'] ?? ''}');
                                },
                                icon: const Icon(Icons.share),
                                label: const Text("Share"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade100,
                                ),
                              ),
                            ],
                          ),
                        ]
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
