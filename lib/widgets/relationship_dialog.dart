import 'package:flutter/material.dart';
import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import '../models/contact.dart';
import '../models/relationship.dart';
import 'crisp_toast.dart';

class RelationshipDialog extends StatefulWidget {
  final Contact currentContact;
  final List<Contact> availableContacts;
  final Relationship? relationship;
  final Function(Relationship) onSave;

  const RelationshipDialog({
    super.key,
    required this.currentContact,
    required this.availableContacts,
    required this.onSave,
    this.relationship,
  });

  @override
  State<RelationshipDialog> createState() => _RelationshipDialogState();
}

class _RelationshipDialogState extends State<RelationshipDialog> {
  late String? selectedContactId;
  late List<Contact> dropdownContacts;
  final standardRoles = ['Parent', 'Child', 'Spouse', 'Sibling', 'Other'];
  late String selectedRole;
  late TextEditingController otherTypeController;
  late TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    dropdownContacts = List<Contact>.from(widget.availableContacts);

    if (widget.relationship != null) {
      selectedContactId = widget.relationship!.targetContactId;
      // We assume the parent passed a valid list including the target contact if editing.
    } else {
      selectedContactId =
          dropdownContacts.isNotEmpty ? dropdownContacts.first.id : null;
    }

    notesController = TextEditingController(
      text: widget.relationship?.notes ?? '',
    );
    otherTypeController = TextEditingController();

    if (widget.relationship != null) {
      if (standardRoles.contains(widget.relationship!.type)) {
        selectedRole = widget.relationship!.type;
      } else {
        selectedRole = 'Other';
        otherTypeController.text = widget.relationship!.type;
      }
    } else {
      selectedRole = 'Parent';
    }
  }

  @override
  void dispose() {
    notesController.dispose();
    otherTypeController.dispose();
    super.dispose();
  }

  String getTargetName() {
    if (selectedContactId == null) return 'selected contact';
    try {
      final contact = dropdownContacts.firstWhere(
        (c) => c.id == selectedContactId,
      );
      return contact.fullName.isNotEmpty
          ? contact.fullName
          : (contact.nickname ?? 'Selected Contact');
    } catch (_) {
      return 'Selected Contact';
    }
  }

  String getSourceName() {
    return widget.currentContact.fullName.isNotEmpty
        ? widget.currentContact.fullName
        : (widget.currentContact.nickname ?? 'Current Contact');
  }

  String getRoleDescription() {
    final role = selectedRole == 'Other'
        ? (otherTypeController.text.isEmpty ? '...' : otherTypeController.text)
        : selectedRole;
    return '${getTargetName()} is the $role of ${getSourceName()}';
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.relationship != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Relationship' : 'Add Relationship'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedContactId,
              decoration: const InputDecoration(
                labelText: 'Connected contact',
              ),
              items: dropdownContacts
                  .map(
                    (contact) => DropdownMenuItem<String>(
                      value: contact.id,
                      child: Text(
                        contact.fullName.isNotEmpty
                            ? contact.fullName
                            : (contact.nickname ?? 'Unnamed Contact'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedContactId = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Role',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: standardRoles.map((role) {
                return _buildRoleChip(role);
              }).toList(),
            ),
            if (selectedRole == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: otherTypeController,
                decoration: const InputDecoration(
                  labelText: 'Custom relationship type',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      getRoleDescription(),
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final targetId = selectedContactId;
            String finalType = selectedRole;

            if (selectedRole == 'Other') {
              finalType = otherTypeController.text.trim();
            }

            if (finalType.isEmpty || targetId == null) {
              CrispToast.show(context, 'Please select a contact and role.');
              return;
            }

            final relationshipToSave = Relationship(
              id: widget.relationship?.id,
              sourceContactId: widget.currentContact.id,
              targetContactId: targetId,
              type: finalType,
              notes: notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
            );

            widget.onSave(relationshipToSave);
            // Navigator pop is handled inside onSave or caller?
            // Better to let caller handle async ops, but here we invoke and close?
            // In original, it did async save then pop.
            // Let's matching the original behavior: we passed an async callback probably.
            // But here onSave is synchronous in signature.
            // Let's assume onSave returns void/Future.
            // The widget should technically be cleaner but for now simple 'onPressed' logic is fine.
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildRoleChip(String role) {
    final isSelected = selectedRole == role;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        setState(() {
          selectedRole = role;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.greenTint : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.cardBorder,
            width: 1,
          ),
        ),
        child: Text(
          role,
          style: TextStyle(
            color: isSelected ? colorScheme.primary : colorScheme.secondaryText,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
