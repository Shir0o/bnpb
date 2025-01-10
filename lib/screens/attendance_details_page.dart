import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/attendance.dart';
import '../models/contact.dart';

class AttendanceDetailsPage extends StatelessWidget {
  final Attendance attendance;
  final Map<String, Contact> contactLookup;

  const AttendanceDetailsPage({
    super.key,
    required this.attendance,
    required this.contactLookup,
  });

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
            // Date section with Material styling
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy - h:mm a')
                          .format(attendance.eventDate.toLocal()),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),

            // Attendance section
            Text(
              'Attendance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),

            // List of attendees wrapped in a Card
            Expanded(
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ListView.builder(
                    itemCount: attendance.contacts.length,
                    itemBuilder: (context, index) {
                      final entry = attendance.contacts.entries.toList()[index];
                      final contactId = entry.key;
                      final isPresent = entry.value;
                      final contact = contactLookup[contactId];

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isPresent ? Colors.green : Colors.red,
                          child: Icon(
                            isPresent ? Icons.check : Icons.clear,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          contact?.fullName ?? 'Unknown Contact',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        tileColor: isPresent
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
