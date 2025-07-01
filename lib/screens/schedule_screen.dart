//schudhle_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
 
class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});
 
  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}
 
class _MySchedulePageState extends State<MySchedulePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _bookedSlots = [];
 
  @override
  void initState() {
    super.initState();
    _fetchBookedSlots();
  }
 
  Future<void> _fetchBookedSlots() async {
    final user = _auth.currentUser;
    if (user == null) return;
 
    try {
      final querySnapshot = await _firestore
          .collection('trainer_slots')
          .where('booked_by', arrayContains: user.uid)
          .get();
 
      setState(() {
        _bookedSlots = querySnapshot.docs.map((doc) {
          final data = doc.data();
          DateTime date;
          if (data['date'] is Timestamp) {
            final utcDate = (data['date'] as Timestamp).toDate();
            date = DateTime(utcDate.year, utcDate.month, utcDate.day);
          } else if (data['date'] is DateTime) {
            date = data['date'] as DateTime;
          } else if (data['date'] is String) {
            date = DateTime.parse(data['date'] as String);
          } else {
            date = DateTime.now();
          }
 
          return {
            'id': doc.id,
            'date': date,
            'time': data['time'] ?? '',
            'trainer': data['trainer_name'] ?? 'Unknown Trainer',
            'docRef': doc.reference,
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching slots: ${e.toString()}')),
      );
    }
  }
 
  Future<void> _cancelBooking(DocumentReference docRef) async {
    final user = _auth.currentUser;
    if (user == null) return;
 
    try {
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) throw Exception('Slot not found');
 
        List bookedBy = List.from(doc['booked_by'] ?? []);
        List bookedNames = List.from(doc['booked_names'] ?? []);
 
        if (!bookedBy.contains(user.uid)) {
          throw Exception('No booking found to cancel');
        }
 
        int index = bookedBy.indexOf(user.uid);
        bookedBy.removeAt(index);
        bookedNames.removeAt(index);
 
        transaction.update(docRef, {
          'booked': FieldValue.increment(-1),
          'booked_by': bookedBy,
          'booked_names': bookedNames,
        });
      });
 
      await _fetchBookedSlots();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: ${e.toString()}')),
      );
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('My Scheduled Sessions'),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookedSlots.isEmpty
              ? const Center(
                  child: Text(
                    'No booked sessions found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchBookedSlots,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _bookedSlots.length,
                    itemBuilder: (context, index) {
                      final slot = _bookedSlots[index];
                      final dateStr = DateFormat('EEEE, MMMM d').format(slot['date']);
                      final time = slot['time'];
 
                      return Card(
                        elevation: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1C2D5E), Color(0xFF3D5A80)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        slot['trainer'],
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                      onPressed: () => _showCancelDialog(slot['docRef']),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, color: Colors.white70, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, color: Colors.white70, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      time,
                                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
 
  void _showCancelDialog(DocumentReference docRef) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelBooking(docRef);
            },
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
 