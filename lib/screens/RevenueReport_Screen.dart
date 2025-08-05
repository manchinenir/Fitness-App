import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

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
  int totalRevenue = 0;
  bool isLoading = false;

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
    _calculateTotalSummary();
  }

  Future<void> _calculateTotalSummary() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('client_purchases').get();
      int revenue = 0;
      Set<String> uniquePlans = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final price = data['price'] ?? data['plan_price'] ?? 0;
        if (price is num) revenue += price.toInt();
        final planName = data['planTitle'] ?? data['plan_name'] ?? data['plan'] ?? data['name'] ?? '';
        if (planName is String && planName.trim().isNotEmpty) {
          uniquePlans.add(planName.trim());
        }
      }

      setState(() {
        totalRevenue = revenue;
        totalPlans = uniquePlans.length;
      });
    } catch (e) {
      print("Error calculating total summary: $e");
    }
  }

  Future<void> _exportPdfReport() async {
    final pdf = pw.Document();
    final currentYear = DateTime.now().year;
    final planCountByName = <String, int>{};
    int yearlyPlans = 0;
    double yearlyRevenue = 0;
    int totalSlots = 0;
    final monthlyData = <String, Map<String, dynamic>>{};

    for (var entry in monthMap.entries) {
      final monthName = entry.key;
      final monthIndex = entry.value;
      final start = DateTime(currentYear, monthIndex, 1);
      final end = monthIndex < 12 ? DateTime(currentYear, monthIndex + 1, 1) : DateTime(currentYear + 1, 1, 1);

      final planSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('timestamp', isGreaterThanOrEqualTo: start)
          .where('timestamp', isLessThan: end)
          .get();

      final slotSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThan: end)
          .get();

      Set<String> uniquePlans = {};
      double monthRevenue = 0;
      int monthSlots = 0;

      for (var doc in planSnapshot.docs) {
        final data = doc.data();
        final price = data['price'] ?? data['plan_price'] ?? 0;
        final planName = data['planTitle'] ?? data['plan_name'] ?? data['plan'] ?? data['name'] ?? '';
        if (price is num) monthRevenue += price.toDouble();
        if (planName is String && planName.trim().isNotEmpty) {
          uniquePlans.add(planName.trim());
          planCountByName[planName] = (planCountByName[planName] ?? 0) + 1;
        }
      }

      for (var doc in slotSnapshot.docs) {
        final booked = List<String>.from(doc['booked_by'] ?? []);
        monthSlots += booked.length;
      }

      monthlyData[monthName] = {
        'plans': uniquePlans.length,
        'revenue': monthRevenue,
        'slots': monthSlots,
      };

      yearlyPlans += uniquePlans.length;
      yearlyRevenue += monthRevenue;
      totalSlots += monthSlots;
    }

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
            "Year: $currentYear",
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
            headers: ['Month', 'Plans', 'Slots', 'Revenue'],
            headerStyle: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 20),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
            columnWidths: {
              0: const pw.FixedColumnWidth(120),
              1: const pw.FixedColumnWidth(100),
              2: const pw.FixedColumnWidth(100),
              3: const pw.FixedColumnWidth(120),
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
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Text(
                    "• ${e.key}: ${e.value} purchases",
                    style: const pw.TextStyle(fontSize: 22),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );

    try {
      final outputDir = await getTemporaryDirectory();
      final outputFile = File("${outputDir.path}/Flex_Revenue_Report_$currentYear.pdf");
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
                _buildSummaryCard("Total Plans", totalPlans.toString(), accentColor),
                _buildSummaryCard("Total Revenue", '\$${totalRevenue.toStringAsFixed(2)}', highlightColor),
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
            if (isLoading) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: textColor.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToMonthReport(String month) {
    final monthIndex = monthMap[month]!;
    final year = DateTime.now().year;
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

// -------- MonthlyReportScreen ----------

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
  double revenue = 0;
  bool loading = true;
  List<Map<String, dynamic>> planDetails = [];
  List<Map<String, dynamic>> slotDetails = [];
  List<Map<String, dynamic>> revenueDetails = [];

  @override
  void initState() {
    super.initState();
    _fetchMonthlyData();
  }

  Future<void> _fetchMonthlyData() async {
    try {
      final planSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('timestamp', isGreaterThanOrEqualTo: widget.start)
          .where('timestamp', isLessThan: widget.end)
          .get();

      Set<String> uniquePlans = {};
      revenue = 0;
      planDetails = [];
      revenueDetails = [];

      for (var doc in planSnapshot.docs) {
        final data = doc.data();
        final price = data['price'] ?? data['plan_price'] ?? 0;
        final amount = (price as num).toDouble();
        revenue += amount;

        final planName = data['planTitle'] ?? data['plan_name'] ?? data['plan'] ?? data['name'] ?? '';
        String clientName = 'Unknown Client';

        try {
          final clientId = data['clientId'] ?? data['client_id'] ?? '';
          if (clientId != null && clientId.toString().isNotEmpty) {
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(clientId.toString()).get();
            if (userDoc.exists) {
              clientName = userDoc.data()?['name'] ?? 'Unknown Client';
            }
          } else {
            clientName = data['clientName'] ?? data['client_name'] ?? 'Unknown Client';
          }
        } catch (_) {}

        if (planName is String && planName.trim().isNotEmpty) {
          uniquePlans.add(planName.trim());

          planDetails.add({
            'plan': planName,
            'client': clientName,
            'date': DateFormat('dd MMM yyyy').format(data['timestamp']?.toDate() ?? DateTime.now()),
          });

          revenueDetails.add({
            'plan': planName,
            'client': clientName,
            'amount': amount,
            'date': DateFormat('dd MMM yyyy').format(data['timestamp']?.toDate() ?? DateTime.now()),
          });
        }
      }
      plans = uniquePlans.length;

      final slotSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: widget.start)
          .where('date', isLessThan: widget.end)
          .get();

      slotDetails = [];
      slots = 0;

      for (var doc in slotSnapshot.docs) {
        final data = doc.data();
        final bookedBy = List<String>.from(data['booked_by'] ?? []);
        final timestamp = data['date'];
        DateTime slotDate;
        if (timestamp is Timestamp) {
          slotDate = timestamp.toDate();
        } else {
          try {
            slotDate = DateFormat('yyyy-MM-dd').parse(data['date'] ?? '');
          } catch (_) {
            slotDate = DateTime.now();
          }
        }
        final formattedDate = DateFormat('dd MMM yyyy').format(slotDate);
        final time = data['time'] ?? '';
        final trainerName = data['trainer_name'] ?? 'Unknown Trainer';
        final planName = data['plan_name'] ?? 'Unknown Plan';

        for (String clientId in bookedBy) {
          try {
            String userName = "Unknown User";
            if (clientId.isNotEmpty) {
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(clientId).get();
              userName = userDoc.exists ? (userDoc.data()?['name'] ?? 'Unknown User') : 'Unknown User';
            }

            slotDetails.add({
              'date': formattedDate,
              'time': time,
              'client': userName,
              'trainer': trainerName,
              'plan': planName,
            });
            slots++;
          } catch (e) {
            print("Error in fetching slot user/trainer info: $e");
          }
        }
      }

      slotDetails.sort((a, b) {
        final dateCompare = DateFormat('dd MMM yyyy')
            .parse(a['date'])
            .compareTo(DateFormat('dd MMM yyyy').parse(b['date']));
        if (dateCompare != 0) return dateCompare;
        return a['time'].compareTo(b['time']);
      });

      setState(() => loading = false);
    } catch (e) {
      print("Error loading month data: $e");
      setState(() => loading = false);
    }
  }

  Future<void> _exportMonthlyPdf() async {
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
              headers: ['Plan Name', 'Client', 'Date'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
              },
              data: planDetails.map((detail) {
                return [
                  detail['plan'],
                  detail['client'],
                  detail['date'],
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
              headers: ['Plan', 'Client', 'Amount', 'Date'],
              headerStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 18),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
              },
              data: revenueDetails.map((detail) {
                return [
                  detail['plan'],
                  detail['client'],
                  '\$${detail['amount'].toStringAsFixed(2)}',
                  detail['date'],
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
              headers: ['Date', 'Time', 'Client', 'Trainer', 'Plan'],
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
              },
              data: slotDetails.map((detail) {
                return [
                  detail['date'],
                  detail['time'],
                  detail['client'],
                  detail['trainer'],
                  detail['plan'],
                ];
              }).toList(),
            ),
        ],
      ),
    );

    try {
      final outputDir = await getTemporaryDirectory();
      final outputFile = File("${outputDir.path}/Flex_${widget.monthName}Report$year.pdf");
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
                        subtitle: Text(detail['client'], style: const TextStyle(fontSize: 16)),
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
                        subtitle: Text(detail['client'], style: const TextStyle(fontSize: 16)),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${detail['amount'].toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth * 0.9;

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
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    SizedBox(
                      width: cardWidth,
                      child: GestureDetector(
                        onTap: _showPlanDetails,
                        child: _buildMetricCard("Plans Purchased", plans.toString(), widget.highlightColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: cardWidth,
                      child: GestureDetector(
                        onTap: _showSlotDetails,
                        child: _buildMetricCard("Slots Booked", slots.toString(), widget.primaryColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: cardWidth,
                      child: GestureDetector(
                        onTap: _showRevenueDetails,
                        child: _buildMetricCard("Revenue", '\$${revenue.toStringAsFixed(2)}', Colors.green),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}