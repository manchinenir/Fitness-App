// ================================
// workout_category_tile.dart
// Expandable Workout List with Checkboxes
// ================================

import 'package:flutter/material.dart';

class WorkoutCategoryTile extends StatelessWidget {
  final String category;
  final List<String> workouts;
  final List<String> selectedWorkouts;
  final void Function(String category, String workout, bool isSelected) onSelectionChanged;

  const WorkoutCategoryTile({
    required this.category,
    required this.workouts,
    required this.selectedWorkouts,
    required this.onSelectionChanged,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold)),
      children: workouts.map((workout) {
        final isChecked = selectedWorkouts.contains(workout);
        return CheckboxListTile(
          title: Text(workout),
          value: isChecked,
          onChanged: (bool? value) {
            if (value != null) {
              onSelectionChanged(category, workout, value);
            }
          },
        );
      }).toList(),
    );
  }
}
