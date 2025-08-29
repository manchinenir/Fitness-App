import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const Color kPrimary = Color(0xFF1C2D5E); // Navy blue you shared

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  File? _imageFile;
  String? profileName;
  String? email;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (snapshot.exists) {
        setState(() {
          profileName = snapshot.data()?['name'] ?? 'Your Name';
          email = snapshot.data()?['email'] ?? 'your@email.com';
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedImage =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedImage != null) {
      setState(() {
        _imageFile = File(pickedImage.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 4,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundImage: _imageFile != null
                      ? FileImage(_imageFile!)
                      : const AssetImage('assets/profile.jpg') as ImageProvider,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(1, 1))
                        ],
                      ),
                      child: const Icon(Icons.edit, size: 20, color: kPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            profileName ?? '',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            email ?? '',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView(
              children: [
                _buildOption(
                  context,
                  icon: Icons.info_outline,
                  label: 'Personal Information',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PersonalInfoPage()),
                    );
                  },
                ),
                _buildOption(
                  context,
                  icon: Icons.history,
                  label: 'Session History',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SessionHistoryPage()),
                    );
                  },
                ),
                _buildOption(
                  context,
                  icon: Icons.payment,
                  label: 'Payment History',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PaymentHistoryPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: CircleAvatar(
            backgroundColor: kPrimary.withOpacity(0.12),
            child: Icon(icon, color: kPrimary),
          ),
          title: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: onTap,
        ),
      ),
    );
  }
}

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  String? name;
  String? email;
  String? phone;
  String? imageUrl;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          name = data['name'];
          email = data['email'];
          phone = data['phone'];
          imageUrl = data['profileImage'];
          nameController.text = name ?? '';
          phoneController.text = phone ?? '';
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );

      setState(() {
        _isEditing = false;
        name = nameController.text.trim();
        phone = phoneController.text.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title:
            const Text('Personal Information', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: name == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null)
                      Center(
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: NetworkImage(imageUrl!),
                        ),
                      ),
                    const SizedBox(height: 20),
                    _isEditing
                        ? TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              border: OutlineInputBorder(),
                            ),
                          )
                        : Text(
                            'Name: ${name ?? ''}',
                            style: const TextStyle(fontSize: 16),
                          ),
                    const SizedBox(height: 16),
                    Text(
                      'Email: ${email ?? ''}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    _isEditing
                        ? TextField(
                            controller: phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          )
                        : Text(
                            'Phone: ${phone ?? ''}',
                            style: const TextStyle(fontSize: 16),
                          ),
                    const SizedBox(height: 20),
                    Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                        ),
                        onPressed: () {
                          if (_isEditing) {
                            _updateProfile();
                          } else {
                            setState(() {
                              _isEditing = true;
                            });
                          }
                        },
                        child: Text(
                          _isEditing ? 'Save Changes' : 'Edit Profile',
                          style: const TextStyle(color: Colors.white),
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

class SessionHistoryPage extends StatelessWidget {
  const SessionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Session History', style: TextStyle(color: Colors.white)),
      ),
      body: const Center(
        child: Text(
          'Your session history will appear here.',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class PaymentHistoryPage extends StatelessWidget {
  const PaymentHistoryPage({super.key});

  // Helper method to create unique key from title, subtitle, and price
  String _createPlanKey(String title, String subtitle, double price) {
    final key = '$title|$subtitle|${price.toStringAsFixed(2)}';
    return key;
  }

  // Helper method to group payment data by plan title, subtitle, and price
  Map<String, Map<String, dynamic>> _groupPaymentsByPlan(
      List<QueryDocumentSnapshot> docs) {
    final Map<String, Map<String, dynamic>> groupedData = {};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;

      final title = data['planTitle'] ?? 'No Title';
      final subtitle = data['planSubtitle'] ?? '';
      final price = (data['price'] as num?)?.toDouble() ?? 0.0;
      final purchaseDate = data['purchaseDate'] is Timestamp
          ? (data['purchaseDate'] as Timestamp).toDate()
          : DateTime.now();

      final planKey = _createPlanKey(title, subtitle, price);

      if (groupedData.containsKey(planKey)) {
        groupedData[planKey]!['totalRevenue'] += price;
        groupedData[planKey]!['count'] += 1;
        if (purchaseDate.isAfter(groupedData[planKey]!['latestDate'])) {
          groupedData[planKey]!['latestDate'] = purchaseDate;
        }
      } else {
        groupedData[planKey] = {
          'title': title,
          'subtitle': subtitle,
          'price': price,
          'totalRevenue': price,
          'count': 1,
          'latestDate': purchaseDate,
        };
      }
    }

    return groupedData;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Payment History', style: TextStyle(color: Colors.white)),
      ),
      body: user == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('purchased_plans')
                  .orderBy('purchaseDate', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No payment history found.'));
                }

                final groupedPayments = _groupPaymentsByPlan(docs);
                final groupedEntries = groupedPayments.entries.toList();

                final totalRevenue = groupedPayments.values.fold<double>(
                  0.0,
                  (sum, group) => sum + group['totalRevenue'],
                );
                final totalPurchases = docs.length;

                return Column(
                  children: [
                    // Summary Card
                    Container(
                      margin: const EdgeInsets.all(16.0),
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Payment Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    '$totalPurchases',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const Text('Total Purchases'),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    '\$${totalRevenue.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const Text('Total Revenue'),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Plans List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: groupedEntries.length,
                        itemBuilder: (context, index) {
                          final entry = groupedEntries[index];
                          final groupData = entry.value;

                          final title = groupData['title'];
                          final subtitle = groupData['subtitle'];
                          final price = groupData['price'];
                          final totalRevenue = groupData['totalRevenue'];
                          final count = groupData['count'];
                          final latestDate = groupData['latestDate'] as DateTime;
                          final formattedDate =
                              DateFormat('dd MMM yyyy').format(latestDate);

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 3,
                              child: ExpansionTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.payments,
                                    color: kPrimary,
                                    size: 24,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Purchased $count time${count > 1 ? 's' : ''} • Latest: $formattedDate',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '\$${totalRevenue.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Revenue Details:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Individual Price:'),
                                            Text(
                                              '\$${price.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: kPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Total Revenue:'),
                                            Text(
                                              '\$${totalRevenue.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Purchase Count:'),
                                            Text(
                                              '$count',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
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
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
