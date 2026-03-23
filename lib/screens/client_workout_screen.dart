import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ClientWorkoutScreen extends StatefulWidget {
  const ClientWorkoutScreen({super.key});

  @override
  State<ClientWorkoutScreen> createState() => _ClientWorkoutScreenState();
}

class _ClientWorkoutScreenState extends State<ClientWorkoutScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final _dateFormatter = DateFormat('MMM d, yyyy');
  final _timeFormatter = DateFormat('hh:mm a');
  final Color _primaryColor = const Color(0xFF1C2D5E);
  final Color _accentColor = Colors.blue[700]!;
  final Color _textColor = Colors.blue[900]!;

  // Track video controllers to dispose them properly
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ChewieController> _chewieControllers = {};
  
  // Track expanded state for workouts
  final Map<String, bool> _expandedWorkouts = {};

  @override
  void dispose() {
    // Dispose all video controllers
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    for (var controller in _chewieControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return _buildAuthErrorScreen();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "My Workouts",
          style: TextStyle(
            color: Colors.white,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
          ),
        ],
      ),
      body: _buildWorkoutList(),
    );
  }

  Widget _buildWorkoutList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('workouts')
          .where('assigned_at', isGreaterThan: Timestamp(0, 0))
          .orderBy('assigned_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final workouts = snapshot.data!.docs;
        
        // First, separate and count custom workouts
        int customWorkoutCount = 0;
        final List<Map<String, dynamic>> workoutList = [];
        
        for (var doc in workouts) {
          final data = doc.data() as Map<String, dynamic>;
          final workoutType = data['type'] ?? 'standard';
          
          if (workoutType == 'custom') {
            customWorkoutCount++;
          }
          
          workoutList.add({
            'doc': doc,
            'data': data,
            'type': workoutType,
          });
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: workouts.length,
          itemBuilder: (context, index) {
            final doc = workouts[index];
            final data = doc.data() as Map<String, dynamic>;
            
            final assignedAt = data['assigned_at'] != null 
                ? (data['assigned_at'] as Timestamp).toDate() 
                : DateTime.now();
            final trainerName = data['trainer'] ?? data['trainerName'] ?? 'Your Trainer';
            final isMostRecent = index == 0;
            final workoutId = doc.id;
            final workoutType = data['type'] ?? 'standard';
            
            // Initialize expanded state
            _expandedWorkouts.putIfAbsent(workoutId, () => isMostRecent);

            // Generate workout title based on type and position
            String workoutTitle;
            if (workoutType == 'standard') {
              workoutTitle = data['workout_name'] ?? 'Standard Workout';
            } else {
              // For custom workouts, number them sequentially from oldest to newest
              // Count how many custom workouts come after this one (older ones)
              int customPosition = 1;
              for (int i = workouts.length - 1; i >= 0; i--) {
                final tempDoc = workouts[i];
                final tempData = tempDoc.data() as Map<String, dynamic>;
                final tempType = tempData['type'] ?? 'standard';
                
                if (tempType == 'custom') {
                  if (tempDoc.id == doc.id) {
                    break;
                  }
                  customPosition++;
                }
              }
              workoutTitle = 'Workout Plan-$customPosition';
            }

            if (workoutType == 'standard') {
              return _buildStandardWorkoutCard(
                context: context,
                workoutId: workoutId,
                data: data,
                assignedAt: assignedAt,
                trainerName: trainerName,
                isMostRecent: isMostRecent,
                index: index,
                workoutTitle: workoutTitle,
              );
            } else {
              return _buildCustomWorkoutCard(
                context: context,
                workoutId: workoutId,
                data: data,
                assignedAt: assignedAt,
                trainerName: trainerName,
                isMostRecent: isMostRecent,
                index: index,
                workoutTitle: workoutTitle,
              );
            }
          },
        );
      },
    );
  }

  // Standard Workout Card with media buttons at the top
  Widget _buildStandardWorkoutCard({
    required BuildContext context,
    required String workoutId,
    required Map<String, dynamic> data,
    required DateTime assignedAt,
    required String trainerName,
    required bool isMostRecent,
    required int index,
    required String workoutTitle,
  }) {
    final workoutMedia = data['workout_media'] as List? ?? [];
    final exercises = data['exercises'] as List? ?? [];

    return Card(
      elevation: isMostRecent ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMostRecent ? _accentColor : Colors.grey.withOpacity(0.2),
          width: isMostRecent ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Workout Header (always visible)
          InkWell(
            onTap: () {
              setState(() {
                _expandedWorkouts[workoutId] = !(_expandedWorkouts[workoutId] ?? false);
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Index circle
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isMostRecent ? _primaryColor : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (index + 1).toString(),
                        style: TextStyle(
                          color: isMostRecent ? Colors.white : _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Title and details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workoutTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _primaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Text(
                              _dateFormatter.format(assignedAt),
                              style: TextStyle(fontSize: 12, color: _textColor),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Text(
                              _timeFormatter.format(assignedAt),
                              style: TextStyle(fontSize: 12, color: _textColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'By: $trainerName',
                                style: TextStyle(fontSize: 12, color: _textColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Expand/collapse icon
                  Icon(
                    _expandedWorkouts[workoutId] == true
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _primaryColor,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content
          if (_expandedWorkouts[workoutId] == true) ...[
            const Divider(height: 1),
            
            // Workout Media Section with buttons at the top
            if (workoutMedia.isNotEmpty)
              _buildStandardMediaButtons(workoutMedia, workoutId),
            
            // Exercises Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EXERCISES',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...exercises.map((exercise) {
                    if (exercise is Map<String, dynamic>) {
                      return _buildExerciseItem(exercise, workoutId);
                    }
                    return _buildSimpleExercise(exercise.toString());
                  }).toList(),
                  
                  if (exercises.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No exercises in this workout',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Custom Workout Card - Shows both image and video buttons if available
  Widget _buildCustomWorkoutCard({
    required BuildContext context,
    required String workoutId,
    required Map<String, dynamic> data,
    required DateTime assignedAt,
    required String trainerName,
    required bool isMostRecent,
    required int index,
    required String workoutTitle,
  }) {
    // USE FLATTENED EXERCISES LIST
    final List exercises = data['exercises'] as List? ?? [];

    return Card(
      elevation: isMostRecent ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMostRecent ? _accentColor : Colors.grey.withOpacity(0.2),
          width: isMostRecent ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // HEADER
          InkWell(
            onTap: () {
              setState(() {
                _expandedWorkouts[workoutId] =
                    !(_expandedWorkouts[workoutId] ?? false);
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Index circle
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isMostRecent ? _primaryColor : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (index + 1).toString(),
                        style: TextStyle(
                          color: isMostRecent ? Colors.white : _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workoutTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _primaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Text(
                              _dateFormatter.format(assignedAt),
                              style:
                                  TextStyle(fontSize: 12, color: _textColor),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time,
                                size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Text(
                              _timeFormatter.format(assignedAt),
                              style:
                                  TextStyle(fontSize: 12, color: _textColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'By: $trainerName',
                                style: TextStyle(
                                    fontSize: 12, color: _textColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Icon(
                    _expandedWorkouts[workoutId] == true
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _primaryColor,
                  ),
                ],
              ),
            ),
          ),

          // BODY
          if (_expandedWorkouts[workoutId] == true) ...[
            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.all(16),
              child: exercises.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        ...exercises.map((exercise) {
                          if (exercise is Map<String, dynamic>) {
                            return _buildCustomExerciseWithBothMedia(
                              exercise,
                              workoutId,
                            );
                          }
                          return const SizedBox.shrink();
                        }).toList(),
                      ],
                    )
                  : const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No exercises in this workout',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  // NEW METHOD: Custom exercise with BOTH image and video buttons (if available)
  Widget _buildCustomExerciseWithBothMedia(Map<String, dynamic> exercise, String workoutId) {
    final exerciseName = exercise['name'] ?? exercise['exerciseName'] ?? 'Exercise';
    
    final String? imageUrl = exercise.containsKey('imageUrl') &&
            exercise['imageUrl'] != null &&
            exercise['imageUrl'].toString().trim().isNotEmpty
        ? exercise['imageUrl'].toString().trim()
        : null;

    final String? videoUrl = exercise.containsKey('videoUrl') &&
            exercise['videoUrl'] != null &&
            exercise['videoUrl'].toString().trim().isNotEmpty
        ? exercise['videoUrl'].toString().trim()
        : null;

    final bool hasImage = imageUrl != null && _isValidUrl(imageUrl);
    final bool hasVideo = videoUrl != null && _isValidUrl(videoUrl);

    // Get exercise details for custom workouts (if available)
    final sets = exercise['sets'];
    final reps = exercise['reps'];
    final duration = exercise['duration'];
    final restTime = exercise['restTime'];
    final hasDetails = sets != null || reps != null || duration != null || restTime != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exercise header with name
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exerciseName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: _primaryColor,
                  ),
                ),
              ),
              
              // Media buttons - BOTH image and video if available
              if (hasImage || hasVideo)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasImage)
                      _buildMediaButton(
                        icon: Icons.image,
                        label: 'Image',
                        color: Colors.green,
                        onTap: () => _showMediaDialog(imageUrl!, 'image', exerciseName),
                      ),
                    if (hasVideo)
                      _buildMediaButton(
                        icon: Icons.videocam,
                        label: 'Video',
                        color: Colors.blue,
                        onTap: () async {
                          await _openVideoDialog(videoUrl!, exerciseName);
                        },
                      ),
                  ],
                ),
            ],
          ),
          
          // Exercise details (if available for custom workouts)
          if (hasDetails)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (sets != null)
                    _buildDetailChip('Sets: $sets', Icons.fitness_center),
                  if (reps != null)
                    _buildDetailChip('Reps: $reps', Icons.repeat),
                  if (duration != null)
                    _buildDetailChip('Duration: $duration', Icons.timer),
                  if (restTime != null)
                    _buildDetailChip('Rest: $restTime', Icons.hourglass_empty),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Media buttons for standard workouts (at the top)
  Widget _buildStandardMediaButtons(List<dynamic> workoutMedia, String workoutId) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ondemand_video, size: 18, color: _primaryColor),
              const SizedBox(width: 8),
              Text(
                'Workout Media',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Media buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: workoutMedia.asMap().entries.map((entry) {
              final index = entry.key;
              final media = entry.value;
              if (media is Map<String, dynamic>) {
                final url = media['url'] ?? '';
                final type = media['type'] ?? '';
                
                if (url.isEmpty) return const SizedBox.shrink();
                
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      if (type == 'video') {
                        await _openVideoDialog(url, 'Workout Video ${index + 1}');
                      } else {
                        _showMediaDialog(url, 'image', 'Workout Image ${index + 1}');
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: type == 'video' ? Colors.blue[50] : Colors.green[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: type == 'video' ? Colors.blue[200]! : Colors.green[200]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            type == 'video' ? Icons.videocam : Icons.image,
                            size: 16,
                            color: type == 'video' ? Colors.blue : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            type == 'video' ? 'Video ${index + 1}' : 'Image ${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: type == 'video' ? Colors.blue : Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Standard exercise item with media
  Widget _buildExerciseItem(Map<String, dynamic> exercise, String workoutId) {
    final exerciseName = exercise['name'] ?? exercise['exerciseName'] ?? 'Exercise';
    final sets = exercise['sets'];
    final reps = exercise['reps'];
    final duration = exercise['duration'];
    final restTime = exercise['restTime'];
    
    // Get media URLs
    final imageUrl = exercise['imageUrl'];
    final videoUrl = exercise['videoUrl'];
    
    final hasImage = _isValidUrl(imageUrl);
    final hasVideo = _isValidUrl(videoUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exercise header with name and media buttons
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exerciseName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: _primaryColor,
                  ),
                ),
              ),
              
              // Media buttons - BOTH image and video if available
              if (hasImage || hasVideo)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasImage)
                      _buildMediaButton(
                        icon: Icons.image,
                        label: 'Image',
                        color: Colors.green,
                        onTap: () => _showMediaDialog(imageUrl!, 'image', exerciseName),
                      ),
                    if (hasVideo)
                      _buildMediaButton(
                        icon: Icons.videocam,
                        label: 'Video',
                        color: Colors.blue,
                        onTap: () async {
                            await _openVideoDialog(videoUrl!, exerciseName);
                          },
                      ),
                  ],
                ),
            ],
          ),
          
          // Exercise details
          if (sets != null || reps != null || duration != null || restTime != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (sets != null)
                    _buildDetailChip('Sets: $sets', Icons.fitness_center),
                  if (reps != null)
                    _buildDetailChip('Reps: $reps', Icons.repeat),
                  if (duration != null)
                    _buildDetailChip('Duration: $duration', Icons.timer),
                  if (restTime != null)
                    _buildDetailChip('Rest: $restTime', Icons.hourglass_empty),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Helper method to build media button
  Widget _buildMediaButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Show media in dialog
  void _showMediaDialog(String url, String type, String title) {
    showDialog(
      context: context,
      barrierDismissible: false, // IMPORTANT
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(
                      type == 'video' ? Icons.videocam : Icons.image,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Media content
              Expanded(
                child: type == 'video'
                    ? _buildVideoPlayer(url, 'dialog_$title', 'dialog')
                    : _buildImageWidget(url, title),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleExercise(String exerciseName) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6, 
            height: 6, 
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: _accentColor, 
              shape: BoxShape.circle
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              exerciseName,
              style: TextStyle(
                fontSize: 14, 
                height: 1.4, 
                color: _textColor
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: _textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl, String title) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 3.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => Container(
              height: 200,
              color: Colors.grey[300],
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Loading image...',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 200,
              color: Colors.grey[300],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 40, color: Colors.grey[600]),
                  const SizedBox(height: 4),
                  Text(
                    'Failed to load image',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(String videoUrl, String identifier, String sourceId) {
    final videoKey = '$sourceId-$identifier-$videoUrl';
    
    // Check if we already have a controller for this video
    if (!_videoControllers.containsKey(videoKey)) {
      _initializeVideoController(videoKey, videoUrl);
    }

    // If controller exists but not initialized yet or error occurred
    if (!_videoControllers.containsKey(videoKey) || 
        _videoControllers[videoKey] == null || 
        !(_videoControllers[videoKey]!.value.isInitialized)) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading video...',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Return the video player
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.black,
        ),
        clipBehavior: Clip.antiAlias,
        child: Chewie(
          controller: _chewieControllers[videoKey]!,
        ),
      ),
    );
  }

  Future<void> _openVideoDialog(String videoUrl, String title) async {
    final videoKey = 'dialog-$title-$videoUrl';

    // If controller doesn't exist, initialize FIRST
    if (!_videoControllers.containsKey(videoKey)) {
      await _initializeAndWait(videoKey, videoUrl);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false, // ⛔ don't auto-close
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // ⏸️ PAUSE video when user taps anywhere outside
          _videoControllers[videoKey]?.pause();
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            height: 350,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Chewie(
              controller: _chewieControllers[videoKey]!,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _initializeAndWait(String videoKey, String videoUrl) async {
    final uri = Uri.parse(videoUrl);

    final videoController = VideoPlayerController.networkUrl(uri);
    _videoControllers[videoKey] = videoController;

    await videoController.initialize();

    final chewieController = ChewieController(
      videoPlayerController: videoController,
      autoPlay: true, // 🔥 START IMMEDIATELY
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
    );

    _chewieControllers[videoKey] = chewieController;
  }

  void _initializeVideoController(String videoKey, String videoUrl) {
    try {
      // Validate URL
      final uri = Uri.tryParse(videoUrl);
      if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        print('Invalid video URL: $videoUrl');
        return;
      }

      final videoController = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );
      
      _videoControllers[videoKey] = videoController;
      
      videoController.initialize().then((_) {
        if (mounted) {
          setState(() {
            final chewieController = ChewieController(
              videoPlayerController: videoController,
              autoPlay: false,
              looping: false,
              aspectRatio: videoController.value.aspectRatio,
              allowFullScreen: true,
              allowMuting: true,
              placeholder: Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
              materialProgressColors: ChewieProgressColors(
                playedColor: _primaryColor,
                handleColor: _primaryColor,
                backgroundColor: Colors.grey[300]!,
                bufferedColor: Colors.grey[500]!,
              ),
              errorBuilder: (context, errorMessage) {
                print('Chewie error: $errorMessage');
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[400], size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'Error loading video',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          errorMessage,
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
            
            _chewieControllers[videoKey] = chewieController;
          });
        }
      }).catchError((error) {
        print('Error initializing video: $error');
        if (mounted) {
          setState(() {
            // Remove failed controller
            _videoControllers.remove(videoKey);
          });
        }
      });
    } catch (e) {
      print('Exception initializing video: $e');
    }
  }

  bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center,
                size: 64,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No Workouts Assigned",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Your trainer hasn't assigned any workouts yet. Check back later or contact your trainer.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _textColor,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () => setState(() {}),
              child: const Text("REFRESH"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              "Something went wrong",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[400],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () => setState(() {}),
              child: const Text("RETRY"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 64,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Authentication Required",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Please sign in to access your workout plans",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _textColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () {
                  // Navigate to login screen
                  // Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text(
                  "SIGN IN",
                  style: TextStyle(
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}