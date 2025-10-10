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
        .where('purchaseDate', isGreaterThanOrEqualTo: yearStart)
        .where('purchaseDate', isLessThan: yearEnd)
        .snapshots()
        .listen((_) {
      _calculateTotalSummary();
    });

    _subscriptionSub = FirebaseFirestore.instance
        .collection('client_subscriptions')
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
      int activePlanCount = 0;
      int slots = 0;
      double subRevenue = 0.0;
      int activeSubscriptionCount = 0;

      final yearStart = DateTime.utc(selectedYear, 1, 1);
      final yearEnd = DateTime.utc(selectedYear + 1, 1, 1);

      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('purchaseDate', isGreaterThanOrEqualTo: yearStart)
          .where('purchaseDate', isLessThan: yearEnd)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final paymentStatus = data['paymentStatus']?.toString().toLowerCase() ?? '';
        final planCategory = (data['Plan_Category'] ?? data['planName'] ?? '') as String;
        final status = data['status']?.toString().toLowerCase() ?? '';

        if (paymentStatus == 'completed') {
          final price = (data['price'] ?? data['plan_price'] ?? 0) as num;
          planRevenue += price.toDouble();
          
          if (planCategory.trim().isNotEmpty && (status == 'active' || status == 'enabled')) {
            activePlanCount++;
          }
        }
      }

      final subSnapshot = await FirebaseFirestore.instance.collection('client_subscriptions').get();
      final nowUtc = DateTime.now().toUtc();
      for (var doc in subSnapshot.docs) {
        final data = doc.data();
        final String? purchaseDateStr = data['purchaseDate'] as String?;
        if (purchaseDateStr == null) continue;
        DateTime purchaseDate;
        try {
          purchaseDate = DateTime.parse(purchaseDateStr);
        } catch (e) {
          continue;
        }
        if (purchaseDate.year != selectedYear) continue;

        final String paymentStatusStr = (data['paymentStatus'] ?? '').toString().toLowerCase();
        final bool isActive = data['isActive'] ?? false;
        final String statusStr = (data['status'] ?? '').toString().toLowerCase();
        
        DateTime? endDateUtc;
        final dynamic endDateRaw = data['endDate'];
        if (endDateRaw is String) {
          endDateUtc = DateTime.parse(endDateRaw);
        } else if (endDateRaw is Timestamp) {
          endDateUtc = endDateRaw.toDate();
        }

        if (paymentStatusStr == 'completed' && 
            isActive && 
            statusStr == 'active' && 
            endDateUtc != null && 
            nowUtc.isBefore(endDateUtc)) {
          final num priceNum = data['price'] ?? 0;
          subRevenue += priceNum.toDouble();
          activeSubscriptionCount++;
        }
      }

      double totalRev = planRevenue + subRevenue;

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

      if (!mounted) return;
      setState(() {
        totalRevenue = totalRev;
        totalPlans = activePlanCount + activeSubscriptionCount;
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
    final planCountByName = <String, int>{};
    final categoryOriginal = <String, String>{};
    int yearlyPlans = 0;
    int yearlyActivePlans = 0;
    double yearlyPlanRevenue = 0.0;
    double yearlySubRevenue = 0.0;
    int totalActiveSubs = 0;
    int totalSlots = 0;
    final monthlyData = <String, Map<String, dynamic>>{};
    final List<Map<String, dynamic>> yearPlanDetails = [];
    final List<Map<String, dynamic>> yearSlotDetails = [];
    final List<Map<String, dynamic>> yearSubscriptionDetails = [];
    final Set<String> yearClientIds = {};
    final Set<String> yearTrainerIds = {};
    final Set<String> yearSlotClientIds = {};
    final Set<String> yearSubClientIds = {};

    try {
      final subSnapshot = await FirebaseFirestore.instance.collection('client_subscriptions').get();
      final List<Map<String, dynamic>> allSubs = subSnapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
      final nowUtc = DateTime.now().toUtc();

      for (var entry in monthMap.entries) {
        final monthName = entry.key;
        final monthIndex = entry.value;
        final monthStart = DateTime.utc(reportYear, monthIndex, 1);
        final monthEnd = monthIndex < 12 ? DateTime.utc(reportYear, monthIndex + 1, 1) : DateTime.utc(reportYear + 1, 1, 1);

        final planSnapshot = await FirebaseFirestore.instance
            .collection('client_purchases')
            .where('purchaseDate', isGreaterThanOrEqualTo: monthStart)
            .where('purchaseDate', isLessThan: monthEnd)
            .get();

        final slotSnapshot = await FirebaseFirestore.instance
            .collection('trainer_slots')
            .where('date', isGreaterThanOrEqualTo: monthStart)
            .where('date', isLessThan: monthEnd)
            .get();

        double monthPlanRevenue = 0.0;
        int monthPlans = 0;
        int monthActivePlans = 0;
        int monthSlots = 0;
        Set<String> monthUniquePlans = {};
        double monthSubRevenue = 0.0;
        int monthActiveSubs = 0;

        for (var doc in planSnapshot.docs) {
          final data = doc.data();
          final paymentStatus = data['paymentStatus']?.toString().toLowerCase() ?? '';
          final status = data['status']?.toString().toLowerCase() ?? '';
          final planCategory = (data['Plan_Category'] ?? data['planName'] ?? '') as String;
          final normCategory = planCategory.trim().toLowerCase();
          final clientId = data['clientId'] ?? data['client_id'] ?? data['userId'] ?? data['user_id'] ?? data['uid'] ?? '';
          final purchaseDate = data['purchaseDate'] as Timestamp? ?? Timestamp.now();
          final cancelledDate = data['cancelledDate'] as Timestamp?;

          if (paymentStatus == 'completed') {
            final price = (data['price'] ?? data['plan_price'] ?? 0) as num;
            monthPlanRevenue += price.toDouble();
            yearClientIds.add(clientId);
            yearPlanDetails.add({
              'month': monthName,
              'plan': planCategory,
              'clientId': clientId,
              'amount': price,
              'date': purchaseDate,
              'status': status,
              'paymentStatus': paymentStatus,
              'cancelledDate': cancelledDate,
            });
            
            if (planCategory.trim().isNotEmpty && (status == 'active' || status == 'enabled')) {
              monthActivePlans++;
              monthUniquePlans.add(normCategory);
              if (!categoryOriginal.containsKey(normCategory)) {
                categoryOriginal[normCategory] = planCategory.trim();
              }
              planCountByName[normCategory] = (planCountByName[normCategory] ?? 0) + 1;
            }
          }
        }

        monthPlans = monthUniquePlans.length;

        for (var subData in allSubs) {
          final String? purchaseDateStr = subData['purchaseDate'] as String?;
          if (purchaseDateStr == null) continue;
          DateTime purchaseDate;
          try {
            purchaseDate = DateTime.parse(purchaseDateStr);
          } catch (e) {
            continue;
          }
          if (purchaseDate.year != reportYear || purchaseDate.month != monthIndex) continue;

          final String paymentStatusStr = (subData['paymentStatus'] ?? '').toString().toLowerCase();
          final bool isActive = subData['isActive'] ?? false;
          final String statusStr = (subData['status'] ?? '').toString().toLowerCase();
          
          DateTime? endDateUtc;
          final dynamic endDateRaw = subData['endDate'];
          if (endDateRaw is String) {
            endDateUtc = DateTime.parse(endDateRaw);
          } else if (endDateRaw is Timestamp) {
            endDateUtc = endDateRaw.toDate();
          }

          final String userId = subData['userId'] ?? '';
          if (paymentStatusStr == 'completed' && 
              isActive && 
              statusStr == 'active' && 
              endDateUtc != null && 
              nowUtc.isBefore(endDateUtc)) {
            final num priceNum = subData['price'] ?? 0;
            monthSubRevenue += priceNum.toDouble();
            monthActiveSubs++;
            yearSubClientIds.add(userId);
            yearSubscriptionDetails.add({
              'month': monthName,
              'plan': subData['planName'] ?? 'Subscription',
              'clientId': userId,
              'amount': priceNum,
              'date': purchaseDate,
              'status': statusStr,
              'paymentStatus': paymentStatusStr,
              'cancelledDate': null,
            });
          }
        }

        yearlyPlanRevenue += monthPlanRevenue;
        yearlySubRevenue += monthSubRevenue;
        yearlyActivePlans += monthActivePlans;
        totalActiveSubs += monthActiveSubs;

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

          final formattedDate = DateFormat('dd MMM yyyy').format(slotDate);
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
              monthSlots++;
            }
          }
        }

        monthlyData[monthName] = {
          'plans': monthActivePlans,
          'planRevenue': monthPlanRevenue,
          'subRevenue': monthSubRevenue,
          'slots': monthSlots,
        };

        totalSlots += monthSlots;
      }

      yearlyPlans = yearlyActivePlans + totalActiveSubs;

      final Map<String, String> userNames = await _fetchUserNames(yearClientIds);
      for (var detail in yearPlanDetails) {
        detail['client'] = userNames[detail['clientId']] ?? 'Unknown Client';
      }
      yearPlanDetails.sort((a, b) => a['date'].compareTo(b['date']));

      final Map<String, String> slotClientNames = await _fetchUserNames(yearSlotClientIds);
      final Map<String, String> trainerNames = await _fetchUserNames(yearTrainerIds);
      for (var detail in yearSlotDetails) {
        detail['client'] = slotClientNames[detail['clientId']] ?? 'Unknown Client';
        detail['trainer'] = trainerNames[detail['trainerId']] ?? detail['trainer'];
      }
      yearSlotDetails.sort((a, b) {
        final dateCompare = DateFormat('dd MMM yyyy')
            .parse(a['date'])
            .compareTo(DateFormat('dd MMM yyyy').parse(b['date']));
        if (dateCompare != 0) return dateCompare;
        return a['time'].compareTo(b['time']);
      });

      final Map<String, String> subUserNames = await _fetchUserNames(yearSubClientIds);
      for (var detail in yearSubscriptionDetails) {
        detail['client'] = subUserNames[detail['clientId']] ?? 'Unknown Client';
      }
      yearSubscriptionDetails.sort((a, b) => a['date'].compareTo(b['date']));

      final topPlans = planCountByName.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

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
            pw.Text(
              "Year: $reportYear",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Text(
              "Generated on: ${DateFormat('dd MMM yyyy').format(DateTime.now())}",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              "1. Yearly Summary",
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            pw.Bullet(
              text: "Total Active Plans: $yearlyActivePlans",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Active Subscriptions: $totalActiveSubs",
              style: const pw.TextStyle(fontSize: 22),
            ),
            pw.Bullet(
              text: "Total Plans & Subscriptions: $yearlyPlans",
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
              text: "Total Revenue: \$${(yearlyPlanRevenue + yearlySubRevenue).toStringAsFixed(2)}",
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
              headers: ['Month', 'Active Plans', 'Slots', 'Plan Revenue', 'Sub Revenue', 'Total Revenue'],
              headerStyle: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 16),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FixedColumnWidth(80),
                1: const pw.FixedColumnWidth(100),
                2: const pw.FixedColumnWidth(60),
                3: const pw.FixedColumnWidth(90),
                4: const pw.FixedColumnWidth(90),
                5: const pw.FixedColumnWidth(100),
              },
              data: monthMap.keys.map((month) {
                final m = monthlyData[month]!;
                final totalMonthRev = (m['planRevenue'] as double) + (m['subRevenue'] as double);
                return [
                  month,
                  m['plans'].toString(),
                  m['slots'].toString(),
                  '\$${(m['planRevenue'] as double).toStringAsFixed(2)}',
                  '\$${(m['subRevenue'] as double).toStringAsFixed(2)}',
                  '\$${totalMonthRev.toStringAsFixed(2)}',
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
              "3. Top Plans of the Year",
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            if (topPlans.isEmpty)
              pw.Text("No data available.", style: const pw.TextStyle(fontSize: 22))
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: topPlans.take(5).map((e) {
                  final originalName = categoryOriginal[e.key] ?? e.key;
                  return pw.Bullet(
                    text: "$originalName: ${e.value} purchases",
                    style: const pw.TextStyle(fontSize: 22),
                  );
                }).toList(),
              ),
          ],
        ),
      );

      if (yearPlanDetails.isNotEmpty) {
        const int pageSize = 50;
        for (int i = 0; i < yearPlanDetails.length; i += pageSize) {
          final endIndex = (i + pageSize < yearPlanDetails.length) ? i + pageSize : yearPlanDetails.length;
          final pageData = yearPlanDetails.sublist(i, endIndex);
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
              build: (context) => [
                pw.Text(
                  "4. Detailed Plan Purchases (${i + 1}-$endIndex of ${yearPlanDetails.length})",
                  style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 15),
                pw.Table.fromTextArray(
                  headers: ['Month', 'Plan Category', 'Client', 'Amount', 'Date', 'Status', 'Payment Status', 'Cancel Date'],
                  headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 18),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(1),
                    4: const pw.FlexColumnWidth(1),
                    5: const pw.FlexColumnWidth(1),
                    6: const pw.FlexColumnWidth(1),
                    7: const pw.FlexColumnWidth(1),
                  },
                  data: pageData.map((detail) {
                    final dateStr = DateFormat('dd MMM yyyy').format((detail['date'] as Timestamp).toDate());
                    final cancelStr = detail['cancelledDate'] != null ? DateFormat('dd MMM yyyy').format((detail['cancelledDate'] as Timestamp).toDate()) : 'N/A';
                    return [
                      detail['month'],
                      detail['plan'],
                      detail['client'],
                      '\$${ (detail['amount'] as num).toStringAsFixed(2) }',
                      dateStr,
                      detail['status'],
                      detail['paymentStatus'],
                      cancelStr,
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
                "4. Detailed Plan Purchases - No data available.",
                style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
      }

      if (yearSubscriptionDetails.isNotEmpty) {
        const int pageSize = 50;
        for (int i = 0; i < yearSubscriptionDetails.length; i += pageSize) {
          final endIndex = (i + pageSize < yearSubscriptionDetails.length) ? i + pageSize : yearSubscriptionDetails.length;
          final pageData = yearSubscriptionDetails.sublist(i, endIndex);
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
              build: (context) => [
                pw.Text(
                  "5. Detailed Subscription Purchases (${i + 1}-$endIndex of ${yearSubscriptionDetails.length})",
                  style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 15),
                pw.Table.fromTextArray(
                  headers: ['Month', 'Plan', 'Client', 'Amount', 'Date', 'Status', 'Payment Status'],
                  headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 18),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(1),
                    4: const pw.FlexColumnWidth(1),
                    5: const pw.FlexColumnWidth(1),
                    6: const pw.FlexColumnWidth(1),
                  },
                  data: pageData.map((detail) {
                    final dateStr = DateFormat('dd MMM yyyy').format(detail['date'] as DateTime);
                    return [
                      detail['month'],
                      detail['plan'],
                      detail['client'],
                      '\$${ (detail['amount'] as num).toStringAsFixed(2) }',
                      dateStr,
                      detail['status'],
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
                "5. Detailed Subscription Purchases - No data available.",
                style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
      }

      if (yearSlotDetails.isNotEmpty) {
        const int pageSize = 50;
        for (int i = 0; i < yearSlotDetails.length; i += pageSize) {
          final endIndex = (i + pageSize < yearSlotDetails.length) ? i + pageSize : yearSlotDetails.length;
          final pageData = yearSlotDetails.sublist(i, endIndex);
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
              build: (context) => [
                pw.Text(
                  "6. Detailed Slot Bookings (${i + 1}-$endIndex of ${yearSlotDetails.length})",
                  style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 15),
                pw.Table.fromTextArray(
                  headers: ['Month', 'Date', 'Time', 'Client', 'Trainer', 'Status'],
                  headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 18),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(color: PdfColors.black, width: 1),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FlexColumnWidth(2),
                    5: const pw.FlexColumnWidth(1),
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
                "6. Detailed Slot Bookings - No data available.",
                style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
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
                  child: _buildSummaryCard("Total Revenue", '\$${totalRevenue.toStringAsFixed(2)}', highlightColor),
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

  Widget _buildSummaryCard(String title, String value, Color color) {
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
                fontSize: 22, // Reduced from 26 to 22
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
                fontSize: 14, // Reduced from 16 to 14
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
  int activeSubscriptionCount = 0;

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
        .where('purchaseDate', isGreaterThanOrEqualTo: widget.start)
        .where('purchaseDate', isLessThan: widget.end)
        .snapshots()
        .listen((snapshot) async {
      double newRevenue = 0.0;
      List<Map<String, dynamic>> newPlanDetails = [];
      List<Map<String, dynamic>> newRevenueDetails = [];
      Set<String> userIds = {};
      Set<String> activeCategories = {};
      int activePlansCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final paymentStatus = data['paymentStatus']?.toString().toLowerCase() ?? '';
        final status = data['status']?.toString().toLowerCase() ?? '';
        final planCategory = (data['Plan_Category'] ?? data['planName'] ?? '') as String;
        final clientId = data['clientId'] ?? data['client_id'] ?? data['userId'] ?? data['user_id'] ?? data['uid'] ?? '';
        final purchaseDate = data['purchaseDate'] as Timestamp? ?? Timestamp.now();
        final cancelledDate = data['cancelledDate'] as Timestamp?;
        if (clientId.isNotEmpty) userIds.add(clientId);

        if (paymentStatus == 'completed') {
          final price = (data['price'] ?? data['plan_price'] ?? 0) as num;
          newRevenue += price.toDouble();

          final normCategory = planCategory.trim().toLowerCase();
          if (planCategory.trim().isNotEmpty && (status == 'active' || status == 'enabled')) {
            activeCategories.add(normCategory);
            activePlansCount++;
          }

          newPlanDetails.add({
            'plan': planCategory,
            'clientId': clientId,
            'date': DateFormat('dd MMM yyyy').format(purchaseDate.toDate()),
            'status': status,
            'cancelledDate': cancelledDate != null ? DateFormat('dd MMM yyyy').format(cancelledDate.toDate()) : null,
          });

          newRevenueDetails.add({
            'plan': planCategory,
            'clientId': clientId,
            'amount': price,
            'date': DateFormat('dd MMM yyyy').format(purchaseDate.toDate()),
            'status': status,
            'paymentStatus': paymentStatus,
            'cancelledDate': cancelledDate != null ? DateFormat('dd MMM yyyy').format(cancelledDate.toDate()) : null,
          });
        }
      }

      Map<String, String> userNames = await _fetchUserNames(userIds);
      for (var detail in newPlanDetails) {
        detail['client'] = userNames[detail['clientId']] ?? 'Unknown Client';
      }
      for (var detail in newRevenueDetails) {
        detail['client'] = userNames[detail['clientId']] ?? 'Unknown Client';
      }

      if (mounted) {
        setState(() {
          plans = activePlansCount;
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

        final formattedDate = DateFormat('dd MMM yyyy').format(slotDate);
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
        final dateCompare = DateFormat('dd MMM yyyy')
            .parse(a['date'])
            .compareTo(DateFormat('dd MMM yyyy').parse(b['date']));
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
        .snapshots()
        .listen((snapshot) async {
      double newSubscriptionRevenue = 0.0;
      List<Map<String, dynamic>> newSubscriptionRevenueDetails = [];
      Set<String> subUserIds = <String>{};
      int newActiveSubscriptionCount = 0;

      final nowUtc = DateTime.now().toUtc();
      final int targetMonth = widget.start.month;
      final int targetYear = widget.start.year;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String? purchaseDateStr = data['purchaseDate'] as String?;
        if (purchaseDateStr == null) continue;

        DateTime purchaseDate;
        try {
          purchaseDate = DateTime.parse(purchaseDateStr);
        } catch (e) {
          continue;
        }

        if (purchaseDate.month != targetMonth || purchaseDate.year != targetYear) continue;

        final String paymentStatusStr = (data['paymentStatus'] ?? '').toString().toLowerCase();
        final bool isActive = data['isActive'] ?? false;
        final String statusStr = (data['status'] ?? '').toString().toLowerCase();
        
        DateTime? endDateUtc;
        final dynamic endDateRaw = data['endDate'];
        if (endDateRaw is String) {
          endDateUtc = DateTime.parse(endDateRaw);
        } else if (endDateRaw is Timestamp) {
          endDateUtc = endDateRaw.toDate();
        }

        if (paymentStatusStr == 'completed' && 
            isActive && 
            statusStr == 'active' && 
            endDateUtc != null && 
            nowUtc.isBefore(endDateUtc)) {
          final num priceNum = data['price'] ?? 0;
          newSubscriptionRevenue += priceNum.toDouble();
          newActiveSubscriptionCount++;
          
          final String userId = data['userId'] ?? '';
          if (userId.isNotEmpty) {
            subUserIds.add(userId);
          }
          final String dateStr = DateFormat('dd MMM yyyy').format(purchaseDate);
          newSubscriptionRevenueDetails.add({
            'plan': data['planName'] ?? 'Unknown Plan',
            'clientId': userId,
            'amount': priceNum,
            'date': dateStr,
            'status': statusStr,
            'paymentStatus': paymentStatusStr,
            'cancelledDate': null,
          });
        }
      }

      final Map<String, String> subUserNames = await _fetchUserNames(subUserIds);
      for (var detail in newSubscriptionRevenueDetails) {
        detail['client'] = subUserNames[detail['clientId']] ?? 'Unknown Client';
      }

      newSubscriptionRevenueDetails.sort((a, b) {
        return DateFormat('dd MMM yyyy').parse(b['date']).compareTo(DateFormat('dd MMM yyyy').parse(a['date']));
      });

      if (mounted) {
        setState(() {
          subscriptionRevenue = newSubscriptionRevenue;
          activeSubscriptionCount = newActiveSubscriptionCount;
          subscriptionRevenueDetails = newSubscriptionRevenueDetails;
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
            "Generated on: ${DateFormat('dd MMM yyyy').format(DateTime.now())}",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 40),
          pw.Text(
            "Monthly Summary",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          pw.Bullet(
            text: "Active Plans: $plans",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Bullet(
            text: "Plan Revenue: \$${revenue.toStringAsFixed(2)}",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Bullet(
            text: "Active Subscriptions: $activeSubscriptionCount",
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
            "Active Subscriptions Details",
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (subscriptionRevenueDetails.isEmpty)
            pw.Text("No active subscriptions available", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))
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

  void _showActiveSubscriptionDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Active Subscriptions - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: subscriptionRevenueDetails.isEmpty
              ? Center(child: Text("No active subscriptions available", style: TextStyle(fontSize: 20, color: widget.textColor, fontWeight: FontWeight.bold)))
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
        title: Text("${widget.fullMonthName} Report", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), // Reduced from 22 to 20
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
                          fontSize: 22, // Reduced from 24 to 22
                          fontWeight: FontWeight.bold,
                          color: widget.primaryColor,
                        ),
                      ),
                    ),
                    _buildMetricCard(
                      "Active Plans", 
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
                          fontSize: 22, // Reduced from 24 to 22
                          fontWeight: FontWeight.bold,
                          color: widget.primaryColor,
                        ),
                      ),
                    ),
                    _buildMetricCard(
                      "Active Subscriptions", 
                      activeSubscriptionCount.toString(), 
                      Colors.orange, 
                      onTap: _showActiveSubscriptionDetails
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
        height: 110, // Reduced from 120 to 110
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
                        fontSize: 24, // Reduced from 28 to 24
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
                        fontSize: 16, // Reduced from 18 to 16
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
                size: 32, // Reduced from 36 to 32
              ),
            ],
          ),
        ),
      ),
    );
  }
}