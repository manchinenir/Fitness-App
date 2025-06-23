import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BookingConfirmationPage extends StatefulWidget {
  final DateTime selectedDate;
  final String selectedTime;
  final String trainerName;
  final int slotCapacity;

  const BookingConfirmationPage({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.trainerName,
    required this.slotCapacity,
  });

  @override
  State<BookingConfirmationPage> createState() => _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _alreadyBooked = false;
  bool _showSuccess = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> triggerNotification(String action, String name, String email, String phone) async {
    final callable = FirebaseFunctions.instance.httpsCallable('notifyTrainerClient');
    await callable.call({
      'action': action,
      'date': DateFormat('yyyy-MM-dd').format(widget.selectedDate),
      'time': widget.selectedTime,
      'userName': name,
      'email': email,
      'phone': phone,
      'trainerName': widget.trainerName,
    });
  }

  Future<void> bookSlot() async {
    setState(() => _loading = true);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final userName = userDoc['name'] ?? 'Client';
    final userEmail = userDoc['email'] ?? '';
    final userPhone = userDoc['phone'] ?? '';

    final docId = "${DateFormat('yyyy-MM-dd').format(widget.selectedDate)}|${widget.selectedTime}";
    final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
    final doc = await docRef.get();

    if (!doc.exists) {
      await docRef.set({
        'date': widget.selectedDate,
        'time': widget.selectedTime,
        'booked': 1,
        'booked_by': [currentUser.uid],
        'booked_names': [userName],
        'capacity': widget.slotCapacity,
        'trainer_name': widget.trainerName,
      });
    } else {
      final data = doc.data()!;
      List bookedBy = data['booked_by'] ?? [];
      List bookedNames = data['booked_names'] ?? [];

      if (bookedBy.contains(currentUser.uid)) {
        setState(() {
          _alreadyBooked = true;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already booked this slot.')),
        );
        return;
      } else if (bookedBy.length >= widget.slotCapacity) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Slot is full.')),
        );
        return;
      }

      bookedBy.add(currentUser.uid);
      bookedNames.add(userName);
      await docRef.update({
        'booked': bookedBy.length,
        'booked_by': bookedBy,
        'booked_names': bookedNames,
      });
    }

    try {
      await triggerNotification('book', userName, userEmail, userPhone);
    } catch (e) {
      debugPrint('Notification Error: $e');
    }

    setState(() {
      _loading = false;
      _showSuccess = true;
    });
    await _controller.forward();
  }

  Future<void> cancelBooking() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final docId = "${DateFormat('yyyy-MM-dd').format(widget.selectedDate)}|${widget.selectedTime}";
    final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
    final doc = await docRef.get();

    if (!doc.exists) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final userName = userDoc['name'] ?? 'Client';
    final userEmail = userDoc['email'] ?? '';
    final userPhone = userDoc['phone'] ?? '';

    final data = doc.data()!;
    List bookedBy = data['booked_by'] ?? [];
    List bookedNames = data['booked_names'] ?? [];

    if (bookedBy.contains(currentUser.uid)) {
      int index = bookedBy.indexOf(currentUser.uid);
      bookedBy.removeAt(index);
      bookedNames.removeAt(index);

      await docRef.update({
        'booked': bookedBy.length,
        'booked_by': bookedBy,
        'booked_names': bookedNames,
      });

      await triggerNotification('cancel', userName, userEmail, userPhone);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );

      Navigator.pop(context);
    }
  }

  Widget _buildConfirmationContent() {
    final formattedDate = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text("Trainer: ${widget.trainerName}", 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text("Date: $formattedDate", style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  Text("Time: ${widget.selectedTime}", style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 30),
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: bookSlot,
                child: const Text("Confirm Booking", style: TextStyle(fontSize: 16)),
              ),
              
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessContent() {
    return Container(
      color: Colors.green.shade50,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 100,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _controller.value * 0.2 + 0.8,
                    child: Opacity(
                      opacity: _controller.value,
                      child: const Text(
                        "Booking Confirmed!",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
              Text(
                "Trainer: ${widget.trainerName}",
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                "Date: ${DateFormat('yyyy-MM-dd').format(widget.selectedDate)}",
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                "Time: ${widget.selectedTime}",
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 40),
              Text(
                "A confirmation has been sent to your email",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  "Done",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _showSuccess ? null : AppBar(title: const Text("Confirm Booking")),
      body: _showSuccess ? _buildSuccessContent() : _buildConfirmationContent(),
    );
  }
}