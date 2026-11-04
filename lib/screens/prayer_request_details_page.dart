import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/crisp_toast.dart';
import 'select_prayer_people_page.dart';

/// Shows a single [PrayerRequest] and edits it in place.
///
/// Changes save automatically: status, dates and category right away, text
/// after a short pause and on leaving. Pops with `true` when anything was
/// saved or the request was deleted.
class PrayerRequestDetailsPage extends StatefulWidget {
  const PrayerRequestDetailsPage({
    super.key,
    required this.request,
    this.initialContacts = const [],
  });

  /// The prayer request being displayed.
  final PrayerRequest request;

  /// Contacts associated with the request.
  final List<Contact> initialContacts;

  @override
  State<PrayerRequestDetailsPage> createState() =>
      _PrayerRequestDetailsPageState();
}

class _PrayerRequestDetailsPageState extends State<PrayerRequestDetailsPage> {
  static final _dayFormat = DateFormat.MMMd();
  static final _weekdayFormat = DateFormat('EEE, MMM d');
  static final _fullDateFormat = DateFormat.yMMMd();
  static const _collapsedHistoryCount = 6;

  /// Last persisted state.
  late PrayerRequest _request;
  late final TextEditingController _textController;
  late final TextEditingController _notesController;
  late PrayerRequestStatus _status;
  late DateTime _requestedAt;
  // Kept while switching status so a mis-tap does not lose the dates; only
  // written when the status uses them.
  DateTime? _answeredAt;
  DateTime? _archivedAt;
  String? _category;
  List<Contact> _contacts = [];
  List<DateTime> _prayedDates = [];
  bool _showAllHistory = false;

  Timer? _saveTimer;
  Future<void> _saveChain = Future.value();
  int _writesInFlight = 0;
  bool _didUpdate = false;
  bool _isDeleting = false;

