import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/attendance.dart';
import '../models/contact.dart';

class AttendanceDetailsPage extends StatelessWidget {
  final Attendance attendance;
  final Map<String, Contact> contactLookup;

  const AttendanceDetailsPage({
    Key? key,
    required this.attendance,
    required this.contactLookup,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(attendance.eventTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10), // Add space between the title and the date
            Text(
              DateFormat('EEEE, MMMM d, yyyy - h:mm a').format(attendance.eventDate.toLocal()),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text(
              'Attendance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: attendance.contacts.length,
                itemBuilder: (context, index) {
                  final entry = attendance.contacts.entries.toList()[index];
                  final contactId = entry.key;
                  final isPresent = entry.value;
                  final contact = contactLookup[contactId];

                  return ListTile(
                    title: Text(
                      contact?.fullName ?? 'Unknown Contact',
                    ),
                    trailing: Icon(
                      isPresent ? Icons.check : Icons.clear,
                      color: isPresent ? Colors.green : Colors.red,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}