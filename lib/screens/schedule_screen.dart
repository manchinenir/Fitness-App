import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
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
    _listenToBookedSlots();
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

          // Extract date and time correctly
          DateTime slotDate;
          String timeString = '';

          // Handle date parsing - ensure we get a DateTime
          if (data['date'] is Timestamp) {
            slotDate = (data['date'] as Timestamp).toDate().toLocal();
          } else if (data['date'] is DateTime) {
            slotDate = (data['date'] as DateTime).toLocal();
          } else if (data['date'] is String) {
            // Handle string date format (yyyy-MM-dd)
            try {
              slotDate = DateFormat('yyyy-MM-dd').parse(data['date'] as String);
            } catch (e) {
              debugPrint('Invalid date format: ${data['date']}');
              continue;
            }
          } else {
            debugPrint('Invalid date type: ${data['date']}');
            continue;
          }

          // ... rest of your parsing logic remains the same
          // Handle time parsing
          if (data['time'] is String) {
            timeString = data['time'] as String;
          } else {
            debugPrint('Invalid time type: ${data['time']}');
            continue;
          }

          // Parse the time to get DateTime with correct time component
          DateTime slotDateTime;
          try {
            // Extract start time from time string (e.g., "5:30 AM - 6:30 AM")
            final startTimeStr = timeString.contains(' - ')
                ? timeString.split(' - ').first.trim()
                : timeString.trim();

            // Parse the time using DateFormat.jm()
            final parsedTime = DateFormat.jm().parse(startTimeStr);

            // Combine date with time
            slotDateTime = DateTime(
              slotDate.year,
              slotDate.month,
              slotDate.day,
              parsedTime.hour,
              parsedTime.minute,
            );
          } catch (e) {
            debugPrint('Error parsing time "$timeString"');
            continue;
          }

          final statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
          final perUserStatus = statusByUser[user.uid] as String?;

          final slot = {
            'id': doc.id,
            'date': slotDateTime, // This is now always a DateTime
            'time': timeString,
            'trainer': data['trainer_name'] ?? 'Unknown Trainer',
            'status': perUserStatus ?? (data['status'] ?? 'Confirmed'),
            'docRef': doc.reference,
          };

          if (slotDateTime.isBefore(now)) {
            past.add(slot);
          } else {
            upcoming.add(slot);
          }
        }

        // Sort past sessions (newest first) and upcoming sessions (oldest first)
        past.sort((a, b) => b['date'].compareTo(a['date']));
        upcoming.sort((a, b) => a['date'].compareTo(b['date'])); // Fixed: should compare b['date']

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
      String? userPurchaseId;
      
      await _firestore.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        if (!snap.exists) throw Exception('Slot not found');

        final data = snap.data() as Map<String, dynamic>;
        List bookedBy = List.from(data['booked_by'] ?? []);
        List bookedNames = List.from(data['booked_names'] ?? []);
        List bookedEmails = List.from(data['booked_emails'] ?? []);
        List purchaseIds = List.from(data['purchase_ids'] ?? []);
        Map<String, dynamic> userPurchaseMap = Map<String, dynamic>.from(data['user_purchase_map'] ?? {});

        final idx = bookedBy.indexOf(user.uid);
        if (idx == -1) throw Exception('You do not have a booking in this slot');

        // Get the purchase ID before removing the user
        userPurchaseId = userPurchaseMap[user.uid] as String?;

        bookedBy.removeAt(idx);
        if (idx < bookedNames.length) bookedNames.removeAt(idx);
        if (idx < bookedEmails.length) bookedEmails.removeAt(idx);
        if (idx < purchaseIds.length) purchaseIds.removeAt(idx);
        userPurchaseMap.remove(user.uid);

        transaction.update(docRef, {
          'booked': bookedBy.length,
          'booked_by': bookedBy,
          'booked_names': bookedNames,
          'booked_emails': bookedEmails,
          'purchase_ids': purchaseIds,
          'user_purchase_map': userPurchaseMap,
          'last_updated': FieldValue.serverTimestamp(),
          'status_by_user': {user.uid: 'Cancelled'},
        });
      });

      // ✅ FIX: Update purchase data AFTER successful cancellation
    if (userPurchaseId != null) {
        await _updatePurchaseOnCancellation(userPurchaseId!);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Force refresh purchase data
      await _loadEligiblePurchase();
      setState(() {});

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel booking: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Cancellation error');
    }
  }

  // Add this helper method
  Future<void> _updatePurchaseOnCancellation(String purchaseId) async {
    try {
      final purchaseDoc = await _firestore.collection('client_purchases').doc(purchaseId).get();
      
      if (purchaseDoc.exists) {
        final purchaseData = purchaseDoc.data()!;
        final isActive = purchaseData['isActive'] as bool? ?? false;
        final status = (purchaseData['status'] as String? ?? 'active').toLowerCase();
        final currentBooked = (purchaseData['bookedSessions'] as num?)?.toInt() ?? 0;
        final currentRemaining = (purchaseData['remainingSessions'] as num?)?.toInt() ?? 0;
        final totalSessions = (purchaseData['totalSessions'] as num?)?.toInt() ?? 0;
        
        // ✅ FIX: Only update if plan is active AND we have booked sessions to decrement
        if (isActive && status != 'cancelled' && currentBooked > 0) {
          await purchaseDoc.reference.update({
            'bookedSessions': currentBooked - 1, // Decrement booked sessions
            'availableSessions': FieldValue.increment(1), // Increment available sessions
            // Remaining sessions stays the same - we're just moving from booked back to available
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('🔄 Updated purchase on cancellation: Booked: ${currentBooked - 1}, Available: +1');
        } else {
          print('ℹ️ Session not returned - Plan inactive/cancelled or no booked sessions');
        }
      }
    } catch (e) {
      print('⚠️ Could not update purchase sessions, but booking was cancelled');
    }
  }

  // Add this helper method to reload eligible purchases
  Future<void> _loadEligiblePurchase() async {
    // This method should reload the user's eligible purchases
    // You might need to implement this based on your book slot logic
    print('🔄 Reloading eligible purchases after cancellation');
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
    final rescheduleData = {
      ...slot,
      'date': Timestamp.fromDate(slot['date'] as DateTime),
      'time': slot['time'],
      'trainer': slot['trainer'],
      'docRef': slot['docRef'],
      'isReschedule': true,
      'originalSlotId': slot['id'],
    };

    // Use pushReplacement to ensure we don't go back to the reschedule context
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ClientBookSlot(
          rescheduleSlot: rescheduleData,
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
                      onPressed: () => _rescheduleBooking({
                        ...slot,
                        'id': slot['id'], // Ensure ID is passed
                      }),
                      child: const Text('Reschedule', style: TextStyle(color: Colors.orange)),
                    ),
                  TextButton(
                    onPressed: () => _showCancelDialog(slot['docRef']),
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                ]
              ],
            ),
            // ... rest of your card content remains the same
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
    try {
      final pdf = pw.Document();

      // Convert to US Eastern Time
      final now = DateTime.now();
      final usTime = now.subtract(Duration(hours: 10, minutes: 30)); // Convert IST to EST (approximate)
      final dateStr = DateFormat('MMMM d, yyyy').format(usTime);
      final timeStr = DateFormat('h:mm a').format(usTime);

      // Use standard A4 format (iOS 4.0, EA4 portrait format)
      final a4Format = PdfPageFormat.a4;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: a4Format,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => [
            // Title
            pw.Text(
              'My Training Schedule',
              style: pw.TextStyle(
                fontSize: 14, // Changed from 40 to 14
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 10), // Reduced from 15
            pw.Text(
              'Generated on: $dateStr and $timeStr EST',
              style: pw.TextStyle(fontSize: 11), // Changed from 28 to 11
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 20), // Reduced from 25

            // Upcoming Sessions Section
            if (_upcomingSlots.isNotEmpty) ...[
              pw.Text(
                'Upcoming Sessions (${_upcomingSlots.length})',
                style: pw.TextStyle(
                  fontSize: 14, // Changed from 36 to 14
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10), // Reduced from 15
              ..._upcomingSlots.map((slot) {
                final dateText = DateFormat('MMMM d, yyyy').format(slot['date']);
                final timeText = slot['time'];
                final trainerText = slot['trainer'];
                final statusText = slot['status'] ?? 'Confirmed';

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: double.infinity,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            trainerText,
                            style: pw.TextStyle(
                              fontSize: 12, // Changed from 32 to 12
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 6), // Reduced from 8
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  'Date: $dateText',
                                  style: pw.TextStyle(fontSize: 11), // Changed from 28 to 11
                                ),
                              ),
                              pw.Text(
                                'Status: ',
                                style: pw.TextStyle(
                                  fontSize: 11, // Changed from 28 to 11
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                statusText,
                                style: pw.TextStyle(
                                  fontSize: 11, // Changed from 28 to 11
                                  color: statusText == 'Cancelled'
                                      ? PdfColors.red
                                      : statusText == 'Rescheduled'
                                          ? PdfColors.orange
                                          : PdfColors.green,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 4), // Reduced from 5
                          pw.Text(
                            'Time: $timeText',
                            style: pw.TextStyle(fontSize: 11), // Changed from 28 to 11
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 10), // Reduced from 15
                    pw.Divider(thickness: 1, color: PdfColors.grey300),
                    pw.SizedBox(height: 8), // Reduced from 10
                  ],
                );
              }).toList(),
              pw.SizedBox(height: 15), // Reduced from 20
            ],

            // Past Sessions Section
            if (_pastSlots.isNotEmpty) ...[
              pw.Text(
                'Past Sessions (${_pastSlots.length})',
                style: pw.TextStyle(
                  fontSize: 14, // Changed from 36 to 14
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10), // Reduced from 15
              ..._pastSlots.map((slot) {
                final dateText = DateFormat('MMMM d, yyyy').format(slot['date']);
                final timeText = slot['time'];
                final trainerText = slot['trainer'];
                final statusText = slot['status'] ?? 'Completed';

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: double.infinity,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            trainerText,
                            style: pw.TextStyle(
                              fontSize: 12, // Changed from 32 to 12
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 6), // Reduced from 8
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  'Date: $dateText',
                                  style: pw.TextStyle(
                                    fontSize: 11, // Changed from 28 to 11
                                    color: PdfColors.grey600,
                                  ),
                                ),
                              ),
                              pw.Text(
                                'Status: $statusText',
                                style: pw.TextStyle(
                                  fontSize: 11, // Changed from 28 to 11
                                  color: PdfColors.grey600,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 4), // Reduced from 5
                          pw.Text(
                            'Time: $timeText',
                            style: pw.TextStyle(
                              fontSize: 11, // Changed from 28 to 11
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 10), // Reduced from 15
                    pw.Divider(thickness: 1, color: PdfColors.grey300),
                    pw.SizedBox(height: 8), // Reduced from 10
                  ],
                );
              }).toList(),
            ],

            // Empty state messages
            if (_upcomingSlots.isEmpty && _pastSlots.isEmpty) ...[
              pw.Center(
                child: pw.Text(
                  'No sessions found',
                  style: pw.TextStyle(fontSize: 11), // Changed from 32 to 11
                ),
              ),
            ],
          ],
          // Remove page numbers by not defining footer
          footer: null, // This removes page numbers
        ),
      );

      // Open the PDF printing dialog with fixed format and no options
      await Printing.layoutPdf(
        format: a4Format, // Fixed format - user can't change
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      // Show error message if PDF generation fails
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF'),
          backgroundColor: Colors.red,
        ),
      );
    }
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