import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'client_book_slot.dart';

class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _pastSlots = [];
  List<Map<String, dynamic>> _upcomingSlots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToBookedSlots(); // real-time listener
  }
void _listenToBookedSlots() {
  final user = _auth.currentUser;
  if (user == null) return;

  _firestore
  .collection('trainer_slots')
  .where('booked_by', arrayContains: user.uid)
  .snapshots()
  .listen((snapshot) {
    try {
      final now = DateTime.now();
      final past = <Map<String, dynamic>>[];
      final upcoming = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // DATE
        DateTime rawDate = DateTime.now();
        if (data['date'] is Timestamp) {
          rawDate = (data['date'] as Timestamp).toDate().toLocal();
        }

        // TIME (robust)
        final timeRaw = (data['time'] ?? '').toString();
        final startStr = timeRaw.contains(' - ')
            ? timeRaw.split(' - ').first.trim()
            : timeRaw.trim();

        TimeOfDay timeOfDay;
        try {
          final parsed = DateFormat.jm().parseLoose(startStr);
          timeOfDay = TimeOfDay(hour: parsed.hour, minute: parsed.minute);
        } catch (_) {
          // If time field is missing/bad, skip this doc instead of crashing
          debugPrint('Skipped doc ${doc.id} due to invalid time: "$timeRaw"');
          continue;
        }

        final slotDateTime = DateTime(
          rawDate.year, rawDate.month, rawDate.day, timeOfDay.hour, timeOfDay.minute,
        );

        final statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
        final perUserStatus = statusByUser[user.uid] as String?;

        final slot = {
          'id': doc.id,
          'date': slotDateTime,
          'time': timeRaw,
          'trainer': data['trainer_name'] ?? 'Unknown Trainer',
          'status': perUserStatus ?? (data['status'] ?? 'Confirmed'),
          'docRef': doc.reference,
        };

        (slotDateTime.isBefore(now) ? past : upcoming).add(slot);
      }

      setState(() {
        _pastSlots = past;
        _upcomingSlots = upcoming;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('MySchedule snapshot parse error: $e\n$st');
      setState(() => _isLoading = false);
    }
  }, onError: (e, st) {
    debugPrint('MySchedule stream error: $e\n$st');
    setState(() => _isLoading = false);
  });

  
}

  
Future<void> _cancelBooking(DocumentReference docRef) async {
  final user = _auth.currentUser;
  if (user == null) return;

  try {
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (!snap.exists) throw Exception('Slot not found');

      final data = snap.data() as Map<String, dynamic>;
      List bookedBy     = List.from(data['booked_by'] ?? []);
      List bookedNames  = List.from(data['booked_names'] ?? []);
      List bookedEmails = List.from(data['booked_emails'] ?? []);

      // Find by uid, then remove name/email at the same index
      final idx = bookedBy.indexOf(user.uid);
      if (idx == -1) throw Exception('You do not have a booking in this slot');

      // Optionally fetch canonical name/email (if you want perfect consistency)
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userName = userDoc.data()?['name'] ?? 'Client';
      final userEmail = userDoc.data()?['email'] ?? '';

      bookedBy.removeAt(idx);
      if (idx < bookedNames.length)  bookedNames.removeAt(idx);
      if (idx < bookedEmails.length) bookedEmails.removeAt(idx);

      transaction.update(docRef, {
        'booked': bookedBy.length,
        'booked_by': bookedBy,
        'booked_names': bookedNames,
        'booked_emails': bookedEmails,
        'last_updated': FieldValue.serverTimestamp(),
        // Per-user status (doesn't affect other attendees)
        'status_by_user': { user.uid: 'Cancelled' },
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking cancelled successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to cancel: ${e.toString()}')),
    );
  }
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

  void _rescheduleBooking(Map<String, dynamic> slot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientBookSlot(
          rescheduleSlot: slot,
        ),
      ),
    );
  }

  Widget _buildSlotCard(Map<String, dynamic> slot, {bool isPast = false}) {
    final dateStr = DateFormat.yMMMMEEEEd().format(slot['date']);
    final time = slot['time'];
    final status = slot['status'] ?? 'Confirmed';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    slot['trainer'],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                  ),
                ),
               if (!isPast) ...[
  if (status != 'Rescheduled')
    TextButton(
      onPressed: () => _rescheduleBooking(slot),
      child: const Text('Reschedule', style: TextStyle(color: Colors.orange)),
    ),
  TextButton(
    onPressed: () => _showCancelDialog(slot['docRef']),
    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
  ),
]

              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'Cancelled'
    ? Colors.red
    : status == 'Rescheduled'
        ? Colors.orange
        : Colors.green,

                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.grey, size: 18),
                const SizedBox(width: 8),
                Text(dateStr, style: const TextStyle(color: Colors.black87, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey, size: 18),
                const SizedBox(width: 8),
                Text(time, style: const TextStyle(color: Colors.black87, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _exportToPDF() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('My Schedule - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}')),
          if (_upcomingSlots.isNotEmpty) ...[
            pw.Header(level: 1, child: pw.Text('Upcoming Sessions')),
            ..._upcomingSlots.map((slot) => pw.Paragraph(text: '📅 ${DateFormat('EEEE, MMMM d').format(slot['date'])} - ${slot['time']} with ${slot['trainer']} (${slot['status']})')),
            pw.SizedBox(height: 16),
          ],
          if (_pastSlots.isNotEmpty) ...[
            pw.Header(level: 1, child: pw.Text('Past Sessions')),
            ..._pastSlots.map((slot) => pw.Paragraph(text: '🕒 ${DateFormat('EEEE, MMMM d').format(slot['date'])} - ${slot['time']} with ${slot['trainer']} (${slot['status']})')),
          ],
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FA),
        appBar: AppBar(
          title: const Text('My Scheduled Sessions'),
          backgroundColor: const Color(0xFF1C2D5E),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _exportToPDF,
              tooltip: 'Export to PDF',
            )
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _upcomingSlots.isEmpty
                      ? const Center(child: Text('No upcoming sessions'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _upcomingSlots.length,
                          itemBuilder: (context, index) => _buildSlotCard(_upcomingSlots[index]),
                        ),
                  _pastSlots.isEmpty
                      ? const Center(child: Text('No past sessions'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pastSlots.length,
                          itemBuilder: (context, index) => _buildSlotCard(_pastSlots[index], isPast: true),
                        ),
                ],
              ),
      ),
    );
  }
}
