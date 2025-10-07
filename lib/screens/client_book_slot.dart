import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'booking_confirmation_page.dart';
import 'client_plans_screen.dart'; // Add this import
class ClientBookSlot extends StatefulWidget {
  final Map<String, dynamic>? rescheduleSlot;

  const ClientBookSlot({Key? key, this.rescheduleSlot}) : super(key: key);

  @override
  State<ClientBookSlot> createState() => _ClientBookSlotState();
}

class _ClientBookSlotState extends State<ClientBookSlot> {
  DateTime _focusedDate = DateTime.now();
  DateTime? _selectedDate;
  final int slotCapacity = 6;
  final String trainerName = 'Kenny Sims';
  bool _isLoading = false;
  String? _selectedPurchaseId;
  Map<String, dynamic>? _selectedPurchaseData;

  final Map<String, List<Map<String, String>>> availabilityMap = {
    'Monday': [
      {'start': '05:30', 'end': '11:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Tuesday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Wednesday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Thursday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Friday': [
      {'start': '05:30', 'end': '11:00'},
    ],
    'Saturday': [
      {'start': '05:30', 'end': '11:00'},
    ],
    'Sunday': [
      {'start': '05:30', 'end': '11:00'},
    ],
  };
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when returning to this screen
    _loadEligiblePurchase();
  }

  // Add this to handle screen focus changes
  @override
  void dispose() {
    // Cancel any ongoing operations if needed
    super.dispose();
  }
    @override
  void initState() {
    super.initState();
    if (widget.rescheduleSlot != null) {
      // Handle both DateTime and Timestamp types
      if (widget.rescheduleSlot!['date'] is Timestamp) {
        _selectedDate = (widget.rescheduleSlot!['date'] as Timestamp).toDate();
        _focusedDate = (widget.rescheduleSlot!['date'] as Timestamp).toDate();
      } else if (widget.rescheduleSlot!['date'] is DateTime) {
        _selectedDate = widget.rescheduleSlot!['date'] as DateTime;
        _focusedDate = widget.rescheduleSlot!['date'] as DateTime;
      }
    } else {
      _selectedDate = DateTime.now();
    }
    _loadEligiblePurchase();
    _debugPrintActivePurchases();
    _debugBookingProcess();
    
    // Optional: Fix existing data
    // Fix any existing data inconsistencies
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fixExistingPurchaseIds();
      _fixInconsistentSessionData(); // Add this line
    });
  }
  // Load the eligible purchase for booking with better error handling
  Future<void> _loadEligiblePurchase() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final purchase = await _getEligiblePurchase();
      
      if (purchase != null) {
        setState(() {
          _selectedPurchaseId = purchase['purchaseId'];
          _selectedPurchaseData = purchase;
        });
        
        print('✅ Loaded eligible purchase: ${purchase['planName']}');
        print('🆔 Purchase ID set to: ${purchase['purchaseId']}');
        print('📊 Remaining sessions: ${purchase['remainingSessions']}');
        print('📊 Booked sessions: ${purchase['bookedSessions']}');
        print('📊 Available sessions: ${purchase['availableSessions']}');
      } else {
        setState(() {
          _selectedPurchaseId = null;
          _selectedPurchaseData = null;
        });
        print('❌ No eligible purchase found');
      }
    } catch (e) {
      print('❌loading eligible purchase');
      setState(() {
        _selectedPurchaseId = null;
        _selectedPurchaseData = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<String> generateHourlySlots(String start, String end, DateTime day) {
    List<String> slots = [];
    DateFormat format = DateFormat("HH:mm");
    DateTime slotStart = DateTime(day.year, day.month, day.day,
        format.parse(start).hour, format.parse(start).minute);
    DateTime slotEnd = DateTime(day.year, day.month, day.day,
        format.parse(end).hour, format.parse(end).minute);

    while (slotStart.isBefore(slotEnd)) {
      final nextHour = slotStart.add(const Duration(hours: 1));
      slots.add('${DateFormat.jm().format(slotStart)} - ${DateFormat.jm().format(nextHour)}');
      slotStart = nextHour;
    }
    return slots;
  }

  List<String> getSlotsForDay(DateTime date) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final selectedMidnight = DateTime(date.year, date.month, date.day);

    if (selectedMidnight.isBefore(todayMidnight)) return [];

    final weekday = DateFormat('EEEE').format(date);
    final blocks = availabilityMap[weekday] ?? [];
    List<String> result = [];

    for (final block in blocks) {
      if (isSameDay(date, now)) {
        DateTime currentTime = now;
        DateTime blockEnd = DateTime(date.year, date.month, date.day,
            int.parse(block['end']!.split(':')[0]), int.parse(block['end']!.split(':')[1]));
        if (blockEnd.isAfter(currentTime)) {
          DateTime adjustedStart = currentTime.isAfter(DateTime(date.year, date.month, date.day,
                      int.parse(block['start']!.split(':')[0]), int.parse(block['start']!.split(':')[1])))
              ? currentTime
              : DateTime(date.year, date.month, date.day,
                      int.parse(block['start']!.split(':')[0]), int.parse(block['start']!.split(':')[1]));
          result.addAll(generateHourlySlots(
              DateFormat("HH:mm").format(adjustedStart), block['end']!, date));
        }
      } else {
        result.addAll(generateHourlySlots(block['start']!, block['end']!, date));
      }
    }
    return result;
  }

  bool _isDateDisabled(DateTime date) {
    final today = DateTime.now();
    return date.isBefore(DateTime(today.year, today.month, today.day));
  }
  
  Future<Map<String, Map<String, dynamic>>> getSlotStatuses(DateTime date, List<String> slots) async {
    Map<String, Map<String, dynamic>> statuses = {};
    final currentUser = FirebaseAuth.instance.currentUser;
    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    for (String time in slots) {
      final docId = "$dateKey|$time";
      final doc = await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).get();
      if (!doc.exists) {
        statuses[time] = {'isFull': false, 'isBookedByUser': false};
      } else {
        List bookedBy = doc['booked_by'] ?? [];
        statuses[time] = {
          'isFull': bookedBy.length >= slotCapacity,
          'isBookedByUser': bookedBy.contains(currentUser?.uid),
        };
      }
    }
    return statuses;
  }
  // Add this method to ClientBookSlot for immediate data sync
 // Add this method to ClientBookSlot for immediate data sync
  Future<void> _forceRefreshPurchaseData() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // Small delay to ensure Firestore has processed the previous operation
      await Future.delayed(Duration(milliseconds: 500));
      
      // Clear current selection
      setState(() {
        _selectedPurchaseId = null;
        _selectedPurchaseData = null;
      });
      
      // Reload from scratch
      await _loadEligiblePurchase();
      
      // Additional verification
      final eligibility = await _checkUserEligibility();
      print('🔄 FORCE REFRESH COMPLETE:');
      print('   Eligible: ${eligibility['eligible']}');
      if (eligibility['eligible']) {
        print('   Available Sessions: ${eligibility['availableSessions']}');
      }
      
    } catch (e) {
      print('❌ Error in force refresh');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Future<void> _debugBookingProcess() async {
    final eligibility = await _checkUserEligibility();
    print('=== 🎯 BOOKING DEBUG ===');
    print('Eligible: ${eligibility['eligible']}');
    if (eligibility['eligible']) {
      print('Selected Purchase: ${eligibility['purchaseData']['planName']}');
      print('Purchase ID: ${eligibility['purchaseId']}');
      print('Remaining Sessions: ${eligibility['purchaseData']['remainingSessions']}');
      print('Purchase Date: ${eligibility['purchaseData']['purchaseDate']}');
    }
    print('=== 🎯 END DEBUG ===');
  }

  // Get the oldest active purchase with remaining sessions (FIFO)
  // Get the oldest active purchase with remaining sessions (FIFO)
  Future<Map<String, dynamic>?> _getEligiblePurchase() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      List<Map<String, dynamic>> eligiblePurchases = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'] as bool? ?? false;
        final remainingSessions = data['remainingSessions'] as int? ?? 0;
        final bookedSessions = data['bookedSessions'] as int? ?? 0;
        final status = (data['status'] as String? ?? 'active').toLowerCase();
        
        // ✅ CRITICAL FIX: Calculate available sessions CORRECTLY
        final totalSessions = data['totalSessions'] as int? ?? 0;
        final availableSessions = totalSessions - bookedSessions;
        // Plan is eligible if it's active, not cancelled, and has available sessions
        final isEligible = isActive && 
                          status != 'cancelled' && 
                          status != 'completed' &&
                          status != 'expired' &&
                          availableSessions > 0; // Use availableSessions, not remainingSessions
                
        if (isEligible) {
          String purchaseId;
          if (data['purchaseId'] != null && data['purchaseId'].toString().isNotEmpty) {
            purchaseId = data['purchaseId'] as String;
          } else {
            purchaseId = doc.id;
          }
          
          eligiblePurchases.add({
            ...data,
            'purchaseId': purchaseId,
            'docId': doc.id,
            'availableSessions': availableSessions, // Store the calculated value
          });
        }
      }

      if (eligiblePurchases.isEmpty) return null;

      // Use LIFO (newest purchase first)
      eligiblePurchases.sort((a, b) {
        final dateA = (a['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dateB = (b['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        return dateB.compareTo(dateA); // Newest first
      });

      final selectedPurchase = eligiblePurchases.first;

      print('🎯 ELIGIBLE PURCHASES SORTED (NEWEST FIRST):');
      for (var purchase in eligiblePurchases) {
        print('   📋 ${purchase['planName']} - ${purchase['availableSessions']} available (${purchase['remainingSessions']} remaining - ${purchase['bookedSessions']} booked)');
      }

      return eligiblePurchases.first;
    } catch (e) {
      debugPrint('❌ Error getting eligible purchase:');
      return null;
    }
  }
  Future<void> _debugPrintActivePurchases() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      print('=== 🔍 DEBUG: All Purchases for User ===');
      for (final doc in snapshot.docs) {
        final data = doc.data();
        print('📋 Plan: ${data['planName']}');
        print('   Status: ${data['status']}');
        print('   Remaining: ${data['remainingSessions']}');
        print('   PurchaseId (field): ${data['purchaseId']}');
        print('   Document ID: ${doc.id}');
        print('   Active: ${data['isActive']}');
        print('   Purchase Date: ${data['purchaseDate']}');
        print('---');
      }
      print('=== 🔍 END DEBUG ===');
    } catch (e) {
      print('❌ Debug error');
    }
  }

  // Add this method to fix existing purchase documents
  Future<void> _fixExistingPurchaseIds() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final docId = doc.id;
        
        // If purchaseId is missing or doesn't match document ID, fix it
        if (data['purchaseId'] == null || data['purchaseId'] != docId) {
          await doc.reference.update({
            'purchaseId': docId,
            'docId': docId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('✅ Fixed purchase ID for document: $docId');
        }
      }
    } catch (e) {
      print('❌ Error fixing purchase IDs');
    }
  }
  // Check if user has any active purchase with remaining sessions
  Future<Map<String, dynamic>> _checkUserEligibility() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {
        'eligible': false, 
        'message': 'Please sign in to book slots',
        'canCancelOnly': false
      };
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      List<Map<String, dynamic>> eligiblePurchases = [];
      List<Map<String, dynamic>> inactivePurchases = [];
      int totalAvailableSessions = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'] as bool? ?? false;
        final remainingSessions = data['remainingSessions'] as int? ?? 0;
        final bookedSessions = data['bookedSessions'] as int? ?? 0;
        final status = (data['status'] as String? ?? 'active').toLowerCase();
        
        // ✅ FIX: Calculate available sessions correctly
        final totalSessions = data['totalSessions'] as int? ?? 0;
        final availableSessions = totalSessions - bookedSessions;

        // ✅ FIX: Use availableSessions for eligibility check
        final isEligible = isActive && 
                          status != 'cancelled' && 
                          status != 'completed' &&
                          status != 'expired' &&
                          availableSessions > 0; // Use available sessions, not remaining

        if (isEligible) {
          String purchaseId;
          if (data['purchaseId'] != null && data['purchaseId'].toString().isNotEmpty) {
            purchaseId = data['purchaseId'] as String;
          } else {
            purchaseId = doc.id;
          }
          
          eligiblePurchases.add({
            ...data,
            'purchaseId': purchaseId,
            'docId': doc.id,
            'availableSessions': availableSessions, // Store the calculated value
          });

          totalAvailableSessions += availableSessions;
        } else {
          // Track inactive purchases for display purposes only
          inactivePurchases.add({
            ...data,
            'purchaseId': doc.id,
            'docId': doc.id,
            'availableSessions': availableSessions,
          });
        }
      }

      print('📈 TOTAL: User has $totalAvailableSessions available session(s) across ${eligiblePurchases.length} active plans');
      print('📋 INACTIVE: User has ${inactivePurchases.length} inactive/cancelled plans');

      if (eligiblePurchases.isEmpty) {
        return {
          'eligible': false,
          'message': totalAvailableSessions <= 0 
              ? 'You have used all available sessions in your active plans. Please purchase a new plan to book more sessions.'
              : 'You have no active plans with available sessions. Please purchase a plan to proceed.',
          'canCancelOnly': inactivePurchases.isNotEmpty,
          'inactivePurchases': inactivePurchases,
        };
      }

      // Use LIFO (newest purchase first) for better user experience
      eligiblePurchases.sort((a, b) {
        final dateA = (a['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dateB = (b['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        return dateB.compareTo(dateA); // Newest first
      });

      final selectedPurchase = eligiblePurchases.first;
      final purchaseId = selectedPurchase['purchaseId'] as String;
      final availableSessions = selectedPurchase['availableSessions'] as int;

      return {
        'eligible': true,
        'message': '',
        'purchaseId': purchaseId,
        'docId': selectedPurchase['docId'],
        'purchaseData': selectedPurchase,
        'availableSessions': availableSessions,
        'totalAvailableSessions': totalAvailableSessions,
        'eligiblePurchases': eligiblePurchases,
        'canCancelOnly': false,
      };
    } catch (e) {
      debugPrint('❌ Error checking user eligibility');
      return {
        'eligible': false, 
        'message': 'Error checking your plan status. Please try again.',
        'canCancelOnly': false
      };
    }
  }
  Future<void> _debugPrintSessionDetails() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      print('=== 🔍 SESSION DETAILS: All Purchases ===');
      int totalBookableSessions = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'] as bool? ?? false;
        final remainingSessions = data['remainingSessions'] as int? ?? 0;
        final totalSessions = data['totalSessions'] as int? ?? 0;
        final usedSessions = data['usedSessions'] as int? ?? 0;
        final status = (data['status'] as String? ?? 'active').toLowerCase();
        
        final matchesDashboardCriteria = isActive && remainingSessions > 0 && status != 'cancelled';
        
        if (matchesDashboardCriteria) {
          totalBookableSessions += remainingSessions;
          print('✅ BOOKABLE: ${data['planName']}');
          print('   📊 Sessions: $usedSessions used, $remainingSessions remaining of $totalSessions total');
          print('   🎯 Can book $remainingSessions more session(s)');
        } else {
          print('❌ NOT BOOKABLE: ${data['planName']}');
          print('   📊 Sessions: $usedSessions used, $remainingSessions remaining of $totalSessions total');
        }
        print('---');
      }
      
      print('📈 TOTAL: User can book $totalBookableSessions session(s) across all active plans');
      print('=== 🔍 END SESSION DETAILS ===');
    } catch (e) {
      print('❌ Debug error');
    }
  }
  
  Future<void> _cancelBooking(String docId, {bool suppressError = false}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (!suppressError) setState(() => _isLoading = true);
    
    try {
      // First get the slot to find the purchaseId
      final slotDoc = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .doc(docId)
          .get();
      
      if (!slotDoc.exists) {
        if (!suppressError) throw Exception('Slot document not found');
        return;
      }

      final slotData = slotDoc.data()!;
      final userPurchaseMap = Map<String, dynamic>.from(slotData['user_purchase_map'] ?? {});
      final purchaseId = userPurchaseMap[currentUser.uid] as String?;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          if (!suppressError) throw Exception('Slot document not found');
          return;
        }

        List bookedBy = List.from(doc['booked_by'] ?? []);
        List bookedNames = List.from(doc['booked_names'] ?? []);
        List bookedEmails = List.from(doc['booked_emails'] ?? []);
        List purchaseIds = List.from(doc['purchase_ids'] ?? []);
        Map<String, dynamic> userPurchaseMap = Map<String, dynamic>.from(doc['user_purchase_map'] ?? {});

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
            
        final userEmail = userDoc['email'] ?? '';
        final userName = userDoc['name'] ?? 'Client';

        final userIndex = bookedBy.indexOf(currentUser.uid);
        if (userIndex == -1) {
          if (!suppressError) throw Exception('No booking found for current user');
          return;
        }

        bookedBy.removeAt(userIndex);
        bookedNames.removeAt(userIndex);
        bookedEmails.removeAt(userIndex);
        if (userIndex < purchaseIds.length) {
          purchaseIds.removeAt(userIndex);
        }
        userPurchaseMap.remove(currentUser.uid);

        transaction.update(docRef, {
          'booked': bookedBy.length,
          'booked_by': bookedBy,
          'booked_names': bookedNames,
          'booked_emails': bookedEmails,
          'purchase_ids': purchaseIds,
          'user_purchase_map': userPurchaseMap,
          'last_updated': FieldValue.serverTimestamp(),
          // Update status to show cancelled
          'status_by_user': {
            currentUser.uid: 'Cancelled'
          },
        });
      });

      // ✅ CRITICAL FIX: Update purchase data to make session available again
      if (purchaseId != null) {
        await _returnSessionToPurchase(purchaseId);
      }

      // ✅ CRITICAL FIX: Force refresh purchase data immediately
      await _forceRefreshPurchaseData();

      if (!suppressError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking cancelled successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (!suppressError) setState(() {});
    } catch (e) {
      if (!suppressError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel booking'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (!suppressError) debugPrint('Cancellation error');
    } finally {
      if (!suppressError) setState(() => _isLoading = false);
    }
  }

  // Add this method to return session to purchase
  Future<void> _returnSessionToPurchase(String purchaseId) async {
    try {
      final purchaseDoc = await FirebaseFirestore.instance
          .collection('client_purchases')
          .doc(purchaseId)
          .get();

      if (purchaseDoc.exists) {
        final data = purchaseDoc.data()!;
        final isActive = data['isActive'] as bool? ?? false;
        final status = (data['status'] as String? ?? 'active').toLowerCase();
        final currentBooked = (data['bookedSessions'] as num?)?.toInt() ?? 0;
        final totalSessions = (data['totalSessions'] as num?)?.toInt() ?? 0;
        
        // ✅ FIX: Only update if plan is active AND we have booked sessions to decrement
        if (isActive && status != 'cancelled' && currentBooked > 0) {
          final newBookedCount = currentBooked - 1;
          final newAvailableSessions = totalSessions - newBookedCount;
          
          await purchaseDoc.reference.update({
            'bookedSessions': newBookedCount,
            'availableSessions': newAvailableSessions, // Recalculated value
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('🔄 Updated purchase on cancellation: Booked: $newBookedCount, Available: $newAvailableSessions, Total: $totalSessions');
        } else {
          print('ℹ️ Session not returned - Plan inactive/cancelled or no booked sessions');
        }
      }
    } catch (e) {
      print('⚠️ Could not update purchase sessions, but booking was cancelled');
    }
  }
  Future<void> _fixInconsistentSessionData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final totalSessions = (data['totalSessions'] as num?)?.toInt() ?? 0;
        final bookedSessions = (data['bookedSessions'] as num?)?.toInt() ?? 0;
        final currentAvailable = (data['availableSessions'] as num?)?.toInt() ?? 0;
        
        // Calculate what available sessions should be
        final calculatedAvailable = totalSessions - bookedSessions;
        
        // If there's a discrepancy, fix it
        if (currentAvailable != calculatedAvailable) {
          await doc.reference.update({
            'availableSessions': calculatedAvailable,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('✅ Fixed inconsistent session data for ${data['planName']}: available=$calculatedAvailable (was $currentAvailable)');
        }
      }
    } catch (e) {
      print('❌ Error fixing inconsistent session data');
    }
  }

  // Increment remaining sessions for specific purchase
  Future<void> _incrementRemainingSessions(String purchaseId) async {
    try {
      final purchaseDoc = await FirebaseFirestore.instance
          .collection('client_purchases')
          .doc(purchaseId)
          .get();

      if (purchaseDoc.exists) {
        final data = purchaseDoc.data()!;
        final remainingSessions = (data['remainingSessions'] as num?)?.toInt() ?? 0;
        final totalSessions = (data['totalSessions'] as num?)?.toInt() ?? 0;
        
        if (remainingSessions < totalSessions) {
          await purchaseDoc.reference.update({
            'remainingSessions': remainingSessions + 1,
            'usedSessions': FieldValue.increment(-1),
          });
          
          // Reload purchase data after update
          await _loadEligiblePurchase();
        }
      }
    } catch (e) {
      debugPrint('Error incrementing remaining sessions:');
    }
  }
  // Add these helper methods to your _ClientBookSlotState class:

  Widget _buildTimeSlotItem(String time) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        time,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRequirementItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.circle,
            size: 6,
            color: const Color(0xFF1C2D5E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
  void _checkAndClearRescheduleContext() {
    if (widget.rescheduleSlot != null) {
      // After a short delay, navigate to a fresh instance without reschedule context
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ClientBookSlot(rescheduleSlot: null),
            ),
          );
        }
      });
    }
  }
  void showSlotPopup(String time) async {
    if (_isLoading) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to book slots')),
      );
      return;
    }

    final selectedDate = _selectedDate ?? _focusedDate;
    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
    final docId = "$dateKey|$time";
    final doc = await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).get();
    final isBookedByUser = doc.exists && (doc['booked_by'] ?? []).contains(currentUser.uid);
    final isFull = doc.exists && (doc['booked_by'] ?? []).length >= slotCapacity;

    // ✅ FIX: Check if this is actually a reschedule flow
    bool isRescheduleFlow = widget.rescheduleSlot != null && 
                          widget.rescheduleSlot!['isReschedule'] == true;

    if (!isBookedByUser && !isFull && !isRescheduleFlow) {
      // Only check eligibility for NEW bookings, not reschedules
      final eligibilityResult = await _checkUserEligibility();
      
      if (!eligibilityResult['eligible']) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 10,
            backgroundColor: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with icon and title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade700,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Booking Not Allowed',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Message content
                  Text(
                    eligibilityResult['message'],
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      color: Colors.black87,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Action buttons
                  Row(
                    children: [
                      if (eligibilityResult['message'].contains('used all available sessions'))
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ClientPlansScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1C2D5E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'View Plans',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else if (eligibilityResult['message'].contains('purchase') || 
                          eligibilityResult['message'].contains('plan'))
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ClientPlansScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1C2D5E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'View Plans',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      
                      const SizedBox(width: 12),
                      
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
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
        );
        return;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isBookedByUser ? 'Cancel Slot' : isFull ? 'Slot Full' : (isRescheduleFlow ? 'Reschedule Slot' : 'Book Slot')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isBookedByUser
                ? 'Do you want to cancel this booking at $time?'
                : isFull
                    ? 'This slot is already full'
                    : isRescheduleFlow
                        ? 'Do you want to reschedule to this slot at $time?'
                        : 'Do you want to proceed to book this slot at $time?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          if (!isFull || isBookedByUser || isRescheduleFlow)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);

                if (isBookedByUser) {
                  await _cancelBooking(docId);
                  setState(() {});
                } else {
                  // ✅ FIX: Clear reschedule context after successful reschedule
                  if (isRescheduleFlow) {
                    // For reschedule, proceed directly without purchase validation
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookingConfirmationPage(
                          selectedDate: selectedDate,
                          selectedTime: time,
                          trainerName: trainerName,
                          slotCapacity: slotCapacity,
                          rescheduleSlot: widget.rescheduleSlot,
                          purchaseId: 'reschedule_no_plan',
                          purchaseData: {
                            'planName': 'Rescheduled Session',
                            'remainingSessions': 0,
                            'totalSessions': 0,
                          },
                        ),
                      ),
                    );
                    
                    if (result == true) {
                      // ✅ CRITICAL FIX: Clear the reschedule context and refresh
                      // This ensures subsequent bookings are treated as new bookings
                      await _forceRefreshPurchaseData();
                      _checkAndClearRescheduleContext();

                    }
                  } else {
                    // For new booking, check eligibility
                    final eligibilityResult = await _checkUserEligibility();
                    final purchaseId = eligibilityResult['purchaseId'] as String?;
                    final purchaseData = eligibilityResult['purchaseData'] as Map<String, dynamic>?;

                    if (purchaseId == null || purchaseData == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Error: No active plan found')),
                      );
                      return;
                    }

                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookingConfirmationPage(
                          selectedDate: selectedDate,
                          selectedTime: time,
                          trainerName: trainerName,
                          slotCapacity: slotCapacity,
                          rescheduleSlot: null, // Ensure rescheduleSlot is null for new bookings
                          purchaseId: purchaseId,
                          purchaseData: purchaseData,
                        ),
                      ),
                    );
                    
                    if (result == true) {
                      await _forceRefreshPurchaseData();
                      setState(() {});
                    }
                  }
                }
              },
              child: Text(isBookedByUser ? 'Cancel Booking' : isRescheduleFlow ? 'Reschedule' : 'Proceed'),
            ),
        ],
      ),
    );
  }


  // Update _buildPurchaseInfo method in ClientBookSlot:

  Widget _buildPurchaseInfo() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _checkUserEligibility(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingPurchaseInfo();
        }

        if (!snapshot.hasData || !snapshot.data!['eligible']) {
          return _buildNoEligiblePlansInfo(snapshot.data?['message'], snapshot.data?['inactivePurchases']);
        }

        final eligibilityData = snapshot.data!;
        final eligiblePurchases = eligibilityData['eligiblePurchases'] as List<Map<String, dynamic>>;
        final totalAvailableSessions = eligibilityData['totalAvailableSessions'] as int;

        return Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Active Plans Available',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'You can book $totalAvailableSessions session(s) across ${eligiblePurchases.length} active plan(s)',
                style: TextStyle(
                  color: Colors.green[800],
                ),
              ),
              SizedBox(height: 8),
              ...eligiblePurchases.map((purchase) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  '• ${purchase['planName']}: ${purchase['availableSessions']} available (${purchase['remainingSessions']} remaining - ${purchase['bookedSessions']} booked)',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                  ),
                ),
              )).toList(),
              SizedBox(height: 8),
              Text(
                'Booking will use sessions from your newest active plan first',
                style: TextStyle(
                  color: Colors.green[600],
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoEligiblePlansInfo(String? message, List<Map<String, dynamic>>? inactivePurchases) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Active Plans',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      message ?? 'Please purchase a plan to book sessions.',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ClientPlansScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'View Plans',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.orange[600]!),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.orange[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (inactivePurchases != null && inactivePurchases.isNotEmpty) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inactive/Cancelled Plans:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700],
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  ...inactivePurchases.take(3).map((purchase) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle, size: 6, color: Colors.orange[500]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${purchase['planName']}: ${purchase['status']} (${purchase['availableSessions']} available)',
                            style: TextStyle(
                              color: Colors.orange[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingPurchaseInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue[600]),
          ),
          SizedBox(width: 12),
          Text(
            'Checking available plans...',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = _selectedDate ?? _focusedDate;
    final slots = getSlotsForDay(selectedDate);
    final dateLabel = DateFormat('EEEE, MMMM d').format(selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Book Appointment"),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Purchase Info Card REMOVED - Container commented out
                // _buildPurchaseInfo(),
                
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: TableCalendar(
                                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                                lastDay: DateTime(DateTime.now().year + 2, 12, 31),
                                focusedDay: _focusedDate,
                                selectedDayPredicate: (day) => isSameDay(day, selectedDate),
                                onDaySelected: (day, _) {
                                  if (_isDateDisabled(day)) return;

                                  final today = DateTime.now();
                                  setState(() {
                                    if (isSameDay(day, today)) {
                                      _selectedDate = DateTime.now();
                                    } else {
                                      _selectedDate = day;
                                    }
                                    _focusedDate = day;
                                  });
                                },
                                calendarBuilders: CalendarBuilders(
                                  defaultBuilder: (context, day, _) {
                                    final today = DateTime.now();
                                    if (day.isBefore(DateTime(today.year, today.month, today.day))) {
                                      return Center(
                                        child: Text(
                                          '${day.day}',
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                      );
                                    }
                                    return null;
                                  },
                                ),
                                headerStyle: const HeaderStyle(
                                  formatButtonVisible: false,
                                  titleCentered: true,
                                  titleTextStyle: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                                ),
                                calendarStyle: const CalendarStyle(
                                  todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                  selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                ),
                                daysOfWeekStyle: const DaysOfWeekStyle(
                                  weekdayStyle: TextStyle(color: Colors.black87),
                                  weekendStyle: TextStyle(color: Colors.black87),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(dateLabel,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E))),
                        const SizedBox(height: 12),
                        if (slots.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24.0),
                            child: Text("No available slots remaining for today",
                                style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ),
                        if (slots.isNotEmpty)
                          FutureBuilder<Map<String, Map<String, dynamic>>>(
                            future: getSlotStatuses(selectedDate, List<String>.from(slots)),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24.0),
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                                  child: Text('No Avaliable slots', style: const TextStyle(color: Colors.red)),
                                );
                              }
                              final statuses = snapshot.data ?? {};
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 3,
                                  ),
                                  itemCount: slots.length,
                                  itemBuilder: (context, index) {
                                    final time = slots[index];
                                    final slotInfo = statuses[time] ?? {'isFull': false, 'isBookedByUser': false};
                                    final isDisabled = slotInfo['isFull'] && !slotInfo['isBookedByUser'];
                                    final isBookedByUser = slotInfo['isBookedByUser'];

                                    return ElevatedButton(
                                      onPressed: isDisabled ? null : () => showSlotPopup(time),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        backgroundColor: isDisabled
                                            ? Colors.grey[200]
                                            : isBookedByUser
                                                ? Colors.green[50]
                                                : Colors.white,
                                        foregroundColor: isDisabled
                                            ? Colors.grey
                                            : isBookedByUser
                                                ? Colors.green[800]
                                                : const Color(0xFF1C2D5E),
                                        side: BorderSide(
                                          color: isDisabled
                                              ? Colors.grey
                                              : isBookedByUser
                                                  ? Colors.green
                                                  : const Color(0xFF1C2D5E),
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      child: Text(
                                        time,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}