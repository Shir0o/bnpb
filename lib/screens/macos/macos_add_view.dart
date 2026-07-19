import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/db_helper.dart';
import '../../main.dart' show CrispColorScheme;
import '../../models/contact.dart';
import '../../models/relationship.dart';
import '../../services/backup_service.dart';
import '../../services/contact_service.dart';
import '../../services/reminder_coordinator.dart';
import '../../widgets/crisp_toast.dart';

enum _AddMode { contact, family }

const _standardRoles = <String>[
  'Parent',
  'Child',
  'Spouse',
  'Sibling',
  'Other'
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

/// Desktop "Add contact / Add family" section: a centered form with a
/// segmented tab switch, ported from the mobile `AddContactPage` /
/// `AddFamilyPage` field logic.
class MacOSAddView extends StatefulWidget {
  const MacOSAddView({super.key, this.onSaved});

  /// Invoked after a successful save — the shell routes back to Contacts.
  final VoidCallback? onSaved;

  @override
  State<MacOSAddView> createState() => _MacOSAddViewState();
}

class _MacOSAddViewState extends State<MacOSAddView> {
  _AddMode _mode = _AddMode.contact;

  // Add contact
  final _contactFormKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _nickname = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  bool _isSavingContact = false;

  // Add family
  final _familyFormKey = GlobalKey<FormState>();
  final _famFirstName = TextEditingController();
  final _famLastName = TextEditingController();
  final _famLocation = TextEditingController();
  final List<_MemberDraft> _members = [];
  bool _isSavingFamily = false;

  @override
  void initState() {
    super.initState();
    _addMember();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _nickname.dispose();
    _location.dispose();
    _notes.dispose();
    _famFirstName.dispose();
    _famLastName.dispose();
    _famLocation.dispose();
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  void _addMember() {
    setState(() {
      _members.add(_MemberDraft(defaultLastName: _famLastName.text));
    });
  }

  void _removeMember(int index) {
    setState(() => _members.removeAt(index).dispose());
  }

  Future<void> _saveContact() async {
    if (!_contactFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final newContact = Contact(
      id: DateTime.now().toIso8601String(),
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
      nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    setState(() => _isSavingContact = true);
    try {
      await DBHelper().insertContact(newContact);
      ContactService().notifyContactsChanged();
      if (!mounted) return;
      CrispToast.show(context, 'Contact saved: ${newContact.fullName}');
      unawaited(BackupService().exportBackup());
      await ReminderCoordinator().syncSignificantDates(newContact);
      if (!mounted) return;
      _firstName.clear();
      _lastName.clear();
      _nickname.clear();
      _location.clear();
      _notes.clear();
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Failed to save contact: $error');
    } finally {
      if (mounted) setState(() => _isSavingContact = false);
    }
  }

  Future<void> _saveFamily() async {
    if (!_familyFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    var stamp = DateTime.now();
    String nextId() {
      final id = stamp.toIso8601String();
      stamp = stamp.add(const Duration(microseconds: 1));
      return id;
    }

    final anchorLast = _famLastName.text.trim();
    final anchor = Contact(
      id: nextId(),
      firstName: _famFirstName.text.trim(),
      lastName: anchorLast.isEmpty ? null : anchorLast,
      location:
          _famLocation.text.trim().isEmpty ? null : _famLocation.text.trim(),
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
            lastName: last.isEmpty ? null : last),
      );

      final role = m.role;
      final customType = role == 'Other' ? m.customRole.text.trim() : null;
      final forwardType = role == 'Other' ? (customType ?? 'Other') : role;
      final inverseType = _inverseRole(role, customType: customType);

      relationships.add(Relationship(
          sourceContactId: anchor.id,
          targetContactId: memberId,
          type: forwardType));
      relationships.add(Relationship(
          sourceContactId: memberId,
          targetContactId: anchor.id,
          type: inverseType));
    }

    for (var i = 0; i < _members.length; i++) {
      if (_members[i].role != 'Child') continue;
      for (var j = i + 1; j < _members.length; j++) {
        if (_members[j].role != 'Child') continue;
        final a = memberContacts[i].id;
        final b = memberContacts[j].id;
        relationships.add(Relationship(
            sourceContactId: a, targetContactId: b, type: 'Sibling'));
        relationships.add(Relationship(
            sourceContactId: b, targetContactId: a, type: 'Sibling'));
      }
    }

    setState(() => _isSavingFamily = true);
    try {
      final dbHelper = DBHelper();
      final database = await dbHelper.database;
      await database.transaction((txn) async {
        await dbHelper.contactDao
            .upsertContactRow(txn, anchor, isUpdate: false);
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
      CrispToast.show(context, 'Saved $total contacts');
      unawaited(BackupService().exportBackup());
      unawaited(ReminderCoordinator().syncSignificantDates(anchor));
      for (final c in memberContacts) {
        unawaited(ReminderCoordinator().syncSignificantDates(c));
      }
      if (!mounted) return;
      _famFirstName.clear();
      _famLastName.clear();
      _famLocation.clear();
      for (final m in _members) {
        m.dispose();
      }
      _members.clear();
      _addMember();
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Failed to save family: $error');
    } finally {
      if (mounted) setState(() => _isSavingFamily = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(34),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          child: _modeTab(
                              colorScheme, _AddMode.contact, 'Add contact')),
                      Expanded(
                          child: _modeTab(
                              colorScheme, _AddMode.family, 'Add family')),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_mode == _AddMode.contact)
                  _buildContactForm(colorScheme)
                else
                  _buildFamilyForm(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeTab(ColorScheme colorScheme, _AddMode mode, String label) {
    final selected = _mode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color:
                  selected ? colorScheme.onSurface : colorScheme.secondaryText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactForm(ColorScheme colorScheme) {
    return Form(
      key: _contactFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'New contact',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.3),
              ),
              const Spacer(),
              _saveButton(colorScheme,
                  label: 'Save contact',
                  isSaving: _isSavingContact,
                  onTap: _saveContact),
            ],
          ),
          const SizedBox(height: 20),
          _sectionLabel(colorScheme, 'Identity'),
          const SizedBox(height: 10),
          _field(colorScheme,
              controller: _firstName,
              hint: 'First name',
              icon: Icons.person_outline,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter first name' : null),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _field(colorScheme,
                      controller: _lastName, hint: 'Last name (optional)')),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(colorScheme,
                      controller: _nickname, hint: 'Nickname (optional)')),
            ],
          ),
          const SizedBox(height: 10),
          _field(colorScheme,
              controller: _location,
              hint: 'Location (optional)',
              icon: Icons.place_outlined),
          const SizedBox(height: 20),
          _sectionLabel(colorScheme, 'Context'),
          const SizedBox(height: 10),
          _field(colorScheme,
              controller: _notes, hint: 'Notes (optional)', maxLines: 4),
        ],
      ),
    );
  }

  Widget _buildFamilyForm(ColorScheme colorScheme) {
    return Form(
      key: _familyFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'New family',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.3),
              ),
              const Spacer(),
              _saveButton(colorScheme,
                  label: 'Save all',
                  isSaving: _isSavingFamily,
                  onTap: _saveFamily),
            ],
          ),
          const SizedBox(height: 20),
          Text('Primary contact',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: colorScheme.onSurface)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceTint,
              border: Border.all(color: colorScheme.cardBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _field(colorScheme,
                    controller: _famFirstName,
                    hint: 'First name',
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter first name'
                        : null,
                    filled: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _field(colorScheme,
                            controller: _famLastName,
                            hint: 'Last name (optional)',
                            filled: true)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _field(colorScheme,
                            controller: _famLocation,
                            hint: 'Location (optional)',
                            filled: true)),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Used as default location for family members',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Family members',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: colorScheme.onSurface)),
          const SizedBox(height: 12),
          for (var i = 0; i < _members.length; i++) ...[
            _memberCard(colorScheme, i),
            const SizedBox(height: 12),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _addMember,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add_alt_1_outlined,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Add member',
                        style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberCard(ColorScheme colorScheme, int index) {
    final m = _members[index];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          border: Border.all(color: colorScheme.cardBorder),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _field(colorScheme,
                      controller: m.firstName,
                      hint: 'First name',
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null)),
              const SizedBox(width: 8),
              Expanded(
                  child: _field(colorScheme,
                      controller: m.lastName, hint: 'Last name')),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.close, size: 18, color: colorScheme.outline),
                onPressed:
                    _members.length > 1 ? () => _removeMember(index) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.start,
            children: _standardRoles
                .map((role) => _roleChip(colorScheme, m, role))
                .toList(),
          ),
          if (m.role == 'Other') ...[
            const SizedBox(height: 10),
            _field(colorScheme,
                controller: m.customRole,
                hint: 'Custom relationship',
                validator: (v) =>
                    m.role == 'Other' && (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null),
          ],
        ],
      ),
    );
  }

  Widget _roleChip(ColorScheme colorScheme, _MemberDraft m, String role) {
    final isSelected = m.role == role;
    return InkWell(
      onTap: () => setState(() => m.role = role),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.greenTint : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.cardBorder),
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

  Widget _sectionLabel(ColorScheme colorScheme, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.0,
          color: colorScheme.outline,
          fontWeight: FontWeight.w700),
    );
  }

  Widget _field(
    ColorScheme colorScheme, {
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    int maxLines = 1,
    String? Function(String?)? validator,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: filled ? colorScheme.surface : Colors.transparent,
        border: Border.all(color: colorScheme.cardBorder),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: maxLines > 1 ? 2 : 0),
              child: Icon(icon, size: 19, color: colorScheme.placeholder),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: TextFormField(
              controller: controller,
              maxLines: maxLines,
              textCapitalization: TextCapitalization.sentences,
              validator: validator,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: colorScheme.placeholder),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveButton(
    ColorScheme colorScheme, {
    required String label,
    required bool isSaving,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: isSaving ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(11)),
          child: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white)),
                )
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
