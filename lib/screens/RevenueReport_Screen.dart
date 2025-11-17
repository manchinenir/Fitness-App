import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io' if (dart.library.html) 'dart:html' as io;
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart' if (dart.library.html) 'package:flutter/foundation.dart';

class RevenueReportScreen extends StatefulWidget {
  const RevenueReportScreen({super.key});

  @override
  State<RevenueReportScreen> createState() => _RevenueReportScreenState();
}

class _RevenueReportScreenState extends State<RevenueReportScreen> {
  final Color primaryColor = const Color(0xFF1C2D5E);
  final Color accentColor = const Color(0xFF00C853);
  final Color cardColor = const Color(0xFFF5F5F5);
  final Color textColor = const Color(0xFF333333);
  final Color highlightColor = const Color(0xFF6200EA);

  String? selectedMonth;
  int totalPlans = 0;
  int totalSlots = 0;
  double totalRevenue = 0.0;
  bool isLoading = false;
  late int selectedYear;
  late int currentYear;
  late int startRangeYear;

  StreamSubscription<QuerySnapshot>? _purchaseSub;
  StreamSubscription<QuerySnapshot>? _subscriptionSub;
  StreamSubscription<QuerySnapshot>? _slotSub;

  final Map<String, int> monthMap = {
    "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
    "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
  };

  final Map<String, Color> monthColors = {
    "JAN": const Color(0xFFE3F2FD),
    "FEB": const Color(0xFFE8F5E9),
    "MAR": const Color(0xFFF1F8E9),
    "APR": const Color(0xFFFCE4EC),
    "MAY": const Color(0xFFF3E5F5),
    "JUN": const Color(0xFFEDE7F6),
    "JUL": const Color(0xFFE8EAF6),
    "AUG": const Color(0xFFE0F7FA),
    "SEP": const Color(0xFFE0F2F1),
    "OCT": const Color(0xFFFFF3E0),
    "NOV": const Color(0xFFEFEBE9),
    "DEC": const Color(0xFFECEFF1),
  };

  @override
  void initState() {
    super.initState();
    currentYear = DateTime.now().toUtc().year;
    selectedYear = currentYear;
    startRangeYear = currentYear - 3;
    _startYearlySummaryStreams();
  }

  void _startYearlySummaryStreams() {
    _purchaseSub?.cancel();
    _subscriptionSub?.cancel();
    _slotSub?.cancel();

    final yearStart = DateTime.utc(selectedYear, 1, 1);
    final yearEnd = DateTime.utc(selectedYear + 1, 1, 1);

    _purchaseSub = FirebaseFirestore.instance
        .collection('client_purchases')
        .where('paymentStatus', isEqualTo: 'completed')
        .snapshots()
        .listen((_) {
      _calculateTotalSummary();
    });

    _subscriptionSub = FirebaseFirestore.instance
        .collection('client_subscriptions')
        .where('paymentStatus', isEqualTo: 'completed')
        .snapshots()
        .listen((_) {
      _calculateTotalSummary();
    });

    _slotSub = FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('date', isGreaterThanOrEqualTo: yearStart)
        .where('date', isLessThan: yearEnd)
        .snapshots()
        .listen((_) {
      _calculateTotalSummary();
    });

    _calculateTotalSummary();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _subscriptionSub?.cancel();
    _slotSub?.cancel();
    super.dispose();
  }

  Future<Map<String, String>> _fetchUserNames(Set<String> ids) async {
    final Map<String, String> names = {};
    await Future.wait(ids.map((id) async {
      if (id.isNotEmpty) {
        try {
          final snap = await FirebaseFirestore.instance.collection('users').doc(id).get();
          names[id] = snap.data()?['name'] as String? ?? 'Unknown';
        } catch (_) {
          names[id] = 'Unknown';
        }
      }
    }));
    return names;
  }

  Future<void> _calculateTotalSummary() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      double planRevenue = 0.0;
      double subscriptionRevenue = 0.0;
      int slots = 0;

      final yearStart = DateTime.utc(selectedYear, 1, 1);
      final yearEnd = DateTime.utc(selectedYear + 1, 1, 1);

      // ✅ Track ALL unique plans purchased during the year (regardless of current status)
      Set<String> uniquePlanNames = {};

      // ✅ Fetch all completed or COMPLETED plans for the selected year
      final planSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('paymentStatus', whereIn: ['completed', 'COMPLETED'])
          .get();

      for (var doc in planSnapshot.docs) {
        final data = doc.data();

        // Determine effective purchase date
        DateTime? effectiveDate;
        if (data['completedDate'] != null) {
          effectiveDate = (data['completedDate'] as Timestamp).toDate();
        } else if (data['createdAt'] != null) {
          effectiveDate = (data['createdAt'] as Timestamp).toDate();
        } else if (data['purchaseDate'] != null) {
          final v = data['purchaseDate'];
          if (v is Timestamp) {
            effectiveDate = v.toDate();
          } else {
            try {
              effectiveDate = DateTime.parse(v.toString());
            } catch (_) {}
          }
        }

        // Skip if no date or not within selected year
        if (effectiveDate == null || effectiveDate.year != selectedYear) continue;

        // Normalize and count unique plan names (always add, never remove)
        final planName = (data['Plan_Category'] ?? data['planName'] ?? '').toString().trim();
        if (planName.isEmpty) continue;
        
        // ✅ ALWAYS add to unique plans - never remove even if cancelled/completed
        uniquePlanNames.add(planName.toLowerCase());

        // Add plan revenue (only for completed payments)
        final num price = data['price'] ?? data['plan_price'] ?? 0;
        planRevenue += price.toDouble();
      }

      // ✅ Fetch completed subscriptions for revenue
      final subSnapshot = await FirebaseFirestore.instance
          .collection('client_subscriptions')
          .where('paymentStatus', whereIn: ['completed', 'COMPLETED'])
          .get();

      for (var doc in subSnapshot.docs) {
        final data = doc.data();

        DateTime? effectiveDate;
        if (data['createdAt'] != null) {
          effectiveDate = (data['createdAt'] as Timestamp).toDate();
        } else if (data['purchaseDate'] != null) {
          final v = data['purchaseDate'];
          if (v is Timestamp) {
            effectiveDate = v.toDate();
          } else {
            try {
              effectiveDate = DateTime.parse(v.toString());
            } catch (_) {}
          }
        }

        if (effectiveDate == null || effectiveDate.year != selectedYear) continue;

        final num price = data['price'] ?? 0;
        subscriptionRevenue += price.toDouble();
      }

