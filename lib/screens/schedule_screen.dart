// schedule_screen.dart
import 'package:flutter/material.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int? selectedDate;
  DateTime selectedDateTime = DateTime.now();
  String? selectedTime;

  final List<int> availableDates = List.generate(26, (index) => index + 1);

  List<String> getAvailableTimes(int day) {
    final date = DateTime(2024, 4, day);
    final weekday = date.weekday;

    if (weekday >= 6 || weekday == 1) {
      return _generateTimeSlots('5:30 AM', '11:00 AM', 30);
    } else {
      return [
        ..._generateTimeSlots('5:30 AM', '9:00 AM', 30),
        ..._generateTimeSlots('4:30 PM', '7:00 PM', 30),
      ];
    }
  }

  List<String> _generateTimeSlots(String start, String end, int interval) {
    TimeOfDay parseTime(String time) {
      final parts = time.split(RegExp(r'[: ]'));
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = parts[2];
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: minute);
    }

    final startTime = parseTime(start);
    final endTime = parseTime(end);

    List<String> slots = [];
    TimeOfDay current = startTime;

    while (current.hour < endTime.hour ||
        (current.hour == endTime.hour && current.minute < endTime.minute)) {
      slots.add(_formatTimeOfDay(current));
      int minutes = current.hour * 60 + current.minute + interval;
      current = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    }

    return slots;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trainer Schedule'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'SCHEDULE'),
              Tab(text: 'BOOK'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildScheduleSessionTab(),
            _buildBookSessionTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleSessionTab() {
    return _buildCalendarTab((day) => _buildDynamicTimeSlots(day));
  }

  Widget _buildBookSessionTab() {
    return _buildCalendarTab((day) => _buildDynamicBookSlots(day));
  }

  Widget _buildCalendarTab(List<Widget> Function(int) timeSlotBuilder) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'April 2024',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildCalendar(),
          const SizedBox(height: 24),
          if (selectedDate != null) ...[
            const Text(
              'Select Time',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...timeSlotBuilder(selectedDate!),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    List<TableRow> rows = [
      const TableRow(
        children: [
          _CalendarCell('Sun', isHeader: true),
          _CalendarCell('Mon', isHeader: true),
          _CalendarCell('Tue', isHeader: true),
          _CalendarCell('Wed', isHeader: true),
          _CalendarCell('Thu', isHeader: true),
          _CalendarCell('Fri', isHeader: true),
          _CalendarCell('Sat', isHeader: true),
        ],
      )
    ];

    List<int> allDays = List.generate(26, (i) => i + 1);
    List<List<int>> weeks = [];

    while (allDays.isNotEmpty) {
      weeks.add(allDays.take(7).toList());
      allDays = allDays.skip(7).toList();
    }

    for (var week in weeks) {
      List<Widget> cells = week.map((day) {
        return _CalendarCell(
          '$day',
          isSelected: selectedDate == day,
          onTap: () => _selectDate(day),
        );
      }).toList();
      while (cells.length < 7) {
        cells.add(const _CalendarCell(''));
      }
      rows.add(TableRow(children: cells));
    }

    return Table(children: rows);
  }

  void _selectDate(int day) {
    setState(() {
      selectedDate = day;
      selectedDateTime = DateTime(2024, 4, day);
      selectedTime = null;
    });
  }

  List<Widget> _buildDynamicTimeSlots(int day) {
    final times = getAvailableTimes(day);
    return times.map((time) => _buildTimeSlot(time)).toList();
  }

  List<Widget> _buildDynamicBookSlots(int day) {
    final times = getAvailableTimes(day);
    return times.map((time) => _buildTimeSlot(time, showSlots: true)).toList();
  }

  Widget _buildTimeSlot(String time, {bool showSlots = false}) {
    final slotsLeft = showSlots ? _getRandomSlotsAvailable(time) : null;
    final isSelected = selectedTime == time;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: () => setState(() => selectedTime = time),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                time,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (slotsLeft != null)
                Text(
                  slotsLeft,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRandomSlotsAvailable(String time) {
    final random = DateTime.now().millisecond % 5;
    if (random == 0) return '1 slot left';
    return '$random slots left';
  }
}

class _CalendarCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool isSelected;
  final VoidCallback? onTap;

  const _CalendarCell(
    this.text, {
    this.isHeader = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          height: 40,
          decoration: isSelected
              ? const BoxDecoration(
                  color: Colors.indigo,
                  shape: BoxShape.circle,
                )
              : null,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                color: isHeader
                    ? Colors.black
                    : isSelected
                        ? Colors.white
                        : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
