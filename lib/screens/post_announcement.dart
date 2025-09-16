import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:clipboard/clipboard.dart';

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
  int _selectedTab = 0; // 0: All, 1: Promotions, 2: Referrals
  DateTime? userSignupDate;
  bool showHowItWorks = false;
  bool showMyReferrals = false;
  // New state variables for referral system
  String? userReferralCode;
  int referralCount = 0;
  int monthsEarned = 0;
  List<Map<String, dynamic>> successfulReferrals = [];
  bool isLoadingReferralData = true;


  Future<void> _fetchUserData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        setState(() {
          userBookmarks = List<String>.from(userData['bookmarks'] ?? []);
          readAnnouncements = Set<String>.from(userData['readAnnouncements'] ?? []);
          
          // Get user signup date
          if (userData['created_at'] != null) {
            userSignupDate = (userData['created_at'] as Timestamp).toDate();
          }
        });
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }
  }

  Future<void> _markAsRead(String announcementId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    setState(() {
      readAnnouncements.add(announcementId);
    });

    try {
      await userRef.set({
        'readAnnouncements': FieldValue.arrayUnion([announcementId])
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> _addComment(String announcementId, String comment) async {
    try {
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
    } catch (e) {
      print('Error adding comment: $e');
    }
  }

  Future<void> _toggleReaction(String announcementId, String? selectedEmoji) async {
    try {
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
    } catch (e) {
      print('Error toggling reaction: $e');
    }
  }

  Future<void> _toggleBookmark(String announcementId) async {
    try {
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
      await _fetchUserData();
    } catch (e) {
      print('Error toggling bookmark: $e');
    }
  }

  Future<void> _shareReferralOld(String referralCode) async {
    final String message = "Join Fitness Hub! 💪\n"
      "Use my referral code: $referralCode\n"
      "New members get a special discount, and I'll earn a free month too! 🎉\n\n"
      "Download the app here: https://play.google.com/store/apps/details?id=com.yourfitnessapp&referrer=referral_code%3D$referralCode";
    final String subject = "Fitness App Referral";
    await Share.share(message, subject: subject);
  }

  // Function to handle promotion link
  Future<void> _openPromotionLink(String? link) async {
    if (link != null && link.isNotEmpty) {
      try {
        await launchUrl(Uri.parse(link), mode: LaunchMode.inAppWebView);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchReferralData(); // New method to fetch referral data

  }
   // New method to fetch referral data
  Future<void> _fetchReferralData() async {
  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    
    // Get user's referral code and referral data
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        setState(() {
          userReferralCode = userData['referralCode'] ?? _generateReferralCode(uid);
          
          // Get referral count from user document
          referralCount = userData['referralCount'] ?? 0;
          
          // Get referredBy information if available
          final referredBy = userData['referredBy'];
          if (referredBy != null) {
            // You could fetch the referrer's name here if needed
          }
        });
      }
      
      // Get successful referrals
      final referralsQuery = await FirebaseFirestore.instance
          .collection('referrals')
          .where('referrerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('joinedAt', descending: true)
          .get();
      
      // Also get the friends' names from the users collection
      List<Map<String, dynamic>> referralsWithNames = [];
      
      for (var doc in referralsQuery.docs) {
        final data = doc.data();
        final referredUserId = data['referredUserId'];
        
        // Get the referred user's name
        if (referredUserId != null) {
          final referredUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(referredUserId)
              .get();
              
          if (referredUserDoc.exists) {
            final referredUserName = referredUserDoc.data()?['name'] ?? 'Friend';
            referralsWithNames.add({
              'friendName': referredUserName,
              'joinedAt': data['joinedAt'] ?? data['timestamp'] ?? Timestamp.now(),
            });
          }
        }
      }
      
      setState(() {
        successfulReferrals = referralsWithNames;
        monthsEarned = (referralCount >= 3) ? 3 : referralCount; // Max 3 months per year
        isLoadingReferralData = false;
      });
    } catch (e) {
      print('Error fetching referral data: $e');
      setState(() {
        isLoadingReferralData = false;
      });
    }
  }


  // Generate a referral code from user ID
  String _generateReferralCode(String uid) {
    return uid.substring(0, 8).toUpperCase();
  }

  // Function to handle referral sharing with dynamic app links
  // Function to handle referral sharing with dynamic app links
  Future<void> _shareReferral() async {
    if (userReferralCode == null) return;
    
    final String message = "Join Fitness Hub! 💪\n"
      "Use my referral code: $userReferralCode\n"
      "New members get a special discount, and I'll earn a free month too! 🎉\n\n"
      "Download the app here: https://play.google.com/store/apps/details?id=com.yourfitnessapp&referrer=referral_code%3D$userReferralCode";
    final String subject = "Fitness App Referral";
    
    await Share.share(message, subject: subject);
  }

  // Function to copy referral link to clipboard
  Future<void> _copyReferralLink() async {
    if (userReferralCode == null) return;
    
    final String referralLink = "https://play.google.com/store/apps/details?id=com.yourfitnessapp&referrer=referral_code%3D$userReferralCode";
    await FlutterClipboard.copy(referralLink);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personalized referral link copied to clipboard!')),
    );
  }

  // Function to share via specific platform with personalized link
  // Function to share via specific platform with personalized link
  Future<void> _shareViaPlatform(String platform) async {
    if (userReferralCode == null) return;
    
    final String message = "Join Fitness Hub! 💪\n"
      "Use my referral code: $userReferralCode\n"
      "New members get a special discount, and I'll earn a free month too! 🎉";
    final String referralLink = "https://play.google.com/store/apps/details?id=com.yourfitnessapp&referrer=referral_code%3D$userReferralCode";
    
    switch (platform) {
      case 'whatsapp':
        final encodedMessage = Uri.encodeComponent('$message\n$referralLink');
        final whatsappUrl = "whatsapp://send?text=$encodedMessage";
        if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
          await launchUrl(Uri.parse(whatsappUrl));
        } else {
          // Fallback to regular share if WhatsApp is not installed
          await Share.share('$message\n$referralLink', subject: "Fitness App Referral");
        }
        break;
      case 'email':
        final String subject = "Fitness App Referral";
        final String body = "$message\n\n$referralLink";
        final String encodedSubject = Uri.encodeComponent(subject);
        final String encodedBody = Uri.encodeComponent(body);
        final emailUrl = "mailto:?subject=$encodedSubject&body=$encodedBody";
        if (await canLaunchUrl(Uri.parse(emailUrl))) {
          await launchUrl(Uri.parse(emailUrl));
        } else {
          // Fallback to regular share
          await Share.share('$message\n$referralLink', subject: subject);
        }
        break;
    }
  }
  String _getCategoryEmoji(String category) {
    switch (category) {
      case 'Important':
        return '⚠';
      case 'Birthday':
        return '🎂';
      case 'Event':
        return '📅';
      case 'Promotion':
        return '🎁';
      case 'Referral':
        return '👥';
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
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search announcements...',
                            filled: true,
                            fillColor: Colors.transparent,
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF1C2D5E)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            hintStyle: TextStyle(color: Colors.grey[600]),
                          ),
                          onChanged: (val) {
                            setState(() {
                              searchQuery = val.toLowerCase();
                            });
                          },
                        ),
                      ),
                      Container(
                        height: 48,
                        width: 1,
                        color: Colors.grey[300],
                      ),
                      SizedBox(
                        width: 56,
                        child: IconButton(
                          icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF1C2D5E)),
                          onPressed: () async {
                            final selected = await showDialog<List<String>>(
                              context: context,
                              builder: (ctx) {
                                final categories = ['Birthday', 'General', 'Event', 'Important', 'Promotion', 'Referral'];
                                List<String> tempSelected = [...selectedCategories];

                                return StatefulBuilder(
                                  builder: (context, setState) {
                                    return AlertDialog(
                                      title: const Text("Select Categories", style: TextStyle(fontWeight: FontWeight.bold)),
                                      content: SizedBox(
                                        width: double.maxFinite,
                                        child: Column(
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
                                              contentPadding: EdgeInsets.zero,
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(ctx, <String>[]);
                                          },
                                          child: const Text("Clear All", style: TextStyle(color: Colors.red)),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(ctx, tempSelected);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF1C2D5E),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: const Text("Apply", style: TextStyle(color: Colors.white)),
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
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Tab selector
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildTabButton(0, 'Announcements', Icons.dashboard),
                _buildTabButton(1, 'Promotions', Icons.local_offer),
                _buildTabButton(2, 'Referrals', Icons.group),
              ],
            ),
          ),
          Expanded(
            child: _selectedTab == 1 
              ? _buildPromotionsTab() 
              : _selectedTab == 2
              ? _buildReferralsTab()
              : _buildAnnouncementsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralsTab() {
    if (isLoadingReferralData) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1C2D5E)),
        ),
      );
    }

    // Function to handle back button
    void handleBack() {
      setState(() {
        showHowItWorks = false;
        showMyReferrals = false;
      });
    }

    // Show referral main content by default
    if (!showHowItWorks && !showMyReferrals) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Combined Referral Header and Code Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2D5E),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    "Refer a Friend",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Share your referral code and both you and your friend will get 1 FREE SESSION!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Benefits section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: "When your friend signs up using your code,\n",
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              TextSpan(
                                text: "BOTH OF YOU GET 1 FREE SESSION!",
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Your referral code section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Your Referral Code",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C2D5E),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2D5E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber, width: 2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                userReferralCode ?? "GENERATING...",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.content_copy, color: Colors.amber, size: 20),
                                onPressed: () {
                                  if (userReferralCode != null) {
                                    FlutterClipboard.copy(userReferralCode!);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Referral code copied to clipboard!')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Share this code with your friends",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Share button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _shareReferral,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: const Color(0xFF1C2D5E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Share This Deal",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
          
            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        showHowItWorks = true;
                        showMyReferrals = false;
                      });
                    },
                    icon: const Icon(Icons.help_outline),
                    label: const Text("How It Works"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C2D5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        showMyReferrals = true;
                        showHowItWorks = false;
                      });
                    },
                    icon: const Icon(Icons.people_outline),
                    label: const Text("View My Referrals"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C2D5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Terms and conditions
            const Center(
              child: Text(
                "Terms and Conditions",
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // Show How It Works section
    else if (showHowItWorks) {
      return Column(
        children: [
          // Back button
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: handleBack,
                ),
                const SizedBox(width: 8),
                const Text(
                  "How It Works",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // How it works content
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(
                          child: Text(
                            "How it works",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C2D5E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Colors.grey),
                        const SizedBox(height: 16),
                        
                        _buildHowItWorksItem("1. Share your unique referral code with friends"),
                        _buildHowItWorksItem("2. Friends sign up using your referral code"),
                        _buildHowItWorksItem("3. The referral link will automatically include your code during signup"),
                        _buildHowItWorksItem("4. After successful signup, both you and your friend get 1 FREE SESSION!"),
                        _buildHowItWorksItem("5. Track your referrals in the 'View My Referrals' section"),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Share button at bottom for How It Works
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _shareReferral,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: const Color(0xFF1C2D5E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Share This Deal",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    
    // Show My Referrals section - ENHANCED UI
    else {
      return Column(
        children: [
          // Enhanced header with gradient
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1C2D5E), Color(0xFF2D3F73)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: handleBack,
                ),
                const SizedBox(width: 8),
                const Text(
                  "My Referrals",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "$referralCount Referrals",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Summary cards in a row
                    Row(
                      children: [
                        // Referral Count Card
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF1C2D5E),
                                  ),
                                  child: const Icon(Icons.group, color: Colors.white, size: 20),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  "Referrals",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$referralCount",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1C2D5E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Free Sessions Earned Card
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.amber,
                                  ),
                                  child: const Icon(Icons.emoji_events, color: Colors.white, size: 20),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  "Free Sessions",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$referralCount",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1C2D5E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Your friends section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Your Friends",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C2D5E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: Colors.grey),
                          const SizedBox(height: 16),
                          
                          if (successfulReferrals.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "No friends have joined yet",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Share your referral link to start earning free sessions!",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: successfulReferrals.map((referral) {
                                final joinDate = (referral['joinedAt'] as Timestamp).toDate();
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [Color(0xFF1C2D5E), Color(0xFF2D3F73)],
                                          ),
                                        ),
                                        child: const Icon(Icons.person, color: Colors.white, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              referral['friendName'] ?? 'Friend',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Joined on ${DateFormat.yMMMd().format(joinDate)}",
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Share button at bottom
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _shareReferral,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C2D5E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 4,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share),
                            SizedBox(width: 8),
                            Text(
                              "Share Referral Link",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildHowItWorksItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareButton(IconData icon, String label, VoidCallback onPressed) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF1C2D5E),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon, size: 28, color: Colors.white),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  
  Widget _buildPromotionsTab() {
    print('Building promotions tab'); // Debug print
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('promotions')
          .orderBy('start', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        print('Promotions snapshot state: ${snapshot.connectionState}'); // Debug print
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1C2D5E)),
                ),
                SizedBox(height: 16),
                Text('Loading promotions...')
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          print('Promotions error: ${snapshot.error}'); // Debug print
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          print('No promotions data'); // Debug print
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_offer,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No promotions available',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check back later for exciting offers!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        print('Found ${snapshot.data!.docs.length} promotions'); // Debug print

        List<DocumentSnapshot> promotions = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;
          
          // Check if promotion is active
          final isActive = data['active'] == true;
          if (!isActive) return false;
          
          // Apply search filter
          bool matchSearch = searchQuery.isEmpty;
          if (!matchSearch && data['title'] != null) {
            matchSearch = data['title'].toString().toLowerCase().contains(searchQuery);
          }
          if (!matchSearch && data['description'] != null) {
            matchSearch = data['description'].toString().toLowerCase().contains(searchQuery);
          }
          
          return matchSearch;
        }).toList();

        print('Filtered promotions: ${promotions.length}'); // Debug print

        if (promotions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No matching promotions found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try different search terms',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: promotions.length,
          itemBuilder: (context, index) {
            final doc = promotions[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildPromotionCard(data, doc.id);
          },
        );
      },
    );
  }

  // Replace the existing _buildAnnouncementsTab() method with this updated version

  Widget _buildAnnouncementsTab() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('announcements')  
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1C2D5E)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No data'));
        }

        final uid = FirebaseAuth.instance.currentUser!.uid;

        List<DocumentSnapshot> filtered = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;
          
          final docId = doc.id;
          
          // Check if timestamp exists
          if (data['timestamp'] == null) return false;
          final announcementTime = (data['timestamp'] as Timestamp).toDate();

          // Filter out announcements before user signup date
          if (userSignupDate != null && announcementTime.isBefore(userSignupDate!)) {
            return false;
          }

          // Check audience restrictions - CRITICAL FIX
          final audience = data['audience'] ?? 'All Users';
          if (audience == 'Specific Clients') {
            final targetClientIds = List<String>.from(data['targetClientIds'] ?? []);
            // Only show if current user is in the target list
            if (!targetClientIds.contains(currentUserId)) {
              return false;
            }
          }

          // Filter by tab selection
          bool matchTab = true;
          if (_selectedTab == 2) { // Referrals tab
            matchTab = data['category'] == 'Referral';
          }

          bool matchCategory = selectedCategories.isEmpty || 
              (data['category'] != null && selectedCategories.contains(data['category']));
          
          bool matchSearch = searchQuery.isEmpty;
          if (!matchSearch) {
            final title = data['title']?.toString()?.toLowerCase() ?? '';
            final message = data['message']?.toString()?.toLowerCase() ?? '';
            matchSearch = title.contains(searchQuery) || message.contains(searchQuery);
          }
          
          bool matchUnread = !showUnreadOnly || !readAnnouncements.contains(docId);

          return matchTab && matchCategory && matchSearch && matchUnread;
        }).toList();


        filtered.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          if (aData['timestamp'] == null || bData['timestamp'] == null) return 0;
          
          final aTime = (aData['timestamp'] as Timestamp).toDate();
          final bTime = (bData['timestamp'] as Timestamp).toDate();
          return bTime.compareTo(aTime);
        });

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.announcement,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No announcements found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try adjusting your filters or check back later',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final doc = filtered[index];
            final data = doc.data() as Map<String, dynamic>;
            final docId = doc.id;
            
            // Special handling for referral posts
            if (data['category'] == 'Referral') {
              return _buildReferralCard(data, docId);
            }
            
            final comments = (data['comments'] ?? []) as List<dynamic>;
            final rawReactions = data['reactions'] ?? {};
            final reactions = Map<String, dynamic>.from(rawReactions);
            final currentReaction = reactions[uid];
            final postTime = (data['timestamp'] as Timestamp).toDate();
            final isBookmarked = userBookmarks.contains(docId);
            final category = data['category'] ?? 'General';

            final isNew = DateTime.now().difference(postTime).inHours <= 24 && 
                        !readAnnouncements.contains(docId);
            final emoji = _getCategoryEmoji(category);

            final TextEditingController commentController = TextEditingController();

            return GestureDetector(
              onTap: () {
                // Mark as read when user taps anywhere on the card
                if (!readAnnouncements.contains(docId)) {
                  _markAsRead(docId);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: readAnnouncements.contains(docId) 
                      ? Colors.grey[100]  // Light grey background for read announcements
                      : Colors.white,     // White background for unread announcements
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header section with gradient
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1C2D5E).withOpacity(0.95),
                            const Color(0xFF2D3F73),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category emoji badge
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title and new indicator
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['title'] ?? 'No Title',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    if (isNew)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'NEW',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Date and time
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.7)),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('MMM dd, yyyy · hh:mm a').format(postTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.8),
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
                    
                    // Message content
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        data['message'] ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    
                    // Category badge - Improved design
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C2D5E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1C2D5E).withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1C2D5E),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    
                    // Media attachments
                    if (data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                        child: GestureDetector(
                          onTap: () async {
                            await showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(20),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    data['imageUrl'],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: Hero(
                            tag: 'image-$docId',
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: NetworkImage(data['imageUrl']),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.black.withOpacity(0.2),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    if (data['pdfUrl'] != null && (data['pdfUrl'] as String).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
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
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF1C2D5E).withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C2D5E).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'View PDF Document',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Color(0xFF1C2D5E),
                                    ),
                                  ),
                                ),
                                Icon(Icons.open_in_new, color: Colors.grey[600], size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    
                    // Reactions section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['👍', '❤', '🎉', '👏'].map((emoji) {
                          final count = reactions.values.where((v) => v == emoji).length;
                          final isSelected = currentReaction == emoji;
                          return GestureDetector(
                            onTap: () {
                              _toggleReaction(docId, isSelected ? null : emoji);
                              // Mark as read when user reacts
                              if (!readAnnouncements.contains(docId)) {
                                _markAsRead(docId);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? const Color(0xFF1C2D5E).withOpacity(0.1) 
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected 
                                      ? const Color(0xFF1C2D5E) 
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(emoji, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 4),
                                  Text(
                                    count > 0 ? count.toString() : '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? const Color(0xFF1C2D5E) : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    
                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Bookmark button - FILLED STYLE
                          ElevatedButton.icon(
                            onPressed: () {
                              _toggleBookmark(docId);
                              // Mark as read when user bookmarks
                              if (!readAnnouncements.contains(docId)) {
                                _markAsRead(docId);
                              }
                            },
                            icon: Icon(
                              isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: Text(
                              isBookmarked ? 'Saved' : 'Save',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isBookmarked ? Colors.green : const Color(0xFF1C2D5E),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          
                          // Share button - FILLED WITH BLACK BACKGROUND AND WHITE TEXT
                          ElevatedButton.icon(
                            onPressed: () {
                              Share.share('${data['title']}\n\n${data['message'] ?? ''}');
                              // Mark as read when user shares
                              if (!readAnnouncements.contains(docId)) {
                                _markAsRead(docId);
                              }
                            },
                            icon: const Icon(Icons.share, size: 16, color: Colors.white),
                            label: const Text(
                              'Share',
                              style: TextStyle(
                                fontSize: 13, 
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1C2D5E),
                              foregroundColor: Colors.white, // Text and icon color
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Comments section
                    if (comments.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Comments",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Color(0xFF1C2D5E),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...comments.map((comment) {
                              final commentTime = (comment['timestamp'] as Timestamp).toDate();
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          comment['username'] ?? 'Anonymous',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          DateFormat('MMM dd, yyyy').format(commentTime),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      comment['text'] ?? '', 
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    
                    // Add comment section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: comments.isEmpty 
                            ? const BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              )
                            : BorderRadius.circular(0),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentController,
                              decoration: InputDecoration(
                                hintText: 'Add a comment...',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                hintStyle: const TextStyle(fontSize: 14),
                              ),
                              onTap: () {
                                // Mark as read when user taps on comment field
                                if (!readAnnouncements.contains(docId)) {
                                  _markAsRead(docId);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF1C2D5E),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white, size: 20),
                              onPressed: () {
                                if (commentController.text.trim().isNotEmpty) {
                                  _addComment(docId, commentController.text.trim());
                                  commentController.clear();
                                  FocusScope.of(context).unfocus();
                                  // Mark as read when user comments
                                  if (!readAnnouncements.contains(docId)) {
                                    _markAsRead(docId);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
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
  Widget _buildTabButton(int index, String title, IconData icon) {
    return Expanded(
      child: Material(
        color: _selectedTab == index ? const Color(0xFF1C2D5E).withOpacity(0.1) : Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedTab = index;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: _selectedTab == index ? const Color(0xFF1C2D5E) : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _selectedTab == index ? FontWeight.bold : FontWeight.normal,
                    color: _selectedTab == index ? const Color(0xFF1C2D5E) : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromotionCard(Map<String, dynamic> data, String docId) {
    final isBookmarked = userBookmarks.contains(docId);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.orange[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_offer,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['title'] ?? 'No Title',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        Text(
                          data['offer'] ?? 'Special Offer',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C2D5E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data['description'] ?? 'No description available',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (data['code'] != null && data['code'].toString().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.confirmation_number, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Code: ${data['code']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (data['start'] != null && data['end'] != null) ...[
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Valid: ${DateFormat.yMMMd().format((data['start'] as Timestamp).toDate())} - ${DateFormat.yMMMd().format((data['end'] as Timestamp).toDate())}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _toggleBookmark(docId),
                    icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                    label: const Text("Bookmark"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple.shade100,
                      foregroundColor: Colors.deepPurple,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openPromotionLink(data['link']),
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text("Get Offer"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C2D5E),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> data, String docId) {
    final postTime = (data['timestamp'] as Timestamp).toDate();
    final isBookmarked = userBookmarks.contains(docId);
    final cardColor = _getCardColorByDate(postTime);
    final emoji = _getCategoryEmoji('Referral');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
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
                
                // Referral-specific content
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Referral Bonus:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(data['bonusDetails'] ?? 'Earn points for each friend who joins!'),
                      const SizedBox(height: 8),
                      if (data['referralCode'] != null)
                        Text("Your code: ${data['referralCode']}"),
                    ],
                  ),
                ),
                
                const Text('Category: Referral'),
                Text('Time: ${postTime.toLocal().toString().split('.')[0]}'),
                const Divider(),
                
                // Action buttons for referral
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
                        _shareReferralOld(data['referralCode'] ?? '');
                      },
                      icon: const Icon(Icons.share),
                      label: const Text("Share Referral"),
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
  }
}