      // ✅ Fetch total booked slots (not cancelled)
      final slotSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: yearStart)
          .where('date', isLessThan: yearEnd)
          .get();

      for (var doc in slotSnapshot.docs) {
        final data = doc.data();
        final booked = List<String>.from(data['booked_by'] ?? []);
        if (booked.isEmpty) continue;

        final statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
        for (String clientId in booked) {
          String status = statusByUser[clientId] ?? data['status'] ?? 'Confirmed';
          if (status.toLowerCase() != 'cancelled') {
            slots++;
          }
        }
      }

      final totalRevenueCombined = planRevenue + subscriptionRevenue;

      if (!mounted) return;
      setState(() {
        totalPlans = uniquePlanNames.length; // ✅ Unique plan names only (never decreases)
        totalRevenue = totalRevenueCombined; // ✅ Plans + Subscriptions
        totalSlots = slots;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  bool _isWithinDateRange(DateTime now, dynamic start, dynamic end) {
    DateTime? s, e;
    if (start is Timestamp) s = start.toDate();
    if (end is Timestamp) e = end.toDate();
    final afterStart = (s == null) || !now.isBefore(s);
    final beforeEnd  = (e == null) || !now.isAfter(e);
    return afterStart && beforeEnd;
  }

  bool _isPlanActive(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status != 'active') return false;

    final now = DateTime.now();
    return _isWithinDateRange(now, data['startDate'], data['endDate']);
  }

  bool _isSubscriptionActive(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status != 'active') return false;

    final isActiveFlag = data['isActive'] == true;
    if (!isActiveFlag) return false;

    final endDate = data['endDate'];
    if (endDate == null) return true;

    DateTime? end;
    if (endDate is Timestamp) {
      end = endDate.toDate();
    } else if (endDate is String) {
      end = DateTime.tryParse(endDate);
    }

    return end == null || end.isAfter(DateTime.now());
  }


  Future<void> _exportPdfReport() async {
    setState(() {
      isLoading = true;
    });

    if (kIsWeb) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF export is not supported on web')),
      );
      return;
    }

    final pdf = pw.Document();
    final reportYear = selectedYear;
    
    // Add these variables for detailed data
    final Map<String, int> monthlyPlanCounts = {};
    final Map<String, double> monthlyPlanRevenue = {};
    final Map<String, int> monthlySubCounts = {};
    final Map<String, double> monthlySubRevenue = {};
    final Map<String, int> monthlySlots = {};
    final List<Map<String, dynamic>> yearPlanDetails = [];
    final List<Map<String, dynamic>> yearSlotDetails = [];
    final List<Map<String, dynamic>> yearSubscriptionDetails = [];
    final Set<String> yearClientIds = {};
    final Set<String> yearTrainerIds = {};
    final Set<String> yearSlotClientIds = {};
    final Set<String> yearSubClientIds = {};

    try {
      // Initialize monthly data
      for (var month in monthMap.keys) {
        monthlyPlanCounts[month] = 0;
        monthlyPlanRevenue[month] = 0.0;
        monthlySubCounts[month] = 0;
        monthlySubRevenue[month] = 0.0;
        monthlySlots[month] = 0;
      }

      // ✅ FIXED: Count ALL purchased plans (not unique)
      double yearlyPlanRevenue = 0.0;
      int totalPlanPurchases = 0; // Count ALL plans purchased in the year
      int activePlans = 0;        // Count only active (non-cancelled) plans
      
      double yearlySubRevenue = 0.0;
      int totalSubPurchases = 0;  // Count ALL subscription purchases
      int activeSubscriptions = 0; // Count only active subscriptions
      int totalSlots = 0;

      // Process plans for the selected year
      final planSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('paymentStatus', whereIn: ['completed', 'COMPLETED'])
          .get();

      for (var doc in planSnapshot.docs) {
        final data = doc.data();

        // Determine effective date
        DateTime? effectiveDate;
        if (data['completedDate'] != null) {
          effectiveDate = (data['completedDate'] as Timestamp).toDate();
        } else if (data['createdAt'] != null) {
          effectiveDate = (data['createdAt'] as Timestamp).toDate();
        } else if (data['purchaseDate'] != null) {
          final v = data['purchaseDate'];
          if (v is Timestamp) {
            effectiveDate = v.toDate();
          } else {
            try {
              effectiveDate = DateTime.parse(v.toString());
            } catch (_) {}
          }
        }

        if (effectiveDate == null || effectiveDate.year != reportYear) continue;

        final num priceNum = data['price'] ?? data['plan_price'] ?? 0;
        final planCategory = (data['Plan_Category'] ?? data['planName'] ?? '') as String;
        final clientId = data['clientId'] ?? data['client_id'] ?? data['userId'] ?? data['user_id'] ?? data['uid'] ?? '';
        final status = (data['status'] ?? '').toString().toLowerCase();
        final cancelledDate = data['cancelledDate'] as Timestamp?;
        
        // Get month name for monthly breakdown
        final monthName = DateFormat('MMM').format(effectiveDate).toUpperCase();

        // ✅ COUNT ALL PURCHASES (not unique)
        totalPlanPurchases++;
        yearlyPlanRevenue += priceNum.toDouble();
        
        // Update monthly counts
        monthlyPlanCounts[monthName] = (monthlyPlanCounts[monthName] ?? 0) + 1;
        monthlyPlanRevenue[monthName] = (monthlyPlanRevenue[monthName] ?? 0) + priceNum.toDouble();

        // Active means not cancelled and within date range
        if (_isPlanActive(data)) {
          activePlans++;
        }

        // Add to detailed data
        if (clientId.isNotEmpty) yearClientIds.add(clientId);
        
        // In the plan processing loop, modify the yearPlanDetails.add():
        final completedDateTs = data['completedDate'] as Timestamp?;
          final cancelledDateTs = data['cancelledDate'] as Timestamp?;

          yearPlanDetails.add({
            'month': monthName,
            'plan': planCategory,
            'clientId': clientId,
            'amount': priceNum,

            // 👉 IMPORTANT: use createdAt only for purchase date, NOT for completed/cancel date
            'date': (data['createdAt'] as Timestamp).toDate(),

            'status': status,
            'paymentStatus': 'completed',

            // 👉 These 2 fields are used later by PDF
            'cancelledDate': cancelledDateTs,
            'completedDate': completedDateTs,
          });
      }

      // Process subscriptions for the selected year - FIXED STATUS DETECTION
      final subSnapshot = await FirebaseFirestore.instance
          .collection('client_subscriptions')
          .where('paymentStatus', whereIn: ['completed', 'COMPLETED'])
          .get();

      for (var doc in subSnapshot.docs) {
        final data = doc.data();

        // Determine subscription start date
        DateTime? effectiveDate;
        if (data['createdAt'] != null) {
          effectiveDate = (data['createdAt'] as Timestamp).toDate();
        } else if (data['purchaseDate'] != null) {
          final v = data['purchaseDate'];
          if (v is Timestamp) {
            effectiveDate = v.toDate();
          } else {
            try {
              effectiveDate = DateTime.parse(v.toString());
            } catch (_) {}
          }
        }

        if (effectiveDate == null || effectiveDate.year != reportYear) continue;

        final num priceNum = data['price'] ?? 0;
        final String userId = data['userId'] ?? '';
        final String planName = data['planName'] ?? 'Unknown Subscription';
        final String statusRaw = (data['status'] ?? '').toString().toLowerCase();
        final bool isActiveNow = data['isActive'] == true;
        final Timestamp? cancelledDate = data['cancelledDate'] as Timestamp?;
        final dynamic endDate = data['endDate'];

        final monthName = DateFormat('MMM').format(effectiveDate).toUpperCase();

        // ✅ Count all completed subscriptions for totals
        totalSubPurchases++;
        yearlySubRevenue += priceNum.toDouble();

        monthlySubCounts[monthName] = (monthlySubCounts[monthName] ?? 0) + 1;
        monthlySubRevenue[monthName] = (monthlySubRevenue[monthName] ?? 0) + priceNum.toDouble();

        // ✅ FIXED: Proper subscription status detection
        String actualStatus = statusRaw;
        
        // Check if subscription is expired
        bool isExpired = false;
        if (endDate != null) {
          DateTime? end;
          if (endDate is Timestamp) {
            end = endDate.toDate();
          } else {
            try {
              end = DateTime.parse(endDate.toString());
            } catch (_) {}
          }
          if (end != null && end.isBefore(DateTime.now())) {
            isExpired = true;
            actualStatus = 'expired';
          }
        }

        // Check if subscription is cancelled
        final bool isCancelled = statusRaw == 'cancelled' || cancelledDate != null;
        if (isCancelled) {
          actualStatus = 'cancelled';
        }

        // ✅ FIXED: Determine if subscription is actually active
        bool isActuallyActive = isActiveNow && 
                              statusRaw == 'active' && 
                              !isCancelled && 
                              !isExpired;

        if (isActuallyActive) {
          activeSubscriptions++;
        }

        if (userId.isNotEmpty) yearSubClientIds.add(userId);

        yearSubscriptionDetails.add({
          'month': monthName,
          'plan': planName,
          'clientId': userId,
          'amount': priceNum,
          'date': effectiveDate,
          'status': actualStatus, // Use the corrected status
          'paymentStatus': 'completed',
          'cancelledDate': cancelledDate,
          'endDate': endDate,
        });
      }

      // Process slots for the selected year
      final yearStart = DateTime.utc(reportYear, 1, 1);
      final yearEnd = DateTime.utc(reportYear + 1, 1, 1);
      
      final slotSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: yearStart)
          .where('date', isLessThan: yearEnd)
          .get();

      for (var doc in slotSnapshot.docs) {
        final data = doc.data();
        final booked = List<String>.from(data['booked_by'] ?? []);
        if (booked.isEmpty) continue;

        DateTime slotDate;
        final dateField = data['date'];
        if (dateField is Timestamp) {
          slotDate = dateField.toDate();
        } else {
          try {
            slotDate = DateFormat('yyyy-MM-dd').parse(dateField ?? '');
          } catch (_) {
            continue;
          }
        }

        final monthName = DateFormat('MMM').format(slotDate).toUpperCase();
        final formattedDate = DateFormat('MMMM d, yyyy').format(slotDate);
        final time = data['time'] ?? '';
        final trainerId = data['trainer_id'] ?? data['trainerId'] ?? '';
        final trainerName = data['trainer_name'] ?? 'Unknown Trainer';
        if (trainerId.isNotEmpty) yearTrainerIds.add(trainerId);

        final statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
        for (String clientId in booked) {
          String status = statusByUser[clientId] ?? data['status'] ?? 'Confirmed';
          if (clientId.isNotEmpty) yearSlotClientIds.add(clientId);
          
          yearSlotDetails.add({
            'month': monthName,
            'date': formattedDate,
            'time': time,
            'clientId': clientId,
            'trainerId': trainerId,
            'trainer': trainerName,
            'status': status,
          });
          
          if (status.toLowerCase() != 'cancelled') {
            totalSlots++;
            monthlySlots[monthName] = (monthlySlots[monthName] ?? 0) + 1;
          }
        }
      }

      final totalRevenueYearly = yearlyPlanRevenue + yearlySubRevenue;
      final totalPlansAndSubs = totalPlanPurchases + totalSubPurchases;

      // Fetch user names for detailed reports
      final Map<String, String> userNames = await _fetchUserNames(yearClientIds);
      for (var detail in yearPlanDetails) {
        detail['client'] = userNames[detail['clientId']] ?? 'Unknown Client';
      }

      final Map<String, String> slotClientNames = await _fetchUserNames(yearSlotClientIds);
      final Map<String, String> trainerNames = await _fetchUserNames(yearTrainerIds);
      for (var detail in yearSlotDetails) {
        detail['client'] = slotClientNames[detail['clientId']] ?? 'Unknown Client';
        detail['trainer'] = trainerNames[detail['trainerId']] ?? detail['trainer'];
      }

      final Map<String, String> subUserNames = await _fetchUserNames(yearSubClientIds);
      for (var detail in yearSubscriptionDetails) {
        detail['client'] = subUserNames[detail['clientId']] ?? 'Unknown Client';
      }

      // Sort details
      yearPlanDetails.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      yearSubscriptionDetails.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      yearSlotDetails.sort((a, b) {
        final dateCompare = DateFormat('MMMM d, yyyy')
            .parse(a['date'])
            .compareTo(DateFormat('MMMM d, yyyy').parse(b['date']));
        if (dateCompare != 0) return dateCompare;
        return a['time'].compareTo(b['time']);
      });

      // ✅ FIXED: PDF generation with correct counts and proper column widths
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
          build: (context) => [
            pw.Center(
              child: pw.Text(
                "Flex Facility App - Revenue Report",
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text("Year: $reportYear", style: const pw.TextStyle(fontSize: 22)),
            pw.Text(
              "Generated on: ${DateFormat('MMMM d, yyyy').format(DateTime.now())}",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              "1. Yearly Summary",
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            pw.Bullet(
              text: "Total Plan Purchases: $totalPlanPurchases",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Active Plans: $activePlans",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Subscription Purchases: $totalSubPurchases",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Active Subscriptions: $activeSubscriptions",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Plans & Subscriptions: $totalPlansAndSubs",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Plan Revenue: \$${yearlyPlanRevenue.toStringAsFixed(2)}",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Subscription Revenue: \$${yearlySubRevenue.toStringAsFixed(2)}",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Revenue: \$${totalRevenueYearly.toStringAsFixed(2)}",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Slots Booked: $totalSlots",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              "2. Monthly Breakdown",
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Month', 'Plan Purchases', 'Subscription Purchases', 'Slots', 'Plan Revenue', 'Subscription Revenue', 'Total Revenue'],
              headerStyle: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 16),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FixedColumnWidth(70),
                1: const pw.FixedColumnWidth(100),
                2: const pw.FixedColumnWidth(130),
                3: const pw.FixedColumnWidth(70),
                4: const pw.FixedColumnWidth(100),
                5: const pw.FixedColumnWidth(120),
                6: const pw.FixedColumnWidth(100),
              },
              data: monthMap.keys.map((month) {
                final planCount = monthlyPlanCounts[month] ?? 0;
                final subCount = monthlySubCounts[month] ?? 0;
                final slotsCount = monthlySlots[month] ?? 0;
                final planRev = monthlyPlanRevenue[month] ?? 0.0;
                final subRev = monthlySubRevenue[month] ?? 0.0;
                final totalMonthRev = planRev + subRev;
                
                return [
                  month,
                  planCount.toString(),
                  subCount.toString(),
                  slotsCount.toString(),
                  '\$${planRev.toStringAsFixed(2)}',
                  '\$${subRev.toStringAsFixed(2)}',
                  '\$${totalMonthRev.toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
          ],
        ),
      );

      // Add detailed plan purchases pages with improved column widths and cancelled dates
      if (yearPlanDetails.isNotEmpty) {
        const int pageSize = 40;
        for (int i = 0; i < yearPlanDetails.length; i += pageSize) {
          final endIndex = (i + pageSize < yearPlanDetails.length) ? i + pageSize : yearPlanDetails.length;
          final pageData = yearPlanDetails.sublist(i, endIndex);
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
              build: (context) => [
                pw.Text(
                  "3. Detailed Plan Purchases (${i + 1}-$endIndex of ${yearPlanDetails.length})",
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 15),
                pw.Table.fromTextArray(
                  headers: ['Month', 'Plan Category', 'Client', 'Amount', 'Purchase Date', 'Status', 'Cancelled/Completed Date', 'Payment Status'],
                  headerStyle: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 14),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(50),  // Month
                    1: const pw.FixedColumnWidth(100), // Plan Category
                    2: const pw.FixedColumnWidth(80),  // Client
                    3: const pw.FixedColumnWidth(70),  // Amount
                    4: const pw.FixedColumnWidth(90),  // Purchase Date
                    5: const pw.FixedColumnWidth(60),  // Status
                    6: const pw.FixedColumnWidth(110),  // Cancelled/Completed Date,  // Status Date (NEW: shows cancelled/completed date)
                    7: const pw.FixedColumnWidth(80),  // Payment Status
                  },
                  data: pageData.map((detail) {
                    final purchaseDateStr = DateFormat('MMM d, yyyy').format(detail['date'] as DateTime);
                    final status = (detail['status'] as String).toLowerCase();
                    
                    // Determine which date to show based on status
                    String statusDateStr = '';
                    if (status == 'cancelled' && detail['cancelledDate'] != null) {
                      statusDateStr = DateFormat('MMM d, yyyy').format((detail['cancelledDate'] as Timestamp).toDate());
                    } else if (status == 'completed' && detail['completedDate'] != null) {
                      statusDateStr = DateFormat('MMM d, yyyy').format((detail['completedDate'] as Timestamp).toDate());
                    }

                    // For 'active' status or any other status without dates, leave blank
                    
                    return [
                      detail['month'],
                      detail['plan'],
                      detail['client'],
                      '\$${(detail['amount'] as num).toStringAsFixed(2)}',
                      purchaseDateStr,
                      detail['status'],
                      statusDateStr, // Shows date only if status is cancelled/completed
                      detail['paymentStatus'],
                    ];
                  }).toList(),
                ),
              ],
            ),
          );
        }
      } else {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
            build: (context) => pw.Center(
              child: pw.Text(
                "3. Detailed Plan Purchases - No data available.",
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
      }

      // Add detailed subscription purchases pages with improved column widths and FIXED status
      if (yearSubscriptionDetails.isNotEmpty) {
        const int pageSize = 40;
        for (int i = 0; i < yearSubscriptionDetails.length; i += pageSize) {
          final endIndex = (i + pageSize < yearSubscriptionDetails.length) ? i + pageSize : yearSubscriptionDetails.length;
          final pageData = yearSubscriptionDetails.sublist(i, endIndex);
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
              build: (context) => [
                pw.Text(
                  "4. Detailed Subscription Purchases (${i + 1}-$endIndex of ${yearSubscriptionDetails.length})",
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 15),
                pw.Table.fromTextArray(
                  headers: ['Month', 'Plan', 'Client', 'Amount', 'Date', 'Status', 'Payment Status', 'End Date'],
                  headerStyle: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 14),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(50),  // Month
                    1: const pw.FixedColumnWidth(100), // Plan
                    2: const pw.FixedColumnWidth(80),  // Client
                    3: const pw.FixedColumnWidth(70),  // Amount
                    4: const pw.FixedColumnWidth(90),  // Date
                    5: const pw.FixedColumnWidth(60),  // Status
                    6: const pw.FixedColumnWidth(80),  // Payment Status
                    7: const pw.FixedColumnWidth(90),  // End Date
                  },
                  data: pageData.map((detail) {
                    final dateStr = DateFormat('MMM d, yyyy').format(detail['date'] as DateTime);
                    final endDate = detail['endDate'];
                    String endDateStr = 'N/A';
                    
                    if (endDate != null) {
                      if (endDate is Timestamp) {
                        endDateStr = DateFormat('MMM d, yyyy').format(endDate.toDate());
                      } else {
                        try {
                          final parsedEndDate = DateTime.parse(endDate.toString());
                          endDateStr = DateFormat('MMM d, yyyy').format(parsedEndDate);
                        } catch (_) {
                          endDateStr = 'Invalid';
                        }
                      }
                    }
                    
                    return [
                      detail['month'],
                      detail['plan'],
                      detail['client'],
                      '\$${(detail['amount'] as num).toStringAsFixed(2)}',
                      dateStr,
                      detail['status'], // This now shows 'expired' correctly
                      detail['paymentStatus'],
                      endDateStr,
                    ];
                  }).toList(),
                ),
              ],
            ),
          );
        }
      } else {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
            build: (context) => pw.Center(
              child: pw.Text(
                "4. Detailed Subscription Purchases - No data available.",
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
      }

      // Add detailed slot bookings pages
      if (yearSlotDetails.isNotEmpty) {
        const int pageSize = 40;
        for (int i = 0; i < yearSlotDetails.length; i += pageSize) {
          final endIndex = (i + pageSize < yearSlotDetails.length) ? i + pageSize : yearSlotDetails.length;
          final pageData = yearSlotDetails.sublist(i, endIndex);
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
              build: (context) => [
                pw.Text(
                  "5. Detailed Slot Bookings (${i + 1}-$endIndex of ${yearSlotDetails.length})",
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 15),
                pw.Table.fromTextArray(
                  headers: ['Month', 'Date', 'Time', 'Client', 'Trainer', 'Status'],
                  headerStyle: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 14),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(50),  // Month
                    1: const pw.FixedColumnWidth(90),  // Date
                    2: const pw.FixedColumnWidth(70),  // Time
                    3: const pw.FixedColumnWidth(80),  // Client
                    4: const pw.FixedColumnWidth(80),  // Trainer
                    5: const pw.FixedColumnWidth(70),  // Status
                  },
                  data: pageData.map((detail) {
                    return [
                      detail['month'],
                      detail['date'],
                      detail['time'],
                      detail['client'],
                      detail['trainer'],
                      detail['status'],
                    ];
                  }).toList(),
                ),
              ],
            ),
          );
        }
      } else {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
            build: (context) => pw.Center(
              child: pw.Text(
                "5. Detailed Slot Bookings - No data available.",
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
      }

      final outputDir = await getTemporaryDirectory();
      final outputFile = io.File("${outputDir.path}/Flex_Revenue_Report_$reportYear.pdf");
      await outputFile.writeAsBytes(await pdf.save());
      await OpenFile.open(outputFile.path);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF exported successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Revenue Report", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, size: 28),
            onPressed: isLoading ? null : _exportPdfReport,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: _buildSummaryCard("Plans Purchased", totalPlans.toString(), accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard("Slots Booked", totalSlots.toString(), primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard("Total Revenue", '\$${totalRevenue.toStringAsFixed(2)}', highlightColor, valueFontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.0,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: monthMap.keys.map((month) {
                return GestureDetector(
                  onTap: () => _navigateToMonthReport(month),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selectedMonth == month
                          ? highlightColor.withOpacity(0.8)
                          : monthColors[month],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      month,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: selectedMonth == month ? Colors.white : textColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_left, size: 32),
                  onPressed: () {
                    setState(() {
                      startRangeYear -= 5;
                    });
                  },
                ),
                Text(
                  "Select Year",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_right, size: 32),
                  onPressed: () {
                    setState(() {
                      startRangeYear += 5;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onHorizontalDragEnd: (DragEndDetails details) {
                double velocity = details.primaryVelocity ?? 0;
                if (velocity > 300) {
                  setState(() {
                    startRangeYear -= 5;
                  });
                } else if (velocity < -300) {
                  setState(() {
                    startRangeYear += 5;
                  });
                }
              },
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.0,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: List.generate(6, (index) {
                  int year = startRangeYear + index;
                  bool isSelected = selectedYear == year;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedYear = year;
                        _startYearlySummaryStreams();
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? highlightColor.withOpacity(0.8) : cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        year.toString(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : textColor,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),
            if (isLoading) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color, {double? valueFontSize}) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: valueFontSize ?? 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToMonthReport(String month) {
    final monthIndex = monthMap[month]!;
    final year = selectedYear;
    final start = DateTime.utc(year, monthIndex, 1);
    final end = monthIndex < 12 ? DateTime.utc(year, monthIndex + 1, 1) : DateTime.utc(year + 1, 1, 1);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonthlyReportScreen(
          monthName: month,
          fullMonthName: DateFormat('MMMM').format(start),
          start: start,
          end: end,
          primaryColor: primaryColor,
          highlightColor: highlightColor,
          cardColor: cardColor,
          textColor: textColor,
        ),
      ),
    );
  }
}

class MonthlyReportScreen extends StatefulWidget {
  final String monthName;
  final String fullMonthName;
  final DateTime start;
  final DateTime end;
  final Color primaryColor;
  final Color highlightColor;
  final Color cardColor;
  final Color textColor;

  const MonthlyReportScreen({
    super.key,
    required this.monthName,
    required this.fullMonthName,
    required this.start,
    required this.end,
    required this.primaryColor,
    required this.highlightColor,
    required this.cardColor,
    required this.textColor,
  });

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  int plans = 0;
  int slots = 0;
  int cancelledSlots = 0;
  int totalCreatedSlots = 0;
  int availableSlots = 0;
  double revenue = 0.0;
  double subscriptionRevenue = 0.0;
  bool loading = true;
  List<Map<String, dynamic>> planDetails = [];
  List<Map<String, dynamic>> slotDetails = [];
  List<Map<String, dynamic>> revenueDetails = [];
  List<Map<String, dynamic>> subscriptionRevenueDetails = [];
  List<Map<String, dynamic>> pdfSubscriptionDetails = [];
  int pdfSubscriptionCount = 0;

  StreamSubscription<QuerySnapshot>? _planSub;
  StreamSubscription<QuerySnapshot>? _slotSub;
  StreamSubscription<QuerySnapshot>? _subscriptionSub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    _planSub = FirebaseFirestore.instance
      .collection('client_purchases')
      .where('paymentStatus', whereIn: ['completed', 'COMPLETED'])
      .snapshots()
      .listen((snapshot) async {
    double newRevenue = 0.0;
    List<Map<String, dynamic>> newPlanDetails = [];
    List<Map<String, dynamic>> newRevenueDetails = [];
    Set<String> userIds = {};
    int allPlanPurchases = 0; // ✅ Always count all purchased plans
    List<Map<String, dynamic>> planDetailsWithDateTime = [];
    List<Map<String, dynamic>> revenueDetailsWithDateTime = [];

    final targetMonth = widget.start.month;
    final targetYear = widget.start.year;

    for (var doc in snapshot.docs) {
      final data = doc.data();

      // ✅ Determine effective purchase date
      DateTime? effectiveDate;
      if (data['completedDate'] != null) {
        effectiveDate = (data['completedDate'] as Timestamp).toDate();
      } else if (data['createdAt'] != null) {
        effectiveDate = (data['createdAt'] as Timestamp).toDate();
      } else if (data['purchaseDate'] != null) {
        final v = data['purchaseDate'];
        if (v is Timestamp) {
          effectiveDate = v.toDate();
        } else {
          try {
            effectiveDate = DateTime.parse(v.toString());
          } catch (_) {}
        }
      }

      if (effectiveDate == null) continue;

      // ✅ Only include purchases within selected month/year
      if (effectiveDate.month != targetMonth || effectiveDate.year != targetYear) {
        continue;
      }

      final planCategory = (data['Plan_Category'] ?? data['planName'] ?? '') as String;
      final clientId = data['clientId'] ?? data['client_id'] ?? data['userId'] ?? data['user_id'] ?? data['uid'] ?? '';
      final statusRaw = (data['status']?.toString().toLowerCase() ?? '');
      final cancelledDate = data['cancelledDate'] as Timestamp?;
      final price = (data['price'] ?? data['plan_price'] ?? 0) as num;

      // ✅ Always count the plan (no matter status)
      allPlanPurchases++;

      // ✅ Add price to revenue (including cancelled or completed)
      newRevenue += price.toDouble();

      if (clientId.isNotEmpty) userIds.add(clientId);

      // ✅ Normalize display status
      String displayStatus = statusRaw.isEmpty ? 'active' : statusRaw;
      if (cancelledDate != null && displayStatus != 'cancelled') {
        displayStatus = 'cancelled';
      }

      // ✅ Add to detailed list
      planDetailsWithDateTime.add({
        'plan': planCategory,
        'clientId': clientId,
        'date': effectiveDate,
        'status': displayStatus,
        'cancelledDate': cancelledDate?.toDate(),
      });

      revenueDetailsWithDateTime.add({
        'plan': planCategory,
        'clientId': clientId,
        'amount': price,
        'date': effectiveDate,
        'status': displayStatus,
        'paymentStatus': 'completed',
        'cancelledDate': cancelledDate?.toDate(),
      });
    }

    // ✅ Sort by newest first
    planDetailsWithDateTime.sort((a, b) => b['date'].compareTo(a['date']));
    revenueDetailsWithDateTime.sort((a, b) => b['date'].compareTo(a['date']));

    // ✅ Format for display
    newPlanDetails = planDetailsWithDateTime.map((detail) {
      return {
        'plan': detail['plan'],
        'clientId': detail['clientId'],
        'date': DateFormat('MMMM d, yyyy').format(detail['date']),
        'status': detail['status'],
        'cancelledDate': detail['cancelledDate'] != null
            ? DateFormat('MMMM d, yyyy').format(detail['cancelledDate'])
            : null,
      };
    }).toList();

    newRevenueDetails = revenueDetailsWithDateTime.map((detail) {
      return {
        'plan': detail['plan'],
        'clientId': detail['clientId'],
        'amount': detail['amount'],
        'date': DateFormat('MMMM d, yyyy').format(detail['date']),
        'status': detail['status'],
        'paymentStatus': detail['paymentStatus'],
        'cancelledDate': detail['cancelledDate'] != null
            ? DateFormat('MMMM d, yyyy').format(detail['cancelledDate'])
            : null,
      };
    }).toList();

    // ✅ Fetch client names
    Map<String, String> userNames = await _fetchUserNames(userIds);
    for (var detail in newPlanDetails) {
      detail['client'] = userNames[detail['clientId']] ?? 'Unknown Client';
    }
    for (var detail in newRevenueDetails) {
      detail['client'] = userNames[detail['clientId']] ?? 'Unknown Client';
    }

    if (mounted) {
      setState(() {
        plans = allPlanPurchases; // ✅ Always reflect total purchases (never decrease)
        revenue = newRevenue;
        planDetails = newPlanDetails;
        revenueDetails = newRevenueDetails;
        loading = false;
      });
    }
  });


    _slotSub = FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('date', isGreaterThanOrEqualTo: widget.start)
        .where('date', isLessThan: widget.end)
        .snapshots()
        .listen((snapshot) async {
      List<Map<String, dynamic>> newSlotDetails = [];
      int newSlots = 0;
      int newCancelledSlots = 0;
      int newAvailableSlots = 0;
      final int newTotalCreatedSlots = snapshot.docs.length;
      Set<String> clientIds = {};
      Set<String> trainerIds = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final booked = List<String>.from(data['booked_by'] ?? []);
        DateTime slotDate;
        final dateField = data['date'];
        if (dateField is Timestamp) {
          slotDate = dateField.toDate();
        } else {
          try {
            slotDate = DateFormat('yyyy-MM-dd').parse(dateField ?? '');
          } catch (_) {
            continue;
          }
        }

        final formattedDate = DateFormat('MMMM d, yyyy').format(slotDate);
        final time = data['time'] ?? '';
        final trainerId = data['trainer_id'] ?? data['trainerId'] ?? '';
        final trainerName = data['trainer_name'] ?? 'Unknown Trainer';
        if (trainerId.isNotEmpty) trainerIds.add(trainerId);

        final statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
        bool hasConfirmed = false;

        if (booked.isNotEmpty) {
          for (String clientId in booked) {
            if (clientId.isNotEmpty) clientIds.add(clientId);
            String status = statusByUser[clientId] ?? data['status'] ?? 'Confirmed';

            newSlotDetails.add({
              'date': formattedDate,
              'time': time,
              'clientId': clientId,
              'trainerId': trainerId,
              'trainer': trainerName,
              'status': status,
            });

            if (status.toLowerCase() != 'cancelled') {
              newSlots++;
              hasConfirmed = true;
            } else {
              newCancelledSlots++;
            }
          }
        }

        if (!hasConfirmed) {
          newAvailableSlots++;
        }
      }

      Map<String, String> userNames = await _fetchUserNames(clientIds);
      Map<String, String> trainerNamesMap = await _fetchUserNames(trainerIds);

      for (var detail in newSlotDetails) {
        detail['client'] = userNames[detail['clientId']] ?? 'Unknown User';
        detail['trainer'] = trainerNamesMap[detail['trainerId']] ?? detail['trainer'];
      }

      newSlotDetails.sort((a, b) {
        final dateCompare = DateFormat('MMMM d, yyyy')
            .parse(a['date'])
            .compareTo(DateFormat('MMMM d, yyyy').parse(b['date']));
        if (dateCompare != 0) return dateCompare;
        return a['time'].compareTo(b['time']);
      });

      if (mounted) {
        setState(() {
          slots = newSlots;
          cancelledSlots = newCancelledSlots;
          totalCreatedSlots = newTotalCreatedSlots;
          availableSlots = newAvailableSlots;
          slotDetails = newSlotDetails;
          loading = false;
        });
      }
    });

    _subscriptionSub = FirebaseFirestore.instance
      .collection('client_subscriptions')
      .where('paymentStatus', whereIn: ['completed', 'COMPLETED'])
      .snapshots()
      .listen((snapshot) async {
    double newSubscriptionRevenue = 0.0;
    List<Map<String, dynamic>> newSubscriptionRevenueDetails = [];
    List<Map<String, dynamic>> newPdfSubscriptionDetails = [];
    Set<String> subUserIds = <String>{};
    int totalSubscriptions = 0; // ✅ Count all subscriptions for the month

    final targetMonth = widget.start.month;
    final targetYear = widget.start.year;

    for (var doc in snapshot.docs) {
      final data = doc.data();

      // ✅ Determine date of purchase
      DateTime? effectiveDate;
      if (data['createdAt'] != null) {
        effectiveDate = (data['createdAt'] as Timestamp).toDate();
      } else if (data['purchaseDate'] != null) {
        final v = data['purchaseDate'];
        if (v is Timestamp) {
          effectiveDate = v.toDate();
        } else {
          try {
            effectiveDate = DateTime.parse(v.toString());
          } catch (_) {}
        }
      }

      if (effectiveDate == null) continue;

      // ✅ Only include subscriptions made in the selected month & year
      if (effectiveDate.month != targetMonth || effectiveDate.year != targetYear) {
        continue;
      }

      final num priceNum = data['price'] ?? 0;
      final String userId = data['userId'] ?? '';
      final String planName = data['planName'] ?? 'Unknown Subscription';
      final String statusRaw = (data['status'] ?? '').toString().toLowerCase();
      final bool isActive = data['isActive'] == true;
      final Timestamp? cancelledDate = data['cancelledDate'] as Timestamp?;
      final dynamic endDate = data['endDate']; // may be Timestamp or String

      // ✅ Always count the purchase (even if cancelled or expired)
      totalSubscriptions++;

      // ✅ Only add to revenue if not cancelled (expired still counts)
      final bool isCancelled = statusRaw == 'cancelled' || cancelledDate != null;
      if (!isCancelled) {
        newSubscriptionRevenue += priceNum.toDouble();
      }

      if (userId.isNotEmpty) subUserIds.add(userId);

      // ✅ Determine readable status
      String displayStatus = statusRaw.isEmpty
          ? (isActive ? 'active' : 'inactive')
          : statusRaw;

      // ✅ Expiration handling (show expired but count still included)
      if (endDate != null) {
        DateTime? end;
        if (endDate is Timestamp) {
          end = endDate.toDate();
        } else {
          try {
            end = DateTime.parse(endDate.toString());
          } catch (_) {}
        }
        if (end != null && end.isBefore(DateTime.now())) {
          displayStatus = 'expired';
        }
      }

      final String dateStr = DateFormat('MMMM d, yyyy').format(effectiveDate);

      // ✅ Add to details (for reports)
      final detail = {
        'plan': planName,
        'clientId': userId,
        'amount': priceNum,
        'date': dateStr,
        'status': displayStatus,
        'paymentStatus': 'completed',
        'cancelledDate': cancelledDate?.toDate(),
      };

      newSubscriptionRevenueDetails.add(detail);
      newPdfSubscriptionDetails.add(detail);
    }

    // ✅ Fetch user names
    final Map<String, String> subUserNames = await _fetchUserNames(subUserIds);

    for (var detail in newSubscriptionRevenueDetails) {
      detail['client'] = subUserNames[detail['clientId']] ?? 'Unknown Client';
    }
    for (var detail in newPdfSubscriptionDetails) {
      detail['client'] = subUserNames[detail['clientId']] ?? 'Unknown Client';
    }

    // ✅ Sort by date (newest first)
    newSubscriptionRevenueDetails.sort((a, b) {
      return DateFormat('MMMM d, yyyy').parse(b['date']).compareTo(DateFormat('MMMM d, yyyy').parse(a['date']));
    });
    newPdfSubscriptionDetails.sort((a, b) {
      return DateFormat('MMMM d, yyyy').parse(b['date']).compareTo(DateFormat('MMMM d, yyyy').parse(a['date']));
    });

    if (mounted) {
      setState(() {
        pdfSubscriptionCount = totalSubscriptions; // ✅ Count all purchases, including expired
        subscriptionRevenue = newSubscriptionRevenue;
        subscriptionRevenueDetails = newSubscriptionRevenueDetails;
        pdfSubscriptionDetails = newPdfSubscriptionDetails;
        loading = false;
      });
    }
  });
  }

  Future<Map<String, String>> _fetchUserNames(Set<String> ids) async {
    final Map<String, String> names = {};
    await Future.wait(ids.map((id) async {
      if (id.isNotEmpty) {
        try {
          final snap = await FirebaseFirestore.instance.collection('users').doc(id).get();
          names[id] = snap.data()?['name'] as String? ?? 'Unknown';
        } catch (_) {
          names[id] = 'Unknown';
        }
      }
    }));
    return names;
  }

  @override
  void dispose() {
    _planSub?.cancel();
    _slotSub?.cancel();
    _subscriptionSub?.cancel();
    super.dispose();
  }

  Future<void> _exportMonthlyPdf() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF export is not supported on web')),
      );
      return;
    }

    final pdf = pw.Document();
    final year = widget.start.year;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              "${widget.fullMonthName} $year Report",
              style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Text(
            "Generated on: ${DateFormat('MMMM d, yyyy').format(DateTime.now())}",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 40),
          pw.Text(
            "Monthly Summary",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          pw.Bullet(
            text: "Plan Purchases: $plans", // Total purchases in the month
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Bullet(
            text: "Plan Revenue: \$${revenue.toStringAsFixed(2)}",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Bullet(
            text: "Subscription Purchases: $pdfSubscriptionCount", // Total subscription purchases
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Bullet(
            text: "Subscription Revenue: \$${subscriptionRevenue.toStringAsFixed(2)}",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Bullet(
            text: "Slots Booked: $slots",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 40),
          pw.Text(
            "Plan Purchases Details",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (planDetails.isEmpty)
            pw.Text("No plan purchases recorded", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))
          else
            pw.Table.fromTextArray(
              headers: ['Plan Category', 'Client', 'Date', 'Status', 'Cancel Date'],
              headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 20),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.5),
              },
              data: planDetails.map((detail) {
                return [
                  detail['plan'],
                  detail['client'],
                  detail['date'],
                  detail['status'],
                  detail['cancelledDate'] ?? 'N/A',
                ];
              }).toList(),
            ),
        ],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
        build: (context) => [
          pw.Text(
            "Plan Revenue Breakdown",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (revenueDetails.isEmpty)
            pw.Text("No revenue data available", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))
          else
            pw.Table.fromTextArray(
              headers: ['Plan Category', 'Client', 'Amount', 'Date', 'Status', 'Payment Status', 'Cancel Date'],
              headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 20),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.2),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(1.2),
              },
              data: revenueDetails.map((detail) {
                return [
                  detail['plan'],
                  detail['client'],
                  '\$${detail['amount'].toStringAsFixed(2)}',
                  detail['date'],
                  detail['status'],
                  detail['paymentStatus'],
                  detail['cancelledDate'] ?? 'N/A',
                ];
              }).toList(),
            ),
        ],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
        build: (context) => [
          pw.Text(
            "Subscription Purchases Details",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (pdfSubscriptionDetails.isEmpty)
            pw.Text("No subscription purchases available", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))
          else
            pw.Table.fromTextArray(
              headers: ['Plan Category', 'Client', 'Amount', 'Date', 'Status', 'Payment Status'],
              headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 20),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.2),
                5: const pw.FlexColumnWidth(1.2),
              },
              data: pdfSubscriptionDetails.map((detail) {
                return [
                  detail['plan'],
                  detail['client'],
                  '\$${detail['amount'].toStringAsFixed(2)}',
                  detail['date'],
                  detail['status'],
                  detail['paymentStatus'],
                ];
              }).toList(),
            ),
        ],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
        build: (context) => [
          pw.Text(
            "Subscription Revenue Details",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (subscriptionRevenueDetails.isEmpty)
            pw.Text("No subscription revenue data available", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))
          else
            pw.Table.fromTextArray(
              headers: ['Plan Category', 'Client', 'Amount', 'Date', 'Status', 'Payment Status'],
              headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 20),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.2),
                5: const pw.FlexColumnWidth(1.2),
              },
              data: subscriptionRevenueDetails.map((detail) {
                return [
                  detail['plan'],
                  detail['client'],
                  '\$${detail['amount'].toStringAsFixed(2)}',
                  detail['date'],
                  detail['status'],
                  detail['paymentStatus'],
                ];
              }).toList(),
            ),
        ],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
        build: (context) => [
          pw.Text(
            "Slot Booking Details",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (slotDetails.isEmpty)
            pw.Text("No slot bookings recorded", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))
          else
            pw.Table.fromTextArray(
              headers: ['Date', 'Time', 'Client', 'Trainer', 'Status'],
              headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 20),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(2.2),
                3: const pw.FlexColumnWidth(2.2),
                4: const pw.FlexColumnWidth(1.2),
              },
              data: slotDetails.map((detail) {
                return [
                  detail['date'],
                  detail['time'],
                  detail['client'],
                  detail['trainer'],
                  detail['status'],
                ];
              }).toList(),
            ),
        ],
      ),
    );

    try {
      final outputDir = await getTemporaryDirectory();
      final outputFile = io.File("${outputDir.path}/Flex_${widget.monthName}_Report_$year.pdf");
      await outputFile.writeAsBytes(await pdf.save());
      await OpenFile.open(outputFile.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e')),
      );
    }
  }

  void _showPlanDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Plan Details - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: planDetails.isEmpty
              ? Center(child: Text("No plan purchases recorded", style: TextStyle(fontSize: 20, color: widget.textColor, fontWeight: FontWeight.bold)))
              : ListView.builder(
                  itemCount: planDetails.length,
                  itemBuilder: (context, index) {
                    final detail = planDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: ListTile(
                        title: Text(detail['plan'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${detail['client']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['status'].toLowerCase() == 'active' ? Colors.green : Colors.red,
                              ),
                            ),
                            if (detail['cancelledDate'] != null)
                              Text(
                                "Cancelled: ${detail['cancelledDate']}",
                                style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        trailing: Text(detail['date'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showRevenueDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Plan Revenue Details - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: revenueDetails.isEmpty
              ? Center(child: Text("No revenue data available", style: TextStyle(fontSize: 20, color: widget.textColor, fontWeight: FontWeight.bold)))
              : ListView.builder(
                  itemCount: revenueDetails.length,
                  itemBuilder: (context, index) {
                    final detail = revenueDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: ListTile(
                        title: Text(detail['plan'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${detail['client']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['status'].toLowerCase() == 'active' ? Colors.green : (detail['status'].toLowerCase() == 'cancelled' ? Colors.red : Colors.black),
                              ),
                            ),
                            Text(
                              "Payment: ${detail['paymentStatus']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['paymentStatus'].toLowerCase() == 'completed' ? Colors.green : Colors.orange,
                              ),
                            ),
                            if (detail['cancelledDate'] != null)
                              Text(
                                "Cancelled: ${detail['cancelledDate']}",
                                style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${detail['amount'].toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(detail['date'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showPdfSubscriptionDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Subscription Purchases - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: pdfSubscriptionDetails.isEmpty
              ? Center(child: Text("No subscription purchases available", style: TextStyle(fontSize: 20, color: widget.textColor, fontWeight: FontWeight.bold)))
              : ListView.builder(
                  itemCount: pdfSubscriptionDetails.length,
                  itemBuilder: (context, index) {
                    final detail = pdfSubscriptionDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: ListTile(
                        title: Text(detail['plan'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${detail['client']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['status'].toLowerCase() == 'active' 
                                    ? Colors.green 
                                    : (detail['status'].toLowerCase() == 'cancelled' || detail['status'].toLowerCase() == 'expired' 
                                        ? Colors.red 
                                        : Colors.black),
                              ),
                            ),
                            Text(
                              "Payment: ${detail['paymentStatus']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['paymentStatus'].toLowerCase() == 'completed' ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${detail['amount'].toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(detail['date'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showSubscriptionRevenueDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Subscription Revenue - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: subscriptionRevenueDetails.isEmpty
              ? Center(child: Text("No subscription revenue data available", style: TextStyle(fontSize: 20, color: widget.textColor, fontWeight: FontWeight.bold)))
              : ListView.builder(
                  itemCount: subscriptionRevenueDetails.length,
                  itemBuilder: (context, index) {
                    final detail = subscriptionRevenueDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: ListTile(
                        title: Text(detail['plan'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${detail['client']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['status'].toLowerCase() == 'active' 
                                    ? Colors.green 
                                    : (detail['status'].toLowerCase() == 'cancelled' || detail['status'].toLowerCase() == 'expired' 
                                        ? Colors.red 
                                        : Colors.black),
                              ),
                            ),
                            Text(
                              "Payment: ${detail['paymentStatus']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: detail['paymentStatus'].toLowerCase() == 'completed' ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${detail['amount'].toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(detail['date'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'rescheduled':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'upcoming':
        return Colors.blue;
      default:
        return Colors.black;
    }
  }

  void _showSlotDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Slot Details - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: slotDetails.isEmpty
              ? Center(child: Text("No slot bookings recorded", style: TextStyle(fontSize: 20, color: widget.textColor, fontWeight: FontWeight.bold)))
              : ListView.builder(
                  itemCount: slotDetails.length,
                  itemBuilder: (context, index) {
                    final detail = slotDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: ListTile(
                        title: Text(
                          detail['client'],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Trainer: ${detail['trainer']}", style: const TextStyle(fontSize: 16)),
                            Text("Time: ${detail['time']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(detail['status']),
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(detail['date'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.fullMonthName} Report", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: widget.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, size: 28),
            onPressed: loading ? null : _exportMonthlyPdf,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0, left: 4.0),
                      child: Text(
                        "Plans Information",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: widget.primaryColor,
                        ),
                      ),
                    ),
                    _buildMetricCard(
                      "Plan Purchases", 
                      plans.toString(), 
                      widget.highlightColor, 
                      onTap: _showPlanDetails
                    ),
                    const SizedBox(height: 16),
                    _buildMetricCard(
                      "Slots Booked", 
                      slots.toString(), 
                      widget.primaryColor, 
                      onTap: _showSlotDetails
                    ),
                    const SizedBox(height: 16),
                    _buildMetricCard(
                      "Plan Revenue", 
                      '\$${revenue.toStringAsFixed(2)}', 
                      Colors.green, 
                      onTap: _showRevenueDetails
                    ),
                    
                    const SizedBox(height: 32),
                    
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0, left: 4.0),
                      child: Text(
                        "Subscriptions Information",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: widget.primaryColor,
                        ),
                      ),
                    ),
                    _buildMetricCard(
                      "Subscription Purchases", 
                      pdfSubscriptionCount.toString(), 
                      Colors.orange, 
                      onTap: _showPdfSubscriptionDetails
                    ),
                    const SizedBox(height: 16),
                    _buildMetricCard(
                      "Subscription Revenue", 
                      '\$${subscriptionRevenue.toStringAsFixed(2)}', 
                      Colors.purple, 
                      onTap: _showSubscriptionRevenueDetails
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: widget.textColor.withOpacity(0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: widget.textColor.withOpacity(0.5),
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}