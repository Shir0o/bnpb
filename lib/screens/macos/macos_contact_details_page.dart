import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../models/relationship.dart';
import '../../services/backup_service.dart';
import '../../services/reminder_coordinator.dart';
import 'contact_view_helpers.dart';
import '../../widgets/crisp_toast.dart';
import '../../widgets/relationship_dialog.dart';

class MacOSContactDetailsPage extends StatefulWidget {
  final Contact? contact;

  const MacOSContactDetailsPage({super.key, this.contact});

  @override
  State<MacOSContactDetailsPage> createState() =>
      _MacOSContactDetailsPageState();
}

class _MacOSContactDetailsPageState extends State<MacOSContactDetailsPage> {
  // Optimization: Cache DateFormat to avoid expensive parsing during build loops
  static final _dateFormat = DateFormat.yMMMd();

  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _firstNameController;
  late TextEditingController _middleNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _nicknameController;
  late TextEditingController _locationController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;

  // State
  List<Relationship> _relationships = [];
  List<Interaction> _interactions = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _firstNameController = TextEditingController(
      text: contact?.firstName ?? '',
    );
    _middleNameController = TextEditingController(
      text: contact?.middleName ?? '',
    );
    _lastNameController = TextEditingController(text: contact?.lastName ?? '');
    _nicknameController = TextEditingController(text: contact?.nickname ?? '');
    _locationController = TextEditingController(text: contact?.location ?? '');
    _emailController = TextEditingController(text: contact?.email ?? '');
    _phoneController = TextEditingController(text: contact?.phone ?? '');
    _notesController = TextEditingController(text: contact?.notes ?? '');

    if (contact != null) {
      _relationships = List.from(contact.relationships);
      // Sort interactions by date desc
      _interactions = List.from(contact.interactions)
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    }

