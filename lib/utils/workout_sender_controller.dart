import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutSenderController {
  static Future<void> sendWorkouts({
    required List<String> clientIds,
    required Map<String, List<String>> workouts,
    required String trainerName,
  }) async {
    final now = Timestamp.now();
    final workoutRef = FirebaseFirestore.instance.collection('workouts').doc();

    final workoutData = {
      'trainer': trainerName,
      'workouts': workouts,
      'assigned_at': now,
      'clients': clientIds,
    };

    // 1. Save workout globally
    await workoutRef.set(workoutData);

    // 2. Also save it to each client's subcollection
    for (final clientId in clientIds) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(clientId)
          .collection('workouts')
          .doc(workoutRef.id)
          .set(workoutData);
    }
  }
}
