// firestore_slot_uploader.dart
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> uploadTrainerSlots() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final daysOfWeek = {
    DateTime.friday: ['05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM'],
    DateTime.saturday: ['05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM'],
    DateTime.sunday: ['05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM'],
    DateTime.monday: [
      '05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM',
      '04:30 PM', '05:00 PM', '05:30 PM', '06:00 PM', '06:30 PM'
    ],
    DateTime.tuesday: [
      '05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM',
      '04:30 PM', '05:00 PM', '05:30 PM', '06:00 PM', '06:30 PM'
    ],
    DateTime.wednesday: [
      '05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM',
      '04:30 PM', '05:00 PM', '05:30 PM', '06:00 PM', '06:30 PM'
    ],
    DateTime.thursday: [
      '05:30 AM', '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM',
      '04:30 PM', '05:00 PM', '05:30 PM', '06:00 PM', '06:30 PM'
    ],
  };

  final startDate = DateTime.now();
  final endDate = startDate.add(const Duration(days: 14));

  for (DateTime date = startDate;
      date.isBefore(endDate);
      date = date.add(const Duration(days: 1))) {
    final daySlots = daysOfWeek[date.weekday];
    if (daySlots != null) {
      for (final time in daySlots) {
        final docRef = firestore
            .collection('trainer_slots')
            .doc('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}')
            .collection('time_slots')
            .doc(time);

        await docRef.set({
          'time': time,
          'capacity': 6,
          'bookedBy': [],
          'status': 'available',
        });
      }
    }
  }
}