    _loadReferenceData();
  }

  Future<void> _loadReferenceData() async {
    if (widget.contact == null) return;
    try {
      final dbHelper = DBHelper();
      // Reload relationships to ensure fresh data if needed, though widget.contact passes them.
      // But if we want to be sure about relationships from DB:
      final relationships = await dbHelper.getRelationshipsForContact(
        widget.contact!.id,
      );
      if (mounted) {
        setState(() {
          _relationships = relationships;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _locationController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final dbHelper = DBHelper();
      final contactId = widget.contact?.id ?? const Uuid().v4();

      final newContact = Contact(
        id: contactId,
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim().isEmpty
            ? null
            : _lastNameController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        // Preserve other fields
        firstMeetingNotes: widget.contact?.firstMeetingNotes,
        interactions:
            _interactions, // Interactions are not edited here directly
        relationships:
            _relationships, // Relationships might need saving separately or via Contact update
        prayerRequests: widget.contact?.prayerRequests ?? [],
        updatedAt: DateTime.now(),
      );

      if (widget.contact == null) {
        await dbHelper.insertContact(newContact);
      } else {
        await dbHelper.updateContact(newContact);
      }

      // Sync reminders & backup
      await ReminderCoordinator().syncSignificantDates(newContact);
      unawaited(BackupService().exportBackup());

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate change
      }
    } catch (e) {
      debugPrint('Error saving contact: $e');
      if (mounted) {
        CrispToast.show(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteContact() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(
            'Delete Contact',
            style: GoogleFonts.googleSans(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete this contact? This action cannot be undone.',
            style: GoogleFonts.googleSans(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.googleSans(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Delete',
                style: GoogleFonts.googleSans(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true && widget.contact?.id != null) {
      if (!mounted) return;
      setState(() => _isSaving = true);
      try {
        await DBHelper().deleteContact(widget.contact!.id);

        final deletedContact = widget.contact!.copyWith(
          deletedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await ReminderCoordinator().syncSignificantDates(deletedContact);
        unawaited(BackupService().exportBackup());

        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        debugPrint('Error deleting contact: $e');
        if (mounted) {
          CrispToast.show(context, 'Failed to delete: $e');
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  void _addRelationship() async {
    // We need to save the contact first if it's new, or handle ID generation.
    // If it's a new contact, we can't easily add relationships without an ID.
    // For now, let's require saving first or generate ID upfront.
    // We generated ID upfront in _saveContact logic, but here we might need it.

    if (widget.contact == null) {
      CrispToast.show(context, 'Please save the contact first.');
      return;
    }

    final dbHelper = DBHelper();
    final contacts = await dbHelper.getContacts();
    final availableContacts =
        contacts.where((c) => c.id != widget.contact!.id).toList();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => RelationshipDialog(
        currentContact: widget.contact!,
        availableContacts: availableContacts,
        onSave: (relationship) async {
          await dbHelper.upsertRelationship(relationship);
          _loadReferenceData(); // Refresh list
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _deleteRelationship(Relationship relationship) async {
    if (relationship.id == null) return;
    await DBHelper().deleteRelationship(relationship.id!);
    _loadReferenceData();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // Header
          _buildHeader(),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile Header (Image + Name Fields)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAvatar(),
                            const SizedBox(width: 32),
                            Expanded(child: _buildNameSection()),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Divider(height: 1, color: colorScheme.outlineVariant),
                        const SizedBox(height: 32),
                        // Contact Info Section
                        _buildContactInfoSection(),
                        const SizedBox(height: 32),
                        Divider(height: 1, color: colorScheme.outlineVariant),
                        const SizedBox(height: 32),
                        // Notes Section
                        _buildNotesSection(),
                        const SizedBox(height: 32),
                        Divider(height: 1, color: colorScheme.outlineVariant),
                        const SizedBox(height: 32),
                        // Interactions Section
                        _buildInteractionsSection(),
                        if (widget.contact != null) ...[
                          const SizedBox(height: 32),
                          Divider(height: 1, color: colorScheme.outlineVariant),
                          const SizedBox(height: 32),
                          _buildDeleteSection(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back Button / Title
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: colorScheme.primary,
                ),
                label: Text(
                  'Contacts',
                  style: GoogleFonts.googleSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          // Action Buttons
          Row(
            children: [
              _buildActionButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(context),
                isPrimary: false,
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                label: 'Done',
                onPressed: _isSaving ? null : _saveContact,
                isPrimary: true,
                isLoading: _isSaving,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? colorScheme.primary
              : colorScheme.surfaceContainerLowest,
          foregroundColor:
              isPrimary ? colorScheme.onPrimary : colorScheme.onSurface,
          disabledBackgroundColor:
              isPrimary ? colorScheme.primary.withValues(alpha: 0.5) : null,
          elevation: 0,
          shadowColor: Colors.transparent,
          side:
              isPrimary ? null : BorderSide(color: colorScheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4), // slightly rounded
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                      isPrimary ? colorScheme.onPrimary : colorScheme.primary,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.googleSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  Widget _buildAvatar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(Icons.person, size: 64, color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildNameSection() {
    return Column(
      children: [
        _buildLabelInputRow('First', _firstNameController),
        const SizedBox(height: 12),
        _buildLabelInputRow('Middle', _middleNameController),
        const SizedBox(height: 12),
        _buildLabelInputRow('Last', _lastNameController),
        const SizedBox(height: 12),
        _buildLabelInputRow(
          'Nickname',
          _nicknameController,
          placeholder: 'e.g. Sally',
        ),
      ],
    );
  }

  Widget _buildContactInfoSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelInputRow(
          'Location',
          _locationController,
          icon: Icons.location_on,
        ),
        const SizedBox(height: 12),
        _buildLabelInputRow(
          'Email',
          _emailController,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _buildLabelInputRow(
          'Phone',
          _phoneController,
          inputType: TextInputType.phone,
        ),
        const SizedBox(height: 20),
        // Relationships
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100, // Fixed label width matching others
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0, right: 12.0),
                child: Text(
                  'Relationships',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.googleSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_relationships.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'No relationships added',
                        style: GoogleFonts.googleSans(
                          fontSize: 13,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ..._relationships.map((rel) => _buildRelationshipItem(rel)),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _addRelationship,
                    icon: Icon(
                      Icons.add_circle,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    label: Text(
                      'add relationship',
                      style: GoogleFonts.googleSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRelationshipItem(Relationship rel) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOutgoing = rel.sourceContactId == widget.contact?.id;
    final otherId = isOutgoing ? rel.targetContactId : rel.sourceContactId;
    // We need to resolve name. For now, showing ID or we need to fetch name.
    // Ideally we have a cache or fetch them.
    // For simplicity, let's fetch name asynchronously or assume we can display something.
    // We'll use FutureBuilder for name resolution if needed, or better, pass a map.
    // But refetching every time is bad.
    // Let's just show "Contact ..." placeholder or handle it better later.
    // Wait, DB helper can give us the name if we fetch it.
    // For now, I'll use a FutureBuilder wrapper for the name.

    return FutureBuilder<Contact?>(
      future: DBHelper().getContactById(otherId),
      builder: (context, snapshot) {
        final otherName = snapshot.data?.displayName ?? 'Unknown Contact';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.googleSans(fontSize: 13),
                      children: [
                        TextSpan(
                          text: '${rel.type}: ',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        TextSpan(
                          text: otherName,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.remove_circle,
                  size: 18,
                  color: colorScheme.outline,
                ),
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _deleteRelationship(rel),
                tooltip: 'Remove',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotesSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0, right: 12.0),
            child: Text(
              'Notes',
              textAlign: TextAlign.right,
              style: GoogleFonts.googleSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _notesController,
            maxLines: 6,
            style: GoogleFonts.googleSans(
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Add notes about this contact...',
              hintStyle: GoogleFonts.googleSans(
                fontSize: 13,
                color: colorScheme.outline,
              ),
              filled: true,
              fillColor: colorScheme.tertiaryContainer.withValues(alpha: 0.28),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractionsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Padding(
            padding: const EdgeInsets.only(top: 0.0, right: 12.0),
            child: Text(
              'Interactions',
              textAlign: TextAlign.right,
              style: GoogleFonts.googleSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  color: colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text('Date', style: _tableHeaderStyle()),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Type', style: _tableHeaderStyle()),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Duration',
                          textAlign: TextAlign.right,
                          style: _tableHeaderStyle(),
                        ),
                      ),
                    ],
                  ),
                ),
                // Table Body
                if (_interactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No interactions yet',
                      style: GoogleFonts.googleSans(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  )
                else
                  ..._interactions.take(5).map((interaction) {
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colorScheme.outlineVariant),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              _dateFormat.format(interaction.occurredAt),
                              style: GoogleFonts.googleSans(
                                fontSize: 12,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Icon(
                                  getMediumIcon(interaction.medium),
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _capitalize(interaction.medium),
                                  style: GoogleFonts.googleSans(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              interaction.durationMinutes != null
                                  ? '${interaction.durationMinutes}m'
                                  : '-',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.googleSans(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                // Footer
                if (_interactions.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'View all history',
                      style: GoogleFonts.googleSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _tableHeaderStyle() {
    final colorScheme = Theme.of(context).colorScheme;
    return GoogleFonts.googleSans(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurfaceVariant,
    );
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;

  Widget _buildLabelInputRow(
    String label,
    TextEditingController controller, {
    String? placeholder,
    IconData? icon,
    TextInputType inputType = TextInputType.text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 100,
          child: Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: GoogleFonts.googleSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              TextFormField(
                controller: controller,
                keyboardType: inputType,
                style: GoogleFonts.googleSans(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: GoogleFonts.googleSans(
                    fontSize: 13,
                    color: colorScheme.outline,
                  ),
                  contentPadding: EdgeInsets.fromLTRB(
                    8,
                    8,
                    icon != null ? 32 : 8,
                    8,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLowest,
                ),
                validator: (value) {
                  if (label == 'First' &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Required';
                  }
                  return null;
                },
              ),
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Icon(icon, size: 16, color: colorScheme.outline),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: _isSaving ? null : _deleteContact,
        icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
        label: Text(
          'Delete Contact',
          style: GoogleFonts.googleSans(
            color: colorScheme.error,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
