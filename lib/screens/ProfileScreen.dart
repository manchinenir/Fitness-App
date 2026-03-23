import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'payment_history_page.dart';
import 'settings_client.dart';

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
  String? imageUrl;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _setupProfileImageListener();
  }
  
  void _setupProfileImageListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          setState(() {
            imageUrl = snapshot.data()?['profileImage'];
          });
        }
      });
    }
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
          imageUrl = snapshot.data()?['profileImage'];
        });
      }
    }
  }

  Future<String?> _uploadProfileImage() async {
    if (_imageFile == null) return null;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');
      
      final uploadTask = ref.putFile(_imageFile!);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profileImage': downloadUrl});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile image updated successfully!')),
        );
      }
      
      return downloadUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
      return null;
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
      
      final downloadUrl = await _uploadProfileImage();
      
      if (downloadUrl != null) {
        setState(() {
          imageUrl = downloadUrl;
        });
      }
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
                      : (imageUrl != null 
                          ? NetworkImage(imageUrl!) 
                          : const AssetImage('assets/profile.jpg')) as ImageProvider,
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
                _buildOption(
                  context,
                  icon: Icons.trending_up,
                  label: 'Progress Tracking',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ProgressTrackingPage()),
                    );
                  },
                ),
                _buildOption(
                  context,
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsClient(),
                      ),
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
  String? gender;
  String? heightFeet;
  String? heightInches;
  String? weight;
  String? bmi;
  String? imageUrl;
  File? _imageFile;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController heightFeetController = TextEditingController();
  final TextEditingController heightInchesController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController genderController = TextEditingController();

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _setupProfileImageListener();
  }

  void _setupProfileImageListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          setState(() {
            imageUrl = snapshot.data()?['profileImage'];
          });
        }
      });
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
      
      final downloadUrl = await _uploadProfileImage();
      
      if (downloadUrl != null) {
        setState(() {
          imageUrl = downloadUrl;
        });
      }
    }
  }

  Future<String?> _uploadProfileImage() async {
    if (_imageFile == null) return null;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');
      
      final uploadTask = ref.putFile(_imageFile!);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profileImage': downloadUrl});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile image updated successfully!')),
        );
      }
      
      return downloadUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
      return null;
    }
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
          gender = data['gender'] ?? 'Not specified';
          heightFeet = data['height_feet'] ?? '';
          heightInches = data['height_inches'] ?? '';
          weight = data['weight_lbs'] ?? '';
          bmi = data['bmi'] ?? '0.0';
          imageUrl = data['profileImage'];
          
          nameController.text = name ?? '';
          phoneController.text = phone ?? '';
          heightFeetController.text = heightFeet ?? '';
          heightInchesController.text = heightInches ?? '';
          weightController.text = weight ?? '';
          genderController.text = gender ?? '';
        });
      }
    }
  }

  double _calculateBMI() {
    final feet = double.tryParse(heightFeetController.text) ?? 0;
    final inches = double.tryParse(heightInchesController.text) ?? 0;
    final weight = double.tryParse(weightController.text) ?? 0;
    
    final heightInMeters = (feet * 0.3048) + (inches * 0.0254);
    final weightInKg = weight * 0.453592;
    
    if (heightInMeters > 0) {
      return weightInKg / (heightInMeters * heightInMeters);
    }
    
    return 0;
  }

  Future<void> _updateProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final newBMI = _calculateBMI();
      
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'gender': genderController.text.trim(),
        'height_feet': heightFeetController.text.trim(),
        'height_inches': heightInchesController.text.trim(),
        'weight_lbs': weightController.text.trim(),
        'bmi': newBMI.toStringAsFixed(2),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );

      setState(() {
        _isEditing = false;
        name = nameController.text.trim();
        phone = phoneController.text.trim();
        gender = genderController.text.trim();
        heightFeet = heightFeetController.text.trim();
        heightInches = heightInchesController.text.trim();
        weight = weightController.text.trim();
        bmi = newBMI.toStringAsFixed(2);
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
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
        ],
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
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: kPrimary.withOpacity(0.2),
                                    width: 3,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 48,
                                  backgroundImage: _imageFile != null
                                      ? FileImage(_imageFile!)
                                      : (imageUrl != null 
                                          ? NetworkImage(imageUrl!) 
                                          : const AssetImage('assets/profile.jpg')) as ImageProvider,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: kPrimary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Personal Details',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            _buildInfoRow(
                              label: 'Full Name',
                              value: name ?? '',
                              isEditing: _isEditing,
                              controller: nameController,
                              keyboardType: TextInputType.text,
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 16),
                            
                            _buildReadOnlyInfoRow(
                              label: 'Email Address',
                              value: email ?? '',
                              icon: Icons.email_outlined,
                            ),
                            const SizedBox(height: 16),
                            
                            _buildInfoRow(
                              label: 'Phone Number',
                              value: phone ?? '',
                              isEditing: _isEditing,
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              icon: Icons.phone_outlined,
                            ),
                            const SizedBox(height: 16),
                            
                            _buildInfoRow(
                              label: 'Gender',
                              value: gender ?? 'Not specified',
                              isEditing: _isEditing,
                              controller: genderController,
                              keyboardType: TextInputType.text,
                              icon: Icons.transgender,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Physical Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildInfoRow(
                                    label: 'Height (ft)',
                                    value: heightFeet ?? '',
                                    isEditing: _isEditing,
                                    controller: heightFeetController,
                                    keyboardType: TextInputType.number,
                                    icon: Icons.straighten,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 5,
                                  child: _buildInfoRow(
                                    label: 'Height (in)',
                                    value: heightInches ?? '',
                                    isEditing: _isEditing,
                                    controller: heightInchesController,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            _buildInfoRow(
                              label: 'Weight (lbs)',
                              value: weight ?? '',
                              isEditing: _isEditing,
                              controller: weightController,
                              keyboardType: TextInputType.number,
                              icon: Icons.monitor_weight_outlined,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Health Metrics',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    kPrimary.withOpacity(0.8),
                                    kPrimary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'Body Mass Index (BMI)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    bmi ?? '0.0',
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getBMICategory(double.tryParse(bmi ?? '0') ?? 0),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    
    const SizedBox(height: 24),
    
    Row(
      children: [
        if (_isEditing)
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: kPrimary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  nameController.text = name ?? '';
                  phoneController.text = phone ?? '';
                  genderController.text = gender ?? '';
                  heightFeetController.text = heightFeet ?? '';
                  heightInchesController.text = heightInches ?? '';
                  weightController.text = weight ?? '';
                });
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (_isEditing) const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 20),
  ],
),
),
),
);
  }

  String _getBMICategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal weight';
    if (bmi < 30) return 'Overweight';
    return 'Obesity';
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required bool isEditing,
    required TextEditingController controller,
    required TextInputType keyboardType,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 18,
                color: Colors.grey.shade600,
              ),
            if (icon != null) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        isEditing
            ? TextFormField(
                controller: controller,
                keyboardType: keyboardType,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kPrimary, width: 1.5),
                  ),
                ),
              )
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  value.isNotEmpty ? value : 'Not specified',
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildReadOnlyInfoRow({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 18,
                color: Colors.grey.shade600,
              ),
            if (icon != null) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class ProgressTrackingPage extends StatefulWidget {
  const ProgressTrackingPage({super.key});

  @override
  State<ProgressTrackingPage> createState() => _ProgressTrackingPageState();
}

class _ProgressTrackingPageState extends State<ProgressTrackingPage> {
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _progressEntries = [];
  Map<String, dynamic>? _editingEntry;
  File? _progressPhotoFile;
  String? _progressPhotoUrl;
  bool _showPhotoContainer = false; // New flag to control photo container visibility
  bool _removeExistingPhoto = false; // ✅ ADD THIS LINE


  @override
  void initState() {
    super.initState();
    _loadProgressData();
    _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedDate);
  }

  Future<void> _loadProgressData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('progress')
          .orderBy('date', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _progressEntries = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'weight': data['weight'],
              'date': (data['date'] as Timestamp).toDate(),
              'photoUrl': data['photoUrl'],
              'notes': data['notes'] ?? '',
            };
          }).toList();
        });
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<String?> _uploadProgressPhoto() async {
    if (_progressPhotoFile == null) return null;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref()
          .child('progress_photos')
          .child(user.uid)
          .child('$timestamp.jpg');
      
      final uploadTask = ref.putFile(_progressPhotoFile!);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _pickProgressPhoto() async {
    final picker = ImagePicker();
    final pickedImage =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedImage != null) {
      setState(() {
        _progressPhotoFile = File(pickedImage.path);
        _showPhotoContainer = true; // Show container when photo is picked
      });
    }
  }

  Future<void> _saveProgressEntry() async {
    if (_weightController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your weight')),
      );
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final existingEntry = _progressEntries.firstWhere(
      (entry) => DateFormat('yyyy-MM-dd').format(entry['date']) == dateStr,
      orElse: () => {},
    );

    if (existingEntry.isNotEmpty && _editingEntry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an entry for this date')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        String? photoUrl;
        if (_progressPhotoFile != null) {
          photoUrl = await _uploadProgressPhoto();
        }

        if (_editingEntry != null) {
          final updateData = {
            'weight': double.parse(_weightController.text),
            'date': Timestamp.fromDate(_selectedDate),
          };

          if (_removeExistingPhoto) {
            updateData['photoUrl'] = FieldValue.delete(); // 🔥 REMOVE FROM FIRESTORE
          } else if (photoUrl != null) {
            updateData['photoUrl'] = photoUrl;
          }

          
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('progress')
              .doc(_editingEntry!['id'])
              .update(updateData);
        } else {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('progress')
              .add({
            'weight': double.parse(_weightController.text),
            'date': Timestamp.fromDate(_selectedDate),
            'photoUrl': photoUrl,
            'createdAt': Timestamp.now(),
          });
        }

        _weightController.clear();
        setState(() {
          _selectedDate = DateTime.now();
          _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedDate);
          _editingEntry = null;
          _progressPhotoFile = null;
          _progressPhotoUrl = null;
          _removeExistingPhoto = false;
          _showPhotoContainer = false; // Hide photo container after saving
        });

        await _loadProgressData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_editingEntry != null 
            ? 'Progress updated successfully!' 
            : 'Progress added successfully!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteProgressEntry(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('progress')
          .doc(id)
          .delete();

      await _loadProgressData();
    }
  }

  void _editProgressEntry(Map<String, dynamic> entry) {
    setState(() {
      _editingEntry = entry;
      _weightController.text = entry['weight'].toString();
      _selectedDate = entry['date'];
      _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedDate);
      _progressPhotoUrl = entry['photoUrl'];
      _progressPhotoFile = null;
      _showPhotoContainer = entry['photoUrl'] != null; // Show container if editing entry has photo
      _removeExistingPhoto = false; // ✅ IMPORTANT

    });
  }

  void _cancelEdit() {
    setState(() {
      _editingEntry = null;
      _weightController.clear();
      _selectedDate = DateTime.now();
      _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedDate);
      _progressPhotoFile = null;
      _progressPhotoUrl = null;
      _showPhotoContainer = false; // Hide photo container when canceling
      _removeExistingPhoto = false;

    });
  }

  void _viewProgressPhoto(String? photoUrl) {
    if (photoUrl != null) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    photoUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: double.infinity,
                        height: 400,
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: double.infinity,
                        height: 400,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.error, color: Colors.red, size: 50),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  String _getMotivationalMessage(double difference) {
    if (difference < -10) return '💪 Amazing transformation! You\'re crushing your goals!';
    if (difference < -5) return '🔥 Outstanding progress! Keep up the great work!';
    if (difference < -2) return '👍 Great job! The results are showing!';
    if (difference < 0) return '👏 Nice! Every pound counts!';
    if (difference == 0) return '💯 Maintaining is progress too! Stay consistent!';
    if (difference < 2) return '🌟 Small fluctuations are normal. Stay focused!';
    if (difference < 5) return '🏋 Don\'t get discouraged. You can get back on track!';
    return '🏋 Time to refocus! You\'ve got this!';
  }

  IconData _getTrendIcon(double difference) {
    if (difference < 0) return Icons.trending_down;
    if (difference > 0) return Icons.trending_up;
    return Icons.trending_flat;
  }

  Color _getTrendColor(double difference) {
    if (difference < 0) return Colors.green;
    if (difference > 0) return Colors.red;
    return Colors.grey;
  }

  // Create a custom dashed border
  BoxDecoration _createDashedBorderDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      border: Border.all(
        color: Colors.grey.shade300,
        width: 1.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chartData = _progressEntries.toList()
      ..sort((a, b) => a['date'].compareTo(b['date']));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Progress Tracking', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Add Progress Form
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      _editingEntry != null ? 'Edit Progress' : 'Add New Progress',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Weight Input
                    TextFormField(
                      controller: _weightController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Weight (lbs)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.monitor_weight),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Date Input with Upload Button
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _dateController,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Date',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefixIcon: const Icon(Icons.calendar_today),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_month),
                                onPressed: () => _selectDate(context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Upload Image Button
                        SizedBox(
                          width: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              padding: const EdgeInsets.all(12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _showPhotoContainer = !_showPhotoContainer;
                              });
                            },

                            child: const Icon(
                              Icons.add_a_photo,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Progress Photo Container (Conditionally Visible)
                    if (_showPhotoContainer)
                      Card(
                        color: Colors.grey.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.photo_camera, color: kPrimary, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Progress Photo (Optional)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: kPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Optional',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: kPrimary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Track your visual progress by adding a photo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              // Photo Preview or Placeholder
                              if (_progressPhotoFile != null || _progressPhotoUrl != null)
                                Container(
                                  height: 150,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.white,
                                  ),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: _progressPhotoFile != null
                                            ? Image.file(
                                                _progressPhotoFile!,
                                                width: double.infinity,
                                                height: double.infinity,
                                                fit: BoxFit.cover,
                                              )
                                            : _progressPhotoUrl != null
                                                ? Image.network(
                                                    _progressPhotoUrl!,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    fit: BoxFit.cover,
                                                    loadingBuilder: (context, child, loadingProgress) {
                                                      if (loadingProgress == null) return child;
                                                      return Center(
                                                        child: CircularProgressIndicator(
                                                          value: loadingProgress.expectedTotalBytes != null
                                                              ? loadingProgress.cumulativeBytesLoaded /
                                                                  loadingProgress.expectedTotalBytes!
                                                              : null,
                                                        ),
                                                      );
                                                    },
                                                  )
                                                : Container(),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: CircleAvatar(
                                          backgroundColor: Colors.black54,
                                          radius: 16,
                                          child: IconButton(
                                            icon: const Icon(Icons.close, size: 16),
                                            color: Colors.white,
                                            onPressed: () {
                                              setState(() {
                                                _progressPhotoFile = null;
                                                _progressPhotoUrl = null;
                                                _removeExistingPhoto = true; // MARK FOR REMOVAL
                                              });
                                            },

                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: _pickProgressPhoto,
                                  child: Container(
                                    height: 120,
                                    decoration: _createDashedBorderDecoration(),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_a_photo,
                                          size: 40,
                                          color: kPrimary.withOpacity(0.6),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Add Progress Photo',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: kPrimary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Optional - Track your visual transformation',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              
                              const SizedBox(height: 12),
                              
                              // Photo Action Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.camera_alt, size: 16),
                                      label: const Text('Take Photo'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: kPrimary,
                                        side: BorderSide(color: kPrimary),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final picker = ImagePicker();
                                        final pickedImage = await picker.pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 85,
                                        );
                                        if (pickedImage != null) {
                                          setState(() {
                                            _progressPhotoFile = File(pickedImage.path);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.photo_library, size: 16),
                                      label: const Text('From Gallery'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: kPrimary,
                                        side: BorderSide(color: kPrimary),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: _pickProgressPhoto,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    
                    // Action Buttons
                    Row(
                      children: [
                        if (_editingEntry != null)
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: kPrimary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _cancelEdit,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: kPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (_editingEntry != null) const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _saveProgressEntry,
                            child: Text(
                              _editingEntry != null ? 'Update' : 'Add Progress',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Progress Chart
            if (_progressEntries.length > 1) 
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weight Progress',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: kPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 200,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              horizontalInterval: 5,
                              verticalInterval: 1,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.grey.shade200,
                                  strokeWidth: 1,
                                );
                              },
                              getDrawingVerticalLine: (value) {
                                return FlLine(
                                  color: Colors.grey.shade100,
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: 1,
                                  getTitlesWidget: (value, meta) {
                                    if (value >= 0 && value < chartData.length) {
                                      final date = chartData[value.toInt()]['date'];
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          _getFormattedDateLabel(date, chartData, value.toInt()),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color.fromARGB(255, 58, 58, 58),
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        )
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toInt().toString(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color.fromARGB(255, 58, 58, 58),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                            ),
                            minX: 0,
                            maxX: chartData.isNotEmpty ? chartData.length - 1 : 0,
                            minY: chartData.isNotEmpty 
                                ? (chartData.map((e) => e['weight']).reduce((a, b) => a < b ? a : b) - 5).floorToDouble()
                                : 0,
                            maxY: chartData.isNotEmpty 
                                ? (chartData.map((e) => e['weight']).reduce((a, b) => a > b ? a : b) + 5).ceilToDouble()
                                : 100,
                            lineBarsData: [
                              LineChartBarData(
                                spots: chartData.asMap().entries.map((entry) {
                                  return FlSpot(
                                    entry.key.toDouble(),
                                    entry.value['weight'],
                                  );
                                }).toList(),
                                isCurved: true,
                                color: kPrimary,
                                barWidth: 3,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: kPrimary,
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      kPrimary.withOpacity(0.3),
                                      kPrimary.withOpacity(0.1),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Weight (lbs)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color.fromARGB(255, 39, 38, 38),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            
            if (_progressEntries.length > 1) const SizedBox(height: 16),
            
            // Progress List Header
            if (_progressEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Progress History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.photo, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${_progressEntries.where((entry) => entry['photoUrl'] != null).length}/${_progressEntries.length}',
                          style: const TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            
            // Progress List
            if (_progressEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Text(
                  'No progress entries yet. Start tracking your progress!',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _progressEntries.length,
                itemBuilder: (context, index) {
                  final entry = _progressEntries[index];
                  final weight = entry['weight'];
                  final date = entry['date'] as DateTime;
                  final formattedDate = DateFormat('MMM dd, yyyy').format(date);
                  final photoUrl = entry['photoUrl'];
                  
                  double difference = 0;
                  String differenceText = '';
                  String motivationalMessage = '';
                  
                  if (index < _progressEntries.length - 1) {
                    final prevWeight = _progressEntries[index + 1]['weight'];
                    difference = weight - prevWeight;
                    differenceText = difference.abs().toStringAsFixed(1);
                    motivationalMessage = _getMotivationalMessage(difference);
                    
                    if (difference > 0) {
                      differenceText = '+$differenceText lbs';
                    } else if (difference < 0) {
                      differenceText = '-$differenceText lbs';
                    } else {
                      differenceText = 'No change';
                    }
                  }
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: kPrimary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getTrendIcon(difference),
                              color: _getTrendColor(difference),
                              size: 24,
                            ),
                          ),
                          title: Text(
                            '$weight lbs',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedDate,
                                style: const TextStyle(fontSize: 14),
                              ),
                              if (difference != 0 && index < _progressEntries.length - 1)
                                Text(
                                  motivationalMessage,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: const Color.fromARGB(255, 46, 46, 46),
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (photoUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.photo, color: Colors.blue),
                                  onPressed: () => _viewProgressPhoto(photoUrl),
                                  tooltip: 'View Progress Photo',
                                ),
                              if (difference != 0) 
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      differenceText,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _getTrendColor(difference),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Icon(
                                      _getTrendIcon(difference),
                                      size: 16,
                                      color: _getTrendColor(difference),
                                    ),
                                  ],
                                ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                itemBuilder: (BuildContext context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editProgressEntry(entry);
                                  } else if (value == 'delete') {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: const Text('Delete Entry'),
                                          content: const Text(
                                              'Are you sure you want to delete this progress entry?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                _deleteProgressEntry(entry['id']);
                                                Navigator.of(context).pop();
                                              },
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(color: Colors.red),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        
                        // Photo Preview in List
                        if (photoUrl != null)
                          GestureDetector(
                            onTap: () => _viewProgressPhoto(photoUrl),
                            child: Container(
                              height: 120,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey.shade50,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [
                                    Image.network(
                                      photoUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded /
                                                    loadingProgress.expectedTotalBytes!
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.photo, size: 12, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text(
                                              'View Photo',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
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
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getFormattedDateLabel(DateTime date, List<Map<String, dynamic>> chartData, int index) {
    if (chartData.length <= 7) {
      return DateFormat('MMM d').format(date);
    } else if (chartData.length <= 14) {
      if (index == 0 || index == chartData.length - 1 || index % 3 == 0) {
        return DateFormat('MMM d').format(date);
      } else {
        return DateFormat('d').format(date);
      }
    } else {
      if (index == 0 || 
          (index > 0 && chartData[index-1]['date'].month != date.month)) {
        return '${DateFormat('MMM').format(date)}\n${date.day}';
      } else {
        return date.day.toString();
      }
    }
  }
}