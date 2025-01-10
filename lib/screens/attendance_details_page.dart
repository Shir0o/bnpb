import 'package:flutter/material.dart';
import '../models/attendance.dart';

class AttendanceDetailsPage extends StatelessWidget {
  final Attendance attendance;

  const AttendanceDetailsPage({Key? key, required this.attendance}) : super(key: key);

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
              'Event Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text('Date: ${attendance.eventDate.toLocal()}'),
            const SizedBox(height: 10),
            Text('Number of Contacts: ${attendance.contacts.length}'),
            const SizedBox(height: 20),
            Text(
              'Contacts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: attendance.contacts.length,
                itemBuilder: (context, index) {
                  final contact = attendance.contacts.entries.toList()[index];
                  return ListTile(
                    title: Text(contact.key),
                    trailing: Icon(
                      contact.value ? Icons.check : Icons.clear,
                      color: contact.value ? Colors.green : Colors.red,
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