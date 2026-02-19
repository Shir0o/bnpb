import 'dart:async';
import 'package:file_picker/file_picker.dart';
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
import '../../widgets/relationship_dialog.dart';

class MacOSContactDetailsPage extends StatefulWidget {
  final Contact? contact;

  const MacOSContactDetailsPage({super.key, this.contact});

  @override
  State<MacOSContactDetailsPage> createState() =>
      _MacOSContactDetailsPageState();
}

class _MacOSContactDetailsPageState extends State<MacOSContactDetailsPage> {
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
  List<String> _photoCues = [];
  List<Relationship> _relationships = [];
  List<Interaction> _interactions = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _firstNameController = TextEditingController(text: contact?.firstName ?? '');
    _middleNameController =
        TextEditingController(text: contact?.middleName ?? '');
    _lastNameController = TextEditingController(text: contact?.lastName ?? '');
    _nicknameController = TextEditingController(text: contact?.nickname ?? '');
    _locationController = TextEditingController(text: contact?.location ?? '');
    _emailController = TextEditingController(text: contact?.email ?? '');
    _phoneController = TextEditingController(text: contact?.phone ?? '');
    _notesController = TextEditingController(text: contact?.notes ?? '');

    if (contact != null) {
      _photoCues = List.from(contact.recognitionPhotoUris);
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
      final relationships =
          await dbHelper.getRelationshipsForContact(widget.contact!.id);
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

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path != null) {
      setState(() {
        // For simplicity, we just keep the latest one as the avatar or add to list?
        // The design shows one main image. Let's prepend to the list so it becomes the primary.
        if (_photoCues.contains(path)) {
          _photoCues.remove(path);
        }
        _photoCues.insert(0, path);
      });
    }
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
        recognitionPhotoUris: _photoCues,
        // Preserve other fields
        firstMeetingNotes: widget.contact?.firstMeetingNotes,
        tags: widget.contact?.tags ?? [],
        recognitionKeywords: widget.contact?.recognitionKeywords ?? [],
        recognitionReminders: widget.contact?.recognitionReminders ?? [],
        interactions: _interactions, // Interactions are not edited here directly
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addRelationship() async {
    // We need to save the contact first if it's new, or handle ID generation.
    // If it's a new contact, we can't easily add relationships without an ID.
    // For now, let's require saving first or generate ID upfront.
    // We generated ID upfront in _saveContact logic, but here we might need it.

    if (widget.contact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please save the contact first.')),
      );
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
    return Scaffold(
      backgroundColor: Colors.white,
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
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        const SizedBox(height: 32),
                        // Contact Info Section
                        _buildContactInfoSection(),
                        const SizedBox(height: 32),
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        const SizedBox(height: 32),
                        // Notes Section
                        _buildNotesSection(),
                        const SizedBox(height: 32),
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        const SizedBox(height: 32),
                        // Interactions Section
                        _buildInteractionsSection(),
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
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white, // semi-transparent?
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back Button / Title
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: Color(0xFF007AFF)),
                label: Text(
                  'Contacts',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF007AFF),
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
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF007AFF) : Colors.white,
          foregroundColor: isPrimary ? Colors.white : const Color(0xFF374151),
          disabledBackgroundColor:
              isPrimary ? const Color(0xFF007AFF).withValues(alpha: 0.5) : null,
          elevation: 0,
          shadowColor: Colors.transparent,
          side: isPrimary
              ? null
              : const BorderSide(color: Color(0xFFD1D5DB)), // gray-300
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
                  color: isPrimary ? Colors.white : const Color(0xFF007AFF),
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  Widget _buildAvatar() {
    final hasPhoto = _photoCues.isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            Container(
              width: 112, // w-28
              height: 112, // h-28
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                image: hasPhoto
                    ? DecorationImage(
                        image: NetworkImage(_photoCues.first), // Simplified
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: !hasPhoto
                  ? Icon(Icons.person, size: 64, color: Colors.grey[400])
                  : null,
            ),
            // Edit Overlay (Always visible on hover ideally, but for simplicity always show "Edit" badge or relying on hover might be tricky in flutter web without logic)
            // Let's make a permanent small badge for now or standard Material InkWell behavior.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Edit',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
        _buildLabelInputRow('Nickname', _nicknameController,
            placeholder: 'e.g. Sally'),
      ],
    );
  }

  Widget _buildContactInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelInputRow(
          'Location',
          _locationController,
          icon: Icons.location_on,
        ),
        const SizedBox(height: 12),
        _buildLabelInputRow('Email', _emailController,
            inputType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _buildLabelInputRow('Phone', _phoneController,
            inputType: TextInputType.phone),
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
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280), // gray-500
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
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.grey[400]),
                      ),
                    ),
                  ..._relationships.map((rel) => _buildRelationshipItem(rel)),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _addRelationship,
                    icon: const Icon(Icons.add_circle,
                        size: 16, color: Color(0xFF16A34A)), // green-600
                    label: Text(
                      'add relationship',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF16A34A),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(fontSize: 13),
                      children: [
                        TextSpan(
                          text: '${rel.type}: ',
                          style: const TextStyle(
                              color: Color(0xFF6B7280)), // gray-500
                        ),
                        TextSpan(
                          text: otherName,
                          style: const TextStyle(
                            color: Color(0xFF007AFF), // primary
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
                icon: const Icon(Icons.remove_circle,
                    size: 18, color: Color(0xFF9CA3AF)), // gray-400
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
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _notesController,
            maxLines: 6,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[900]),
            decoration: InputDecoration(
              hintText: 'Add notes about this contact...',
              hintStyle:
                  GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
              filled: true,
              fillColor: const Color(0xFFFEFCE8).withValues(alpha: 0.5), // yellow-50/50
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF007AFF), width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractionsSection() {
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
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  color: const Color(0xFFF9FAFB), // gray-50
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text('Date',
                              style: _tableHeaderStyle())),
                      Expanded(
                          flex: 3,
                          child: Text('Type',
                              style: _tableHeaderStyle())),
                      Expanded(
                          flex: 1,
                          child: Text('Duration',
                              textAlign: TextAlign.right,
                              style: _tableHeaderStyle())),
                    ],
                  ),
                ),
                // Table Body
                if (_interactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No interactions yet',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey[400])),
                  )
                else
                  ..._interactions.take(5).map((interaction) {
                    return Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: Color(0xFFF3F4F6))),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              DateFormat.yMMMd()
                                  .format(interaction.occurredAt),
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey[900]),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Icon(getMediumIcon(interaction.medium),
                                    size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  _capitalize(interaction.medium),
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.grey[500]),
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
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                // Footer
                if (_interactions.isNotEmpty)
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9FAFB),
                      border: Border(
                          top: BorderSide(color: Color(0xFFF3F4F6))),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'View all history',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF007AFF),
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
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF6B7280),
      letterSpacing: 0.5,
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
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280), // gray-500
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
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[900]),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle:
                      GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                  contentPadding:
                      EdgeInsets.fromLTRB(8, 8, icon != null ? 32 : 8, 8),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: Color(0xFF007AFF), width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
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
                  child: Icon(icon, size: 16, color: Colors.grey[400]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
