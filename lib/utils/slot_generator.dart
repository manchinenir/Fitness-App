import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> uploadTrainerSlots() async {
  final now = DateTime.now();
  final startDate = now;
  final endDate = now.add(const Duration(days: 14)); // 2 weeks

  for (DateTime date = startDate;
      date.isBefore(endDate);
      date = date.add(const Duration(days: 1))) {
    final day = date.weekday; // 1 = Monday, 7 = Sunday
    List<String> slots = [];

    if (day == 6 || day == 7 || day == 1) {
      slots.addAll(_generateTimes('05:30', '11:00'));
    }
    if (day == 1) {
      slots.addAll(_generateTimes('16:30', '19:00'));
    }
    if (day == 2 || day == 3 || day == 4) {
      slots.addAll(_generateTimes('05:30', '09:00'));
      slots.addAll(_generateTimes('16:30', '19:00'));
    }

    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    for (final time in slots) {
      final docRef = FirebaseFirestore.instance
          .collection('trainer_slots')
          .doc(dateStr)
          .collection('time_slots')
          .doc(time);

      await docRef.set({
        'capacity': 6,
        'bookedBy': [],
        'status': 'available',
      });
    }
  }
}

List<String> _generateTimes(String start, String end) {
  final List<String> times = [];
  var startParts = start.split(':').map(int.parse).toList();
  var endParts = end.split(':').map(int.parse).toList();

  int startHour = startParts[0], startMinute = startParts[1];
  int endHour = endParts[0], endMinute = endParts[1];

  while (startHour < endHour || (startHour == endHour && startMinute < endMinute)) {
    String hourStr = startHour.toString().padLeft(2, '0');
    String minStr = startMinute.toString().padLeft(2, '0');
    times.add('$hourStr:$minStr');
    startMinute += 30;
    if (startMinute >= 60) {
      startMinute = 0;
      startHour += 1;
    }
  }

  return times;
}
