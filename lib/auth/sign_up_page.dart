import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final Color navyBlue = const Color(0xFF1C2D5E);

  // For storing picked image file
  File? _selectedImage;

  @override
  Widget build(BuildContext context) {
    return _buildIntroPage(context);
  }

  /// First page with full screen image picker, image preview, skip for now, and sign-up button
  Widget _buildIntroPage(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: _selectedImage != null
                    ? BoxDecoration(
                        image: DecorationImage(
                          image: FileImage(_selectedImage!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage("assets/images/signup.jpeg"),
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 8),
              width: double.infinity,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 80,
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedImage = File(picked.path);
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: navyBlue,
                        side: BorderSide(color: navyBlue, width: 1.3),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _selectedImage == null ? "Choose Image" : "Change Image",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: navyBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SignupFormPage(
                              pickedImage: null,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        "Skip for now",
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SignupFormPage(
                              pickedImage: _selectedImage,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: navyBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Sign Up",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SignupFormPage extends StatefulWidget {
  final File? pickedImage;

  const SignupFormPage({super.key, this.pickedImage});

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
  
  String? selectedGender;
  
  bool isLoading = false;
  String? errorMessage;

  final Color navyBlue = const Color(0xFF1C2D5E);

  // Function to calculate BMI
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


  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      final methods = await _auth.fetchSignInMethodsForEmail(email);
      if (methods.isNotEmpty) {
        throw Exception("The email address is already in use by another account.");
      }

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user!.sendEmailVerification();

      // Calculate BMI
      final bmi = _calculateBMI();

      // Store user data including BMI metrics
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'email': email,
        'role': 'client',
        'gender': selectedGender,
        'height_feet': heightFeetController.text.trim(),
        'height_inches': heightInchesController.text.trim(),
        'weight_lbs': weightController.text.trim(),
        //'bmi': bmi.toStringAsFixed(1),
        'bmi': bmi,

        'created_at': FieldValue.serverTimestamp(),
        // Optionally store image URL if you upload to Firebase Storage
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created! Please verify your email.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        await Future.delayed(const Duration(seconds: 2));
        Navigator.pushReplacementNamed(context, '/login');
      }
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

  /// Second page with your original form
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
                    color: const Color(0xFFFFE5E5), // light red
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