  bool get _isSaving => _saveTimer != null || _writesInFlight > 0;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    _request = request;
    _textController = TextEditingController(text: request.description);
    _notesController = TextEditingController(
      text: request.reflectionNotes ?? '',
    );
    _status = request.status;
    _requestedAt = request.requestedAt;
    _answeredAt = request.answeredAt;
    _archivedAt = request.archivedAt;
    _category = request.category;
    _contacts = List.of(widget.initialContacts);
    _textController.addListener(_scheduleSave);
    _notesController.addListener(_scheduleSave);
    _loadContacts();
    _loadPrayedDates();
  }

  @override
  void dispose() {
    if (_saveTimer != null) _saveNow(notify: false);
    _textController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await DBHelper().getContacts();
    if (!mounted) return;
    final lookup = {for (final c in contacts) c.id: c};
    setState(() {
      _contacts = _request.participantIds
          .map((id) => lookup[id])
          .whereType<Contact>()
          .toList();
    });
  }

  Future<void> _loadPrayedDates() async {
    final id = _request.id;
    if (id == null) return;
    final dates = await DBHelper().prayerRequestDao.getPrayedDates([id]);
    if (!mounted) return;
    setState(() => _prayedDates = dates[id] ?? []);
  }

  PrayerRequest _draft() {
    final text = _textController.text.trim();
    final notes = _notesController.text.trim();
    return PrayerRequest(
      id: _request.id,
      syncId: _request.syncId,
      participantIds: _request.participantIds,
      interactionId: _request.interactionId,
      // An emptied text field keeps the last saved description.
      description: text.isEmpty ? _request.description : text,
      status: _status,
      requestedAt: _requestedAt,
      answeredAt: _status == PrayerRequestStatus.pending ? null : _answeredAt,
      archivedAt: _status == PrayerRequestStatus.archived ? _archivedAt : null,
      category: _category,
      reflectionNotes: notes.isEmpty ? null : notes,
    );
  }

  bool _isUnchanged(PrayerRequest draft) {
    final saved = _request;
    return draft.description == saved.description &&
        draft.status == saved.status &&
        draft.requestedAt == saved.requestedAt &&
        draft.answeredAt == saved.answeredAt &&
        draft.archivedAt == saved.archivedAt &&
        draft.category == saved.category &&
        draft.reflectionNotes == saved.reflectionNotes;
  }

  void _scheduleSave() {
    // Controllers also notify on cursor moves; only edits need a save.
    if (_isDeleting || (_saveTimer == null && _isUnchanged(_draft()))) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
    setState(() {});
  }

  Future<void> _saveNow({bool notify = true}) {
    _saveTimer?.cancel();
    _saveTimer = null;
    final draft = _draft();
    if (_isDeleting || _isUnchanged(draft)) {
      if (notify && mounted) setState(() {});
      return _saveChain;
    }
    _writesInFlight++;
    _saveChain = _saveChain.then((_) => _write(draft));
    return _saveChain;
  }

  Future<void> _write(PrayerRequest draft) async {
    try {
      await DBHelper().updatePrayerRequest(draft);
      _request = draft;
      _didUpdate = true;
      for (final contact in _contacts) {
        await ReminderCoordinator().syncPrayerRequestReminder(contact, draft);
      }
    } catch (error) {
      if (mounted) CrispToast.show(context, 'Could not save changes: $error');
    } finally {
      _writesInFlight--;
      if (mounted) setState(() {});
    }
  }

  void _setStatus(PrayerRequestStatus status) {
    if (status == _status) return;
    final today = _today();
    setState(() {
      _status = status;
      if (status == PrayerRequestStatus.answered) _answeredAt ??= today;
      if (status == PrayerRequestStatus.archived) _archivedAt ??= today;
    });
    _saveNow();
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<DateTime?> _pickDate(DateTime initial, String helpText) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: helpText,
    );
    if (selected == null || !mounted) return null;
    return DateTime(selected.year, selected.month, selected.day);
  }

  Future<void> _pickRequestedDate() async {
    final date = await _pickDate(_requestedAt, 'Requested on');
    if (date == null) return;
    setState(() => _requestedAt = date);
    _saveNow();
  }

  Future<void> _pickAnsweredDate() async {
    final date = await _pickDate(_answeredAt ?? _today(), 'Answered on');
    if (date == null) return;
    setState(() => _answeredAt = date);
    _saveNow();
  }

  Future<void> _pickArchivedDate() async {
    final date = await _pickDate(_archivedAt ?? _today(), 'Archived on');
    if (date == null) return;
    setState(() => _archivedAt = date);
    _saveNow();
  }

  Future<void> _editCategory() async {
    final controller = TextEditingController(text: _category ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Health, Family'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final cleaned = result.trim();
    setState(() => _category = cleaned.isEmpty ? null : cleaned);
    _saveNow();
  }

  Future<void> _confirmDelete() async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this request?'),
        content: const Text(
          'It will be removed from your prayer diary, along with its history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = _request.id;
    if (id == null) return;

    _saveTimer?.cancel();
    _saveTimer = null;
    setState(() => _isDeleting = true);
    try {
      await _saveChain;
      await DBHelper().deletePrayerRequest(id);
      await ReminderCoordinator().cancelPrayerRequestReminder(_request);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      CrispToast.show(context, 'Could not delete request: $error');
    }
  }

  Future<void> _handlePop() async {
    await _saveNow();
    if (!mounted) return;
    Navigator.of(context).pop(_didUpdate);
  }

  String _formatDay(DateTime date) {
    return date.year == DateTime.now().year
        ? _dayFormat.format(date)
        : _fullDateFormat.format(date);
  }

  List<_HistoryEvent> _historyEvents() {
    final draft = _draft();
    final events = [
      if (draft.answeredAt != null)
        _HistoryEvent('Marked answered', draft.answeredAt!, emphasis: true),
      if (draft.archivedAt != null)
        _HistoryEvent('Archived', draft.archivedAt!, emphasis: true),
      for (final date in _prayedDates) _HistoryEvent('Prayed', date),
      _HistoryEvent('Requested', draft.requestedAt),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sectionLabel = theme.textTheme.labelSmall?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: colors.secondaryText,
    );
    final events = _historyEvents();
    final visibleEvents =
        _showAllHistory ? events : events.take(_collapsedHistoryCount).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(
          backgroundColor: colors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _handlePop,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Center(
                child: Text(
                  _isSaving ? 'Saving…' : 'Saved automatically',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 10),
            TextField(
              controller: _textController,
              minLines: 1,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: -0.2,
                color: colors.onSurface,
              ),
              decoration: const InputDecoration.collapsed(
                hintText: 'Prayer request',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  onTap: _pickRequestedDate,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Requested ${_formatDay(_requestedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.faint,
                      ),
                    ),
                  ),
                ),
                Text(
                  ' · Tap text to edit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('STATUS', style: sectionLabel),
            const SizedBox(height: 8),
            Semantics(
              label: 'Status',
              child: Row(
                children: [
                  for (final (index, option) in _statusOptions.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _StatusCard(
                        icon: option.icon,
                        label: option.label,
                        selected: _status == option.status,
                        onTap: () => _setStatus(option.status),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildStatusPanel(theme),
            const SizedBox(height: 20),
            Text('HISTORY', style: sectionLabel),
            const SizedBox(height: 10),
            for (final event in visibleEvents)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: event.emphasis ? colors.primary : colors.faint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        event.label,
                        style: TextStyle(fontSize: 13, color: colors.onSurface),
                      ),
                    ),
                    Text(
                      _formatDay(event.at),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            if (events.length > visibleEvents.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showAllHistory = true),
                  child: Text('Show all ${events.length}'),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: _isDeleting ? null : _confirmDelete,
                style: OutlinedButton.styleFrom(
                  backgroundColor: colors.dangerTint,
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.dangerBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Delete request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colors = theme.colorScheme;
    final metaStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colors.secondaryText,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final contact in _contacts)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ContactAvatar(contact: contact, radius: 13),
              const SizedBox(width: 8),
              Text(
                prayerPersonName(contact),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        InkWell(
          onTap: _editCategory,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Text(
              _category == null ? '· Add category' : '· $_category',
              style: metaStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    final (String? dateLabel, DateTime? date, VoidCallback? onPickDate) =
        switch (_status) {
      PrayerRequestStatus.answered => (
          'Answered on',
          _answeredAt,
          _pickAnsweredDate,
        ),
      PrayerRequestStatus.archived => (
          'Archived on',
          _archivedAt,
          _pickArchivedDate,
        ),
      PrayerRequestStatus.pending => (null, null, null),
    };
    final notesLabel = switch (_status) {
      PrayerRequestStatus.answered => 'How was it answered?',
      PrayerRequestStatus.archived => 'Why was it archived?',
      PrayerRequestStatus.pending => 'Notes',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dateLabel != null) ...[
            InkWell(
              onTap: onPickDate,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      date == null ? 'Set date' : _weekdayFormat.format(date),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            notesLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesController,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 15, height: 1.45),
            decoration: InputDecoration(
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.all(12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.cardBorder),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _statusOptions = [
  (
    status: PrayerRequestStatus.pending,
    label: 'Praying',
    icon: Icons.volunteer_activism_outlined,
  ),
  (
    status: PrayerRequestStatus.answered,
    label: 'Answered',
    icon: Icons.check_circle_outline,
  ),
  (
    status: PrayerRequestStatus.archived,
    label: 'Archived',
    icon: Icons.inventory_2_outlined,
  ),
];

class _HistoryEvent {
  _HistoryEvent(this.label, this.at, {this.emphasis = false});

  final String label;
  final DateTime at;
  final bool emphasis;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? colors.greenTint : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: selected
              ? BorderSide(color: colors.primary, width: 2)
              : BorderSide(color: colors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
