import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Conditional imports for non-web platforms
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
  int totalRevenue = 0;
  bool isLoading = false;
  late int selectedYear;
  late int currentYear;
  late int startRangeYear;

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
    currentYear = DateTime.now().year;
    selectedYear = currentYear;
    startRangeYear = currentYear - 3;
    _calculateTotalSummary();
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
    setState(() {
      isLoading = true;
    });

    try {
      int revenue = 0;
      Set<String> uniquePlanCategories = {};
      int slots = 0;

      // Fetch all client purchases for the year once
      final yearStart = DateTime(selectedYear, 1, 1);
      final yearEnd = DateTime(selectedYear + 1, 1, 1);
      final snapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('purchaseDate', isGreaterThanOrEqualTo: yearStart)
          .where('purchaseDate', isLessThan: yearEnd)
          .get();

      print('Fetched ${snapshot.docs.length} client purchase documents for year $selectedYear');

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final paymentStatus = data['paymentStatus']?.toString().toLowerCase() ?? '';
        final planCategory = (data['Plan_Category'] ?? data['planName'] ?? '') as String;
        final status = data['status']?.toString().toLowerCase() ?? '';

        print('Document ID: ${doc.id}, Plan Category: "$planCategory", Payment Status: "$paymentStatus", Status: "$status"');

        if (paymentStatus == 'completed') {
          final price = (data['price'] ?? data['plan_price'] ?? 0) as num;
          revenue += price.toInt();
          if (planCategory.trim().isNotEmpty && (status == 'active' || status == 'enabled')) {
            uniquePlanCategories.add(planCategory.trim().toLowerCase());
          }
        }
      }

      print('Unique active plan categories: ${uniquePlanCategories.length} - $uniquePlanCategories');

      // Fetch slots for the selected year
      final slotSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: yearStart)
          .where('date', isLessThan: yearEnd)
          .get();

      print('Fetched ${slotSnapshot.docs.length} trainer slot documents');

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

        final statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
        for (String clientId in booked) {
          String status = statusByUser[clientId] ?? data['status'] ?? 'Confirmed';
          if (status.toLowerCase() != 'cancelled') {
            slots++;
          }
        }
      }

      setState(() {
        totalRevenue = revenue;
        totalPlans = uniquePlanCategories.length;
        totalSlots = slots;
        isLoading = false;
      });
    } catch (e) {
      print("Error calculating total summary: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _exportPdfReport() async {
    if (kIsWeb) {
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
    double yearlyRevenue = 0;
    int totalSlots = 0;
    final monthlyData = <String, Map<String, dynamic>>{};
    final List<Map<String, dynamic>> yearPlanDetails = [];
    final List<Map<String, dynamic>> yearSlotDetails = [];
    final Set<String> yearClientIds = {};
    final Set<String> yearTrainerIds = {};
    final Set<String> yearSlotClientIds = {};

    for (var entry in monthMap.entries) {
      final monthName = entry.key;
      final monthIndex = entry.value;
      final start = DateTime(reportYear, monthIndex, 1);
      final end = monthIndex < 12 ? DateTime(reportYear, monthIndex + 1, 1) : DateTime(reportYear + 1, 1, 1);

      final planSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('purchaseDate', isGreaterThanOrEqualTo: start)
          .where('purchaseDate', isLessThan: end)
          .get();

      final slotSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThan: end)
          .get();

      double monthRevenue = 0;
      int monthPlans = 0;
      int monthSlots = 0;
      Set<String> monthUniquePlans = {};

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
          monthRevenue += price.toDouble();
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
          if (planCategory.trim().isNotEmpty) {
            monthUniquePlans.add(normCategory);
            if (!categoryOriginal.containsKey(normCategory)) {
              categoryOriginal[normCategory] = planCategory.trim();
            }
            planCountByName[normCategory] = (planCountByName[normCategory] ?? 0) + 1;
          }
        }
      }

      monthPlans = monthUniquePlans.length;

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
        final planName = data['plan_name'] ?? 'Unknown Plan';
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
            'plan': planName,
            'status': status,
          });
          if (status.toLowerCase() != 'cancelled') {
            monthSlots++;
          }
        }
      }

      monthlyData[monthName] = {
        'plans': monthPlans,
        'revenue': monthRevenue,
        'slots': monthSlots,
      };

      yearlyRevenue += monthRevenue;
      totalSlots += monthSlots;
    }

    yearlyPlans = planCountByName.length;

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
            text: "Total Plans Purchased: $yearlyPlans",
            style: const pw.TextStyle(fontSize: 22),
          ),
          pw.Bullet(
            text: "Total Revenue: \$${yearlyRevenue.toStringAsFixed(2)}",
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
            headers: ['Month', 'Plans Purchased', 'Slots', 'Revenue'],
            headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 20),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
            columnWidths: {
              0: const pw.FixedColumnWidth(100),
              1: const pw.FixedColumnWidth(100),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(100),
            },
            data: monthMap.keys.map((month) {
              final m = monthlyData[month]!;
              return [
                month,
                m['plans'].toString(),
                m['slots'].toString(),
                '\$${(m['revenue'] as double).toStringAsFixed(2)}',
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
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Text(
                    "• $originalName: ${e.value} purchases",
                    style: const pw.TextStyle(fontSize: 22),
                  ),
                );
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
            "4. Detailed Plan Purchases",
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          if (yearPlanDetails.isEmpty)
            pw.Text("No data available.", style: const pw.TextStyle(fontSize: 22))
          else
            pw.Table.fromTextArray(
              headers: ['Month', 'Plan Category', 'Client', 'Amount', 'Date', 'Status', 'Payment Status', 'Cancel Date'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
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
              data: yearPlanDetails.map((detail) {
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginTop: 1.5 * PdfPageFormat.cm),
        build: (context) => [
          pw.Text(
            "5. Detailed Slot Bookings",
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          if (yearSlotDetails.isEmpty)
            pw.Text("No data available.", style: const pw.TextStyle(fontSize: 22))
          else
            pw.Table.fromTextArray(
              headers: ['Month', 'Date', 'Time', 'Client', 'Trainer', 'Plan', 'Status'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
                5: const pw.FlexColumnWidth(2),
                6: const pw.FlexColumnWidth(1),
              },
              data: yearSlotDetails.map((detail) {
                return [
                  detail['month'],
                  detail['date'],
                  detail['time'],
                  detail['client'],
                  detail['trainer'],
                  detail['plan'],
                  detail['status'],
                ];
              }).toList(),
            ),
        ],
      ),
    );

    try {
      final outputDir = await getTemporaryDirectory();
      final outputFile = io.File("${outputDir.path}/Flex_Revenue_Report_$reportYear.pdf");
      await outputFile.writeAsBytes(await pdf.save());
      await OpenFile.open(outputFile.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Revenue Report", style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportPdfReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                  child: _buildSummaryCard("Revenue", '\$$totalRevenue', highlightColor),
                ),
              ],
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
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
                        color: selectedMonth == month ? Colors.white : textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_left),
                  onPressed: () {
                    setState(() {
                      startRangeYear -= 5;
                    });
                  },
                ),
                Text(
                  "Select Year",
                  style: TextStyle(
                    fontSize: 18,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_right),
                  onPressed: () {
                    setState(() {
                      startRangeYear += 5;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onHorizontalDragEnd: (DragEndDetails details) {
                double velocity = details.primaryVelocity ?? 0;
                if (velocity > 300) {
                  // Swipe right, go to previous range
                  setState(() {
                    startRangeYear -= 5;
                  });
                } else if (velocity < -300) {
                  // Swipe left, go to next range
                  setState(() {
                    startRangeYear += 5;
                  });
                }
              },
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: List.generate(6, (index) {
                  int year = startRangeYear + index;
                  bool isSelected = selectedYear == year;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedYear = year;
                        _calculateTotalSummary();
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
                          color: isSelected ? Colors.white : textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 32),
            if (isLoading) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Container(
      height: 120,
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
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: textColor.withOpacity(0.8),
                fontWeight: FontWeight.w600,
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
    final start = DateTime(year, monthIndex, 1);
    final end = monthIndex < 12 ? DateTime(year, monthIndex + 1, 1) : DateTime(year + 1, 1, 1);

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
  double revenue = 0;
  bool loading = true;
  List<Map<String, dynamic>> planDetails = [];
  List<Map<String, dynamic>> slotDetails = [];
  List<Map<String, dynamic>> revenueDetails = [];

  StreamSubscription<QuerySnapshot>? _planSub;
  StreamSubscription<QuerySnapshot>? _slotSub;

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
      double newRevenue = 0;
      List<Map<String, dynamic>> newPlanDetails = [];
      List<Map<String, dynamic>> newRevenueDetails = [];
      Set<String> userIds = {};
      Set<String> activeCategories = {};

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
          plans = activeCategories.isEmpty ? snapshot.docs.length : activeCategories.length;
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
        final planName = data['plan_name'] ?? 'Unknown Plan';
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
              'plan': planName,
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
      Map<String, String> trainerNames = await _fetchUserNames(trainerIds);

      for (var detail in newSlotDetails) {
        detail['client'] = userNames[detail['clientId']] ?? 'Unknown User';
        detail['trainer'] = trainerNames[detail['trainerId']] ?? detail['trainer'];
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
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            "Generated on: ${DateFormat('dd MMM yyyy').format(DateTime.now())}",
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.SizedBox(height: 30),
          pw.Text(
            "Monthly Summary",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          pw.Bullet(
            text: "Plans Purchased: $plans",
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.Bullet(
            text: "Revenue: \$${revenue.toStringAsFixed(2)}",
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.Bullet(
            text: "Slots Booked: $slots",
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.SizedBox(height: 30),
          pw.Text(
            "Plan Purchases Details",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          if (planDetails.isEmpty)
            pw.Text("No plan purchases recorded", style: const pw.TextStyle(fontSize: 18))
          else
            pw.Table.fromTextArray(
              headers: ['Plan Category', 'Client', 'Date', 'Status', 'Cancel Date'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1),
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
            "Revenue Breakdown",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          if (revenueDetails.isEmpty)
            pw.Text("No revenue data available", style: const pw.TextStyle(fontSize: 18))
          else
            pw.Table.fromTextArray(
              headers: ['Plan Category', 'Client', 'Amount', 'Date', 'Status', 'Payment Status', 'Cancel Date'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1),
                5: const pw.FlexColumnWidth(1),
                6: const pw.FlexColumnWidth(1),
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
            "Slot Booking Details",
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          if (slotDetails.isEmpty)
            pw.Text("No slot bookings recorded", style: const pw.TextStyle(fontSize: 18))
          else
            pw.Table.fromTextArray(
              headers: ['Date', 'Time', 'Client', 'Trainer', 'Plan', 'Status'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
                5: const pw.FlexColumnWidth(1),
              },
              data: slotDetails.map((detail) {
                return [
                  detail['date'],
                  detail['time'],
                  detail['client'],
                  detail['trainer'],
                  detail['plan'],
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
            title: Text("Plan Details - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: planDetails.isEmpty
              ? Center(child: Text("No plan purchases recorded", style: TextStyle(fontSize: 18, color: widget.textColor)))
              : ListView.builder(
                  itemCount: planDetails.length,
                  itemBuilder: (context, index) {
                    final detail = planDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: ListTile(
                        title: Text(detail['plan'], style: const TextStyle(fontSize: 18)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${detail['client']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                color: detail['status'].toLowerCase() == 'active' ? Colors.green : Colors.red,
                              ),
                            ),
                            if (detail['cancelledDate'] != null)
                              Text(
                                "Cancelled: ${detail['cancelledDate']}",
                                style: const TextStyle(fontSize: 16, color: Colors.red),
                              ),
                          ],
                        ),
                        trailing: Text(detail['date'], style: const TextStyle(fontSize: 16)),
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
            title: Text("Revenue Details - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: revenueDetails.isEmpty
              ? Center(child: Text("No revenue data available", style: TextStyle(fontSize: 18, color: widget.textColor)))
              : ListView.builder(
                  itemCount: revenueDetails.length,
                  itemBuilder: (context, index) {
                    final detail = revenueDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: ListTile(
                        title: Text(detail['plan'], style: const TextStyle(fontSize: 18)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${detail['client']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                color: detail['status'].toLowerCase() == 'active' ? Colors.green : (detail['status'].toLowerCase() == 'cancelled' ? Colors.red : Colors.black),
                              ),
                            ),
                            Text(
                              "Payment: ${detail['paymentStatus']}",
                              style: TextStyle(
                                fontSize: 16,
                                color: detail['paymentStatus'].toLowerCase() == 'completed' ? Colors.green : Colors.orange,
                              ),
                            ),
                            if (detail['cancelledDate'] != null)
                              Text(
                                "Cancelled: ${detail['cancelledDate']}",
                                style: const TextStyle(fontSize: 16, color: Colors.red),
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
                            Text(detail['date'], style: const TextStyle(fontSize: 16)),
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
            title: Text("Slot Details - ${widget.fullMonthName}", style: const TextStyle(color: Colors.white)),
            backgroundColor: widget.primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: slotDetails.isEmpty
              ? Center(child: Text("No slot bookings recorded", style: TextStyle(fontSize: 18, color: widget.textColor)))
              : ListView.builder(
                  itemCount: slotDetails.length,
                  itemBuilder: (context, index) {
                    final detail = slotDetails[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                            Text("Plan: ${detail['plan']}", style: const TextStyle(fontSize: 16)),
                            Text(
                              "Status: ${detail['status']}",
                              style: TextStyle(
                                fontSize: 16,
                                color: _getStatusColor(detail['status']),
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(detail['date'], style: const TextStyle(fontSize: 16)),
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
        title: Text("${widget.fullMonthName} Report", style: const TextStyle(color: Colors.white, fontSize: 20)),
        backgroundColor: widget.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportMonthlyPdf,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildMetricCard("Plans Purchased", plans.toString(), widget.highlightColor, onTap: _showPlanDetails),
                  const SizedBox(height: 16),
                  _buildMetricCard("Slots Booked", slots.toString(), widget.primaryColor, onTap: _showSlotDetails),
                  const SizedBox(height: 16),
                  _buildMetricCard("Revenue", '\$${revenue.toStringAsFixed(2)}', Colors.green, onTap: _showRevenueDetails),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
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
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: widget.textColor.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}