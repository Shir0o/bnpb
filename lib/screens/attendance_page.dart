import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/attendance.dart';
import 'add_attendance_page.dart';
import 'attendance_details_page.dart';

class AttendancePage extends StatelessWidget {
  const AttendancePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
      ),
      body: FutureBuilder<List<Attendance>>(
        future: _fetchAttendance(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No attendance records found.'));
          } else {
            final attendanceList = snapshot.data!;
            return ListView.builder(
              itemCount: attendanceList.length,
              itemBuilder: (context, index) {
                final attendance = attendanceList[index];
                return ListTile(
                  title: Text(attendance.eventTitle),
                  subtitle: Text(
                      'Date: ${attendance.eventDate.toLocal()} \nContacts: ${attendance.contacts.length}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      _deleteAttendance(context, attendance.eventId);
                    },
                  ),
                  onTap: () {
                    // Navigate to AttendanceDetailsPage, passing the attendance data
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AttendanceDetailsPage(attendance: attendance),
                      ),
                    );
                  },
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddAttendancePage()),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Mark Attendance',
      ),
    );
  }

  Future<List<Attendance>> _fetchAttendance() async {
    final dbHelper = DBHelper();
    return await dbHelper.getAllAttendance();
  }

  Future<void> _deleteAttendance(BuildContext context, String eventId) async {
    final dbHelper = DBHelper();

    // Delete the attendance record
    await dbHelper.deleteAttendance(eventId);

    // Show a confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance deleted successfully')),
    );

    // Refresh the UI (rebuild the widget tree)
    (context as Element).reassemble();
  }
}