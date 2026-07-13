import 'dart:async';

import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/relationship.dart';
import '../services/backup_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';

const _standardRoles = <String>[
  'Parent',
  'Child',
  'Spouse',
  'Sibling',
  'Other',
];

String _inverseRole(String role, {String? customType}) {
  switch (role) {
    case 'Parent':
      return 'Child';
    case 'Child':
      return 'Parent';
    case 'Spouse':
      return 'Spouse';
    case 'Sibling':
      return 'Sibling';
    default:
      return customType ?? role;
  }
}

class _MemberDraft {
  _MemberDraft({String? defaultLastName})
      : firstName = TextEditingController(),
        lastName = TextEditingController(text: defaultLastName ?? ''),
        role = 'Child',
        customRole = TextEditingController();

  final TextEditingController firstName;
  final TextEditingController lastName;
  String role;
  final TextEditingController customRole;

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    customRole.dispose();
  }
}

class AddFamilyPage extends StatefulWidget {
  const AddFamilyPage({super.key});

  @override
  State<AddFamilyPage> createState() => _AddFamilyPageState();
}

class _AddFamilyPageState extends State<AddFamilyPage> {
  final _formKey = GlobalKey<FormState>();

  final _anchorFirstName = TextEditingController();
  final _anchorMiddleName = TextEditingController();
  final _anchorLastName = TextEditingController();
  final _anchorNickname = TextEditingController();
  final _anchorLocation = TextEditingController();

