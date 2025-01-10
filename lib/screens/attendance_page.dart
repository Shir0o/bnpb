import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/attendance.dart';
import 'add_attendance_page.dart';
import 'attendance_details_page.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({Key? key}) : super(key: key);

  @override
  _AttendancePageState createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final DBHelper _dbHelper = DBHelper();
  late Future<List<Attendance>> _attendanceFuture;

  @override
  void initState() {
    super.initState();
    _refreshAttendance(); // Load attendance data
  }

  void _refreshAttendance() {
    setState(() {
      _attendanceFuture = _dbHelper.getAllAttendance(); // Fetch attendance from DBHelper
    });
  }

  Future<void> _deleteAttendance(BuildContext context, String eventId) async {
    await _dbHelper.deleteAttendance(eventId); // Use DBHelper to delete the record

    // Show a confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance deleted successfully')),
    );

    // Refresh the data
    _refreshAttendance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
      ),
      body: FutureBuilder<List<Attendance>>(
        future: _attendanceFuture,
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            AttendanceDetailsPage(attendance: attendance),
                      ),
                    ).then((_) => _refreshAttendance());
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
          ).then((_) => _refreshAttendance());
        },
        child: const Icon(Icons.add),
        tooltip: 'Mark Attendance',
      ),
    );
  }
}