// ================================
// workout_confirmation_dialog.dart
// Confirmation Dialog Before Sending Workouts
// ================================

import 'package:flutter/material.dart';

class WorkoutConfirmationDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const WorkoutConfirmationDialog({
    required this.onConfirm,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Workout Assignment'),
      content: const Text('Are you sure you want to send the selected workouts to this client?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(); // Close the dialog
            onConfirm(); // Proceed with sending workout
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