  final List<_MemberDraft> _members = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _anchorLastName.addListener(_syncMemberLastNames);
    _addMember();
  }

  @override
  void dispose() {
    _anchorLastName.removeListener(_syncMemberLastNames);
    _anchorFirstName.dispose();
    _anchorMiddleName.dispose();
    _anchorLastName.dispose();
    _anchorNickname.dispose();
    _anchorLocation.dispose();
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  /// When the anchor's last name changes, propagate it to member rows that
  /// haven't been manually edited (i.e. still empty or match the previous default).
  String _previousAnchorLast = '';
  void _syncMemberLastNames() {
    final next = _anchorLastName.text;
    for (final m in _members) {
      if (m.lastName.text == _previousAnchorLast) {
        m.lastName.text = next;
      }
    }
    _previousAnchorLast = next;
  }

  void _addMember() {
    setState(() {
      _members.add(_MemberDraft(defaultLastName: _anchorLastName.text));
    });
  }

  void _removeMember(int index) {
    setState(() {
      _members.removeAt(index).dispose();
    });
  }

  Future<void> _saveAll() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // Use ISO-timestamp IDs (matching AddContactPage) so ReminderCoordinator's
    // creation-time parsing keeps working. Bump by 1µs per contact to guarantee
    // uniqueness within the same save.
    var stamp = DateTime.now();
    String nextId() {
      final id = stamp.toIso8601String();
      stamp = stamp.add(const Duration(microseconds: 1));
      return id;
    }

    final anchorLast = _anchorLastName.text.trim();
    final anchor = Contact(
      id: nextId(),
      firstName: _anchorFirstName.text.trim(),
      middleName: _anchorMiddleName.text.trim(),
      lastName: anchorLast.isEmpty ? null : anchorLast,
      nickname: _anchorNickname.text.trim().isEmpty
          ? null
          : _anchorNickname.text.trim(),
      location: _anchorLocation.text.trim().isEmpty
          ? null
          : _anchorLocation.text.trim(),
    );

    final memberContacts = <Contact>[];
    final relationships = <Relationship>[];

    for (final m in _members) {
      final last = m.lastName.text.trim();
      final memberId = nextId();
      memberContacts.add(
        Contact(
          id: memberId,
          firstName: m.firstName.text.trim(),
          lastName: last.isEmpty ? null : last,
        ),
      );

      final role = m.role;
      final customType = role == 'Other' ? m.customRole.text.trim() : null;
      final forwardType = role == 'Other' ? (customType ?? 'Other') : role;
      final inverseType = _inverseRole(role, customType: customType);

      relationships.add(
        Relationship(
          sourceContactId: anchor.id,
          targetContactId: memberId,
          type: forwardType,
        ),
      );
      relationships.add(
        Relationship(
          sourceContactId: memberId,
          targetContactId: anchor.id,
          type: inverseType,
        ),
      );
    }

    // Auto-sibling: any two members that are both Child of the anchor.
    for (var i = 0; i < _members.length; i++) {
      if (_members[i].role != 'Child') continue;
      for (var j = i + 1; j < _members.length; j++) {
        if (_members[j].role != 'Child') continue;
        final a = memberContacts[i].id;
        final b = memberContacts[j].id;
        relationships.add(
          Relationship(sourceContactId: a, targetContactId: b, type: 'Sibling'),
        );
        relationships.add(
          Relationship(sourceContactId: b, targetContactId: a, type: 'Sibling'),
        );
      }
    }

    setState(() => _isSaving = true);

    try {
      final dbHelper = DBHelper();
      final database = await dbHelper.database;
      await database.transaction((txn) async {
        await dbHelper.contactDao.upsertContactRow(
          txn,
          anchor,
          isUpdate: false,
        );
        for (final c in memberContacts) {
          await dbHelper.contactDao.upsertContactRow(txn, c, isUpdate: false);
        }
        final batch = txn.batch();
        for (final r in relationships) {
          batch.insert('relationships', r.toMap(includeId: false));
        }
        await batch.commit(noResult: true);
      });

      ContactService().notifyContactsChanged();

      if (!mounted) return;
      final total = 1 + memberContacts.length;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $total contacts')));

      unawaited(BackupService().exportBackup());
      unawaited(ReminderCoordinator().syncSignificantDates(anchor));
      for (final c in memberContacts) {
        unawaited(ReminderCoordinator().syncSignificantDates(c));
      }

      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save family: $error')));
      debugPrint('Failed to save family: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 390;
    final double titleSize = isSmallScreen ? 20.0 : 26.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Family',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F1512),
          ),
        ),
        titleSpacing: 14,
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        leadingWidth: 62,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: Material(
                color: const Color(0xFFF1F5F2),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: Color(0xFF0F1512),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : GestureDetector(
                    onTap: _saveAll,
                    child: const Text(
                      'Save all',
                      style: TextStyle(
                        color: Color(0xFF0D7A4F),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel(context, 'Primary contact'),
              const SizedBox(height: 8),
              _anchorCard(),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Family members'),
              const SizedBox(height: 8),
              for (var i = 0; i < _members.length; i++) ...[
                _memberCard(i),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add member'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _anchorCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EBE7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _anchorFirstName,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'First Name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter first name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _anchorMiddleName,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Middle Name (Optional)',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _anchorLastName,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Last Name (Optional)',
                prefixIcon: Icon(Icons.person_outline),
                helperText: 'Used as default for family members',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _anchorNickname,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nickname (Optional)',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _anchorLocation,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Location (Optional)',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberCard(int index) {
    final m = _members[index];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EBE7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: m.firstName,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'First name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: m.lastName,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Last name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed:
                      _members.length > 1 ? () => _removeMember(index) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _standardRoles.map((role) {
                return _buildRoleChip(m, role);
              }).toList(),
            ),
            if (m.role == 'Other') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: m.customRole,
                decoration: const InputDecoration(
                  labelText: 'Custom relationship',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (m.role != 'Other') return null;
                  return v == null || v.trim().isEmpty ? 'Required' : null;
                },
              ),
            ],
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: Listenable.merge([
                m.firstName,
                m.customRole,
                _anchorFirstName,
              ]),
              builder: (context, _) => Text(
                _roleSummary(m),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleSummary(_MemberDraft m) {
    final anchorName = _anchorFirstName.text.trim().isEmpty
        ? 'the primary contact'
        : _anchorFirstName.text.trim();
    final first = m.firstName.text.trim().isEmpty
        ? 'This person'
        : m.firstName.text.trim();
    final role = m.role == 'Other'
        ? (m.customRole.text.trim().isEmpty ? '...' : m.customRole.text.trim())
        : m.role;
    return '$first is the $role of $anchorName';
  }

  Widget _buildRoleChip(_MemberDraft m, String role) {
    final isSelected = m.role == role;
    return InkWell(
      onTap: () {
        setState(() => m.role = role);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEAF6EF) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF0D7A4F) : const Color(0xFFE6EBE7),
            width: 1,
          ),
        ),
        child: Text(
          role,
          style: TextStyle(
            color:
                isSelected ? const Color(0xFF0D7A4F) : const Color(0xFF57635C),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
