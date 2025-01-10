import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/attendance.dart';
import '../models/contact.dart';
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
  late Future<Map<String, Contact>> _contactMapFuture;

  @override
  void initState() {
    super.initState();
    _refreshAttendance(); // Load attendance data
    _refreshContacts(); // Load contact data
  }

  void _refreshAttendance() {
    setState(() {
      _attendanceFuture = _dbHelper.getAllAttendance(); // Fetch attendance from DBHelper
    });
  }

  void _refreshContacts() {
    setState(() {
      _contactMapFuture = _fetchContactMap(); // Fetch contacts and build a map
    });
  }

  Future<Map<String, Contact>> _fetchContactMap() async {
    final contacts = await _dbHelper.getContacts();
    return {for (var contact in contacts) contact.id: contact};
  }

  Future<void> _deleteAttendance(BuildContext context, String eventId) async {
    await _dbHelper.deleteAttendance(eventId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance deleted successfully')),
    );

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
            return FutureBuilder<Map<String, Contact>>(
              future: _contactMapFuture,
              builder: (context, contactSnapshot) {
                if (contactSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (contactSnapshot.hasError) {
                  return Center(child: Text('Error: ${contactSnapshot.error}'));
                } else if (!contactSnapshot.hasData || contactSnapshot.data!.isEmpty) {
                  return const Center(child: Text('No contacts found.'));
                } else {
                  final contactMap = contactSnapshot.data!;
                  return ListView.builder(
                    itemCount: attendanceList.length,
                    itemBuilder: (context, index) {
                      final attendance = attendanceList[index];
                      return ListTile(
                        title: Text(attendance.eventTitle),
                        subtitle: Text('Date: ${attendance.eventDate.toLocal()}'),
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
                              builder: (context) => AttendanceDetailsPage(
                                attendance: attendance,
                                contactLookup: contactMap,
                              ),
                            ),
                          ).then((_) {
                            _refreshAttendance();
                            _refreshContacts();
                          });
                        },
                      );
                    },
                  );
                }
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