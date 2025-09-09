import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class SignupPage extends StatefulWidget {
  final String? referralCode;
  
  const SignupPage({Key? key, this.referralCode}) : super(key: key);

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  @override
  Widget build(BuildContext context) {
    // Directly navigate to the signup form page
    return SignupFormPage(
      pickedImage: null,
      referralCode: widget.referralCode,
    );
  }
}

class SignupFormPage extends StatefulWidget {
  final File? pickedImage;
  final String? referralCode;

  const SignupFormPage({Key? key, this.pickedImage, this.referralCode}) : super(key: key);

  @override
  State<SignupFormPage> createState() => _SignupFormPageState();
}

class _SignupFormPageState extends State<SignupFormPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final heightFeetController = TextEditingController();
  final heightInchesController = TextEditingController();
  final weightController = TextEditingController();
  final referralCodeController = TextEditingController();
  
  String? selectedGender;
  String? referrerId;
  
  bool isLoading = false;
  String? errorMessage;
  bool referralCodeValid = false;
  bool checkingReferralCode = false;
  String referrerName = "";

  final Color navyBlue = const Color(0xFF1C2D5E);

  @override
  void initState() {
    super.initState();
    
    // Pre-fill referral code if provided in the URL
    if (widget.referralCode != null) {
      referralCodeController.text = widget.referralCode!;
      _validateReferralCode(widget.referralCode!);
    }
  }

  // Function to calculate BMI (returns a double rounded to 2 decimals)
  double _calculateBMI() {
    final feet = double.tryParse(heightFeetController.text.replaceAll(',', '').trim()) ?? 0.0;
    final inches = double.tryParse(heightInchesController.text.replaceAll(',', '').trim()) ?? 0.0;
    final weightLbs = double.tryParse(weightController.text.replaceAll(',', '').trim()) ?? 0.0;

    // Exact conversion constants
    const footToMeter = 0.3048;      // exact
    const inchToMeter = 0.0254;      // exact
    const lbToKg = 0.45359237;       // more precise

    final heightMeters = (feet * footToMeter) + (inches * inchToMeter);
    final weightKg = weightLbs * lbToKg;

    if (heightMeters <= 0 || weightKg <= 0) return 0.0;

    final bmi = weightKg / (heightMeters * heightMeters);

    // Return rounded to 2 decimals as a double
    return double.parse(bmi.toStringAsFixed(2));
  }

  // Fixed referral code validation method
  Future<void> _validateReferralCode(String code) async {
    if (code.isEmpty) {
      setState(() {
        referralCodeValid = false;
        referrerName = "";
        checkingReferralCode = false;
      });
      return;
    }

    setState(() {
      checkingReferralCode = true;
    });

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('referralCode', isEqualTo: code.trim().toUpperCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final referrerData = querySnapshot.docs.first.data();
        setState(() {
          referralCodeValid = true;
          referrerName = referrerData['name'] ?? "a friend";
          referrerId = querySnapshot.docs.first.id;
          checkingReferralCode = false;
        });
      } else {
        setState(() {
          referralCodeValid = false;
          referrerName = "";
          checkingReferralCode = false;
        });
      }
    } catch (e) {
      print('Error validating referral code: $e');
      setState(() {
        referralCodeValid = false;
        referrerName = "";
        checkingReferralCode = false;
      });
    }
  }

  // Generate a unique referral code for the new user
  String _generateReferralCode(String uid) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.toString().substring(8, 12);
    return 'UITA$random'.toUpperCase();
  }

  // Process referral when a new user signs up with a valid code
  Future<void> _processReferral(String newUserId, String newUserName) async {
    if (!referralCodeValid || referralCodeController.text.isEmpty) return;

    try {
      // Find the referrer
      final querySnapshot = await _firestore
          .collection('users')
          .where('referralCode', isEqualTo: referralCodeController.text.trim().toUpperCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final referrerDoc = querySnapshot.docs.first;
        final referrerId = referrerDoc.id;

        // Create referral record
        await _firestore.collection('referrals').add({
          'referrerId': referrerId,
          'referredUserId': newUserId,
          'referredUserName': newUserName,
          'referralCode': referralCodeController.text.trim().toUpperCase(),
          'status': 'completed',
          'joinedAt': FieldValue.serverTimestamp(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Update referrer's referral count
        await _firestore.collection('users').doc(referrerId).update({
          'referralCount': FieldValue.increment(1),
          'successfulReferrals': FieldValue.arrayUnion([newUserId]),
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Referral applied successfully!')),
        );
      }
    } catch (e) {
      print('Error processing referral: $e');
      // Don't block signup if referral processing fails
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      // Check if email already exists
      final methods = await _auth.fetchSignInMethodsForEmail(email);
      if (methods.isNotEmpty) {
        throw Exception("The email address is already in use by another account.");
      }

      // Create user with email and password
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = userCredential.user;
      if (user != null) {
        // Generate a referral code for the new user
        final String referralCode = _generateReferralCode(user.uid);
        
        // Calculate BMI
        final bmi = _calculateBMI();
        
        // Prepare user data - using the OLD format for compatibility
        final userData = {
          'uid': user.uid,
          'name': nameController.text.trim(),
          'phone': phoneController.text.trim(),
          'email': email,
          'role': 'client', // Added role field from old code
          'gender': selectedGender,
          // Store height and weight in separate fields like the old code
          'height_feet': heightFeetController.text.trim(),
          'height_inches': heightInchesController.text.trim(),
          'weight_lbs': weightController.text.trim(),
          'bmi': bmi, // Store BMI like the old code
          'referralCode': referralCode,
          'created_at': FieldValue.serverTimestamp(),
          'bookmarks': [],
          'readAnnouncements': [],
          'referralCount': 0,
          'successfulReferrals': [],
          // Track if this user was referred by someone
          'referredBy': referralCodeValid ? referrerId : null,
          'referralCodeUsed': referralCodeValid ? referralCodeController.text.trim().toUpperCase() : null,
        };

        // Add user to Firestore
        await _firestore.collection('users').doc(user.uid).set(userData);

        // Process referral if valid code was provided
        if (referralCodeValid && referralCodeController.text.isNotEmpty) {
          await _processReferral(user.uid, nameController.text.trim());
        }

        // Send email verification
        await user.sendEmailVerification();

        // Show success message and navigate to login page
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created! Please verify your email.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Navigate to login page after successful signup
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pushReplacementNamed(context, '/login');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred';
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'The account already exists for that email.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      }
      
      setState(() {
        errorMessage = message;
      });
    } catch (e) {
      final error = e.toString().replaceAll(RegExp(r'\[.*?\]'), '').replaceFirst('Exception: ', '').trim();
      setState(() {
        errorMessage = error;
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildSignupForm(context);
  }

  Widget _buildSignupForm(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 60,
        iconTheme: IconThemeData(color: navyBlue),
        titleTextStyle: TextStyle(
          color: navyBlue,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 20),

              /// LOGO PLACED ABOVE "Create your account"
              Image.asset(
                'assets/images/flex_login/logo.png',
                height: 120,
              ),
              const SizedBox(height: 12),
              Text(
                "Create your account",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 32),

              _buildTextField(
                controller: nameController,
                label: 'Full Name',
                icon: Icons.person_outline,
                validator: (val) => val!.isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: phoneController,
                label: 'Phone',
                icon: Icons.phone,
                maxLength: 10,
                keyboardType: TextInputType.phone,
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter phone number';
                  if (!RegExp(r'^\d{10}$').hasMatch(val)) return 'Phone must be 10 digits';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (val) =>
                    val != null && val.contains('@') ? null : 'Enter a valid email',
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                obscureText: true,
                validator: (val) =>
                    val != null && val.length >= 6 ? null : 'Password must be 6+ characters',
              ),
              const SizedBox(height: 16),

              // Referral Code Field (Optional)
              TextFormField(
                controller: referralCodeController,
                decoration: InputDecoration(
                  labelText: 'Referral Code (Optional)',
                  labelStyle: TextStyle(color: Colors.grey[700]),
                  prefixIcon: Icon(Icons.card_giftcard, color: navyBlue),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: navyBlue),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: navyBlue, width: 2),
                  ),
                  suffixIcon: referralCodeController.text.isNotEmpty
                      ? checkingReferralCode
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              referralCodeValid ? Icons.check_circle : Icons.error,
                              color: referralCodeValid ? Colors.green : Colors.red,
                            )
                      : null,
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    _validateReferralCode(value);
                  } else {
                    setState(() {
                      referralCodeValid = false;
                      referrerName = "";
                    });
                  }
                },
              ),
              if (referralCodeValid && referrerName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    "Referred by $referrerName",
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (!referralCodeValid && referralCodeController.text.isNotEmpty && !checkingReferralCode)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    "Invalid referral code",
                    style: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Gender Selection
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: DropdownButtonFormField<String>(
                  value: selectedGender,
                  decoration: InputDecoration(
                    labelText: 'Gender',
                    labelStyle: TextStyle(color: Colors.grey[700]),
                    prefixIcon: Icon(Icons.person_outline, color: navyBlue),
                    border: InputBorder.none,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedGender = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select gender';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Height input (feet and inches)
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildTextField(
                      controller: heightFeetController,
                      label: 'Height (feet)',
                      icon: Icons.height,
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Enter feet';
                        final feet = int.tryParse(val);
                        if (feet == null || feet < 3 || feet > 7) {
                          return 'Enter valid feet (3-7)';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _buildTextField(
                      controller: heightInchesController,
                      label: 'Height (inches)',
                      icon: Icons.straighten,
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Enter inches';
                        final inches = int.tryParse(val);
                        if (inches == null || inches < 0 || inches > 11) {
                          return 'Enter valid inches (0-11)';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Weight input
              _buildTextField(
                controller: weightController,
                label: 'Weight (lbs)',
                icon: Icons.monitor_weight_outlined,
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter weight';
                  final weight = double.tryParse(val);
                  if (weight == null || weight < 10 || weight > 500) {
                    return 'Enter valid weight (10-500)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _signup,
                    style: ElevatedButton.styleFrom(
                    backgroundColor: navyBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              if (errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE5E5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade400),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Already have an account?",
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text(
                      'Login',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: navyBlue,
                      ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    bool obscureText = false,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      obscureText: obscureText,
      maxLength: maxLength,
      onChanged: (_) {
        if (errorMessage != null) {
          setState(() => errorMessage = null);
        }
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        prefixIcon: Icon(icon, color: navyBlue),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: navyBlue),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: navyBlue, width: 2),
        ),
      ),
    );
  }
}