import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../screens/select_prayer_people_page.dart';
import '../services/reminder_coordinator.dart';
import 'contact_avatar.dart';
import 'crisp_toast.dart';

/// A `#word` category tag in composer text.
final RegExp prayerHashtagPattern = RegExp(
  r'(?<!\S)#([\p{L}\p{N}_-]+)',
  unicode: true,
);

/// Splits composer [text] into the description to save (tags removed) and
/// the raw word of its last `#word` tag, if any.
({String description, String? tag}) parsePrayerRequestText(String text) {
  final matches = prayerHashtagPattern.allMatches(text).toList();
  final description = text
      .replaceAll(prayerHashtagPattern, '')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .trim();
  return (
    description: description,
    tag: matches.isEmpty ? null : matches.last.group(1),
  );
}

/// Turns a tag word into a category: reuses an existing category that
/// matches case-insensitively, otherwise capitalises it. `_` reads as a space.
String categoryFromTag(String tag, Iterable<String> existingCategories) {
  final name = tag.replaceAll('_', ' ');
  for (final existing in existingCategories) {
    if (existing.toLowerCase() == name.toLowerCase()) return existing;
  }
  return name[0].toUpperCase() + name.substring(1);
}

/// Quick-capture composer for creating (or editing) a [PrayerRequest].
///
/// New requests may be for several people; one separate request is created
/// per person. Typing `#word` sets the category.
class LogPrayerRequestSheet extends StatefulWidget {
  const LogPrayerRequestSheet({
    super.key,
    this.initialRequest,
    required this.availableContacts,
    this.initialContact,
    required this.onSaved,
  });

  /// Existing request to edit, if any.
  final PrayerRequest? initialRequest;

  /// Contacts the user can associate with the request.
  final List<Contact> availableContacts;

  /// Contact to preselect when launching the sheet. It cannot be removed.
  final Contact? initialContact;

  /// Called once for each request persisted (one per person when creating).
  final ValueChanged<PrayerRequest> onSaved;

  @override
  State<LogPrayerRequestSheet> createState() => _LogPrayerRequestSheetState();
}

class _LogPrayerRequestSheetState extends State<LogPrayerRequestSheet> {
  static final _dayFormat = DateFormat.MMMd();
  static final _fullDateFormat = DateFormat.yMMMd();

  late final _HashtagController _textController;
  late final TextEditingController _categoryController;
  late final TextEditingController _notesController;
  final FocusNode _textFocus = FocusNode();
  late DateTime _requestedAt;
  final List<String> _selectedIds = [];
  final Map<String, Contact> _contactLookup = {};
  PrayerPeopleStats _stats = const PrayerPeopleStats();
  List<String> _categories = [];
  String? _lastTag;
  bool _showDetails = false;
  bool _isSaving = false;

  bool get _isEditing => widget.initialRequest != null;

  Set<String> get _lockedIds => {
        if (widget.initialContact != null) widget.initialContact!.id,
      };

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRequest;
    _textController = _HashtagController(text: initial?.description ?? '');
    _categoryController = TextEditingController(text: initial?.category ?? '');
    _notesController = TextEditingController(
      text: initial?.reflectionNotes ?? '',
    );
    _requestedAt = initial?.requestedAt ?? DateTime.now();

    for (final contact in widget.availableContacts) {
      _contactLookup[contact.id] = contact;
    }
    if (initial != null) {
      _selectedIds.addAll(initial.participantIds);
    } else if (widget.initialContact != null) {
      _contactLookup[widget.initialContact!.id] = widget.initialContact!;
      _selectedIds.add(widget.initialContact!.id);
    } else if (widget.availableContacts.length == 1) {
      _selectedIds.add(widget.availableContacts.first.id);
    }

    _textController.addListener(_onTextChanged);
    _loadContext();
  }

  Future<void> _loadContext() async {
    final categories = await DBHelper().getPrayerCategories();
    final stats = _isEditing ? _stats : await PrayerPeopleStats.load();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _stats = stats;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final tag = parsePrayerRequestText(_textController.text).tag;
    if (tag != _lastTag) {
      if (tag != null) {
        _categoryController.text = categoryFromTag(tag, _categories);
      } else if (_lastTag != null &&
          _categoryController.text == categoryFromTag(_lastTag!, _categories)) {
        _categoryController.clear();
      }
      _lastTag = tag;
    }
    setState(() {});
  }

  void _insertHash() {
    final value = _textController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final before = value.text.substring(0, selection.start);
    final needsSpace =
        before.isNotEmpty && !before.endsWith(' ') && !before.endsWith('\n');
    final insert = needsSpace ? ' #' : '#';
    _textController.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, insert),
      selection: TextSelection.collapsed(
        offset: selection.start + insert.length,
      ),
    );
    _textFocus.requestFocus();
  }

  Future<void> _pickRequestedDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _requestedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Requested on',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _requestedAt = DateTime(selected.year, selected.month, selected.day);
    });
  }

  Future<void> _openPeoplePicker() async {
    final result = await SelectPrayerPeoplePage.open(
      context,
      initialSelectedIds: List.of(_selectedIds),
      lockedIds: _lockedIds,
    );
    if (result == null || !mounted) return;
    setState(() {
      for (final contact in result) {
        _contactLookup[contact.id] = contact;
      }
      _selectedIds
        ..clear()
        ..addAll(result.map((c) => c.id));
    });
  }

  void _addPerson(String id) {
    setState(() {
      if (!_selectedIds.contains(id)) _selectedIds.add(id);
    });
  }

  void _removePerson(String id) {
    setState(() => _selectedIds.remove(id));
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final description =
        parsePrayerRequestText(_textController.text).description;
    if (description.isEmpty) {
      CrispToast.show(context, 'Write a short prayer request first.');
      return;
    }
    if (_selectedIds.isEmpty) {
      CrispToast.show(context, 'Choose who this request is for.');
      return;
    }

    setState(() => _isSaving = true);
    final category = _categoryController.text.trim();
    final notes = _notesController.text.trim();
    final initial = widget.initialRequest;

    try {
      final List<PrayerRequest> saved;
      if (initial == null) {
        final template = PrayerRequest(
          participantIds: const [],
          description: description,
          status: PrayerRequestStatus.pending,
          requestedAt: _requestedAt,
          category: category.isEmpty ? null : category,
          reflectionNotes: notes.isEmpty ? null : notes,
        );
        final contactIds = List.of(_selectedIds);
        final ids = await DBHelper()
            .prayerRequestDao
            .createForEachContact(template, contactIds);
        saved = [
          for (var i = 0; i < ids.length; i++)
            template.copyWith(id: ids[i], participantIds: [contactIds[i]]),
        ];
      } else {
        final updated = PrayerRequest(
          id: initial.id,
          syncId: initial.syncId,
          participantIds: initial.participantIds,
          interactionId: initial.interactionId,
          description: description,
          status: initial.status,
          requestedAt: _requestedAt,
          answeredAt: initial.answeredAt,
          archivedAt: initial.archivedAt,
          category: category.isEmpty ? null : category,
          reflectionNotes: notes.isEmpty ? null : notes,
        );
        await DBHelper().updatePrayerRequest(updated);
        saved = [updated];
      }

      for (final request in saved) {
        for (final contactId in request.participantIds) {
          final contact = _contactLookup[contactId];
          if (contact != null) {
            await ReminderCoordinator().syncPrayerRequestReminder(
              contact,
              request,
            );
          }
        }
      }
      saved.forEach(widget.onSaved);

      if (!mounted) return;
      Navigator.of(context).pop(initial == null ? 'created' : 'updated');
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Failed to save prayer request: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDay(DateTime date) {
    return date.year == DateTime.now().year
        ? _dayFormat.format(date)
        : _fullDateFormat.format(date);
  }

  bool get _isRequestedToday {
    final now = DateTime.now();
    return _requestedAt.year == now.year &&
        _requestedAt.month == now.month &&
        _requestedAt.day == now.day;
  }

  List<Contact> get _suggestions {
    if (_isEditing) return const [];
    final candidates = _contactLookup.values
        .where((c) => !_selectedIds.contains(c.id) && _stats.isActive(c.id))
        .toList()
      ..sort((a, b) {
        final onList = (_stats.onPrayerList.contains(b.id) ? 1 : 0) -
            (_stats.onPrayerList.contains(a.id) ? 1 : 0);
        if (onList != 0) return onList;
        final open =
            (_stats.openCounts[b.id] ?? 0) - (_stats.openCounts[a.id] ?? 0);
        if (open != 0) return open;
        return prayerPersonName(a)
            .toLowerCase()
            .compareTo(prayerPersonName(b).toLowerCase());
      });
    return candidates.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = [
      for (final id in _selectedIds)
        if (_contactLookup[id] != null) _contactLookup[id]!,
    ];
    final suggestions = _suggestions;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: colors.secondaryText,
    );

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.manual,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (_isEditing ? 'For' : 'Who is this for?')
                                    .toUpperCase(),
                                style: labelStyle,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Close',
                              visualDensity: VisualDensity.compact,
                              color: colors.secondaryText,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final contact in selected)
                              _PersonChip(
                                name: prayerPersonName(contact),
                                onRemove: _isEditing ||
                                        _lockedIds.contains(contact.id)
                                    ? null
                                    : () => _removePerson(contact.id),
                              ),
                            if (!_isEditing)
                              _AddPersonChip(onTap: _openPeoplePicker),
                          ],
                        ),
                        if (selected.length > 1 && !_isEditing) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Saves as ${selected.length} separate requests, '
                            'one per person.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                        if (suggestions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          for (final contact in suggestions)
                            _SuggestionRow(
                              contact: contact,
                              meta: _stats.subtitleFor(contact.id),
                              onTap: () => _addPerson(contact.id),
                            ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _textController,
                          focusNode: _textFocus,
                          autofocus: !_isEditing,
                          minLines: 3,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 16,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: 'What can you pray for? Add a #category',
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: colors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: colors.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        if (!_isRequestedToday && !_showDetails)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _pickRequestedDate,
                              icon: const Icon(Icons.event_outlined, size: 16),
                              label: Text(
                                'Requested ${_formatDay(_requestedAt)}',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: colors.secondaryText,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                            ),
                          ),
                        if (_showDetails) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _categoryController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Category (optional)',
                            ),
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            icon: Icons.event_outlined,
                            label: 'Requested',
                            value: _isRequestedToday
                                ? 'Today, ${_formatDay(_requestedAt)}'
                                : _formatDay(_requestedAt),
                            onTap: _pickRequestedDate,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _notesController,
                            minLines: 2,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (!_isEditing) ...[
                      _ToolButton(
                        tooltip: 'Choose people',
                        onPressed: _openPeoplePicker,
                        child: const Icon(Icons.person_add_alt, size: 20),
                      ),
                      const SizedBox(width: 6),
                    ],
                    _ToolButton(
                      tooltip: 'Add a category',
                      onPressed: _insertHash,
                      child: const Text(
                        '#',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ToolButton(
                      tooltip: 'Set requested date',
                      onPressed: _pickRequestedDate,
                      child: const Icon(Icons.event_outlined, size: 20),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _showDetails = !_showDetails),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(
                            _showDetails ? 'Fewer details' : 'More details',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    _SaveButton(
                      count: _isEditing ? 1 : _selectedIds.length,
                      isSaving: _isSaving,
                      onPressed:
                          _textController.text.trim().isEmpty ? null : _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Highlights `#word` category tags as tokens while typing.
class _HashtagController extends TextEditingController {
  _HashtagController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Leave IME composition styling (e.g. CJK input) to the default.
    if (withComposing &&
        value.isComposingRangeValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final tagStyle = (style ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
      backgroundColor: colors.cardBorder,
    );
    final children = <TextSpan>[];
    var cursor = 0;
    for (final match in prayerHashtagPattern.allMatches(text)) {
      if (match.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      children.add(TextSpan(text: match.group(0), style: tagStyle));
      cursor = match.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.name, this.onRemove});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: EdgeInsets.only(left: 10, right: onRemove == null ? 10 : 2),
      decoration: BoxDecoration(
        color: colors.greenTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.onPrimaryContainer,
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove $name',
              icon: const Icon(Icons.close, size: 16),
              color: colors.onPrimaryContainer,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _AddPersonChip extends StatelessWidget {
  const _AddPersonChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: StadiumBorder(side: BorderSide(color: colors.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: colors.primary),
                const SizedBox(width: 4),
                Text(
                  'Add person',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
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

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.contact,
    required this.meta,
    required this.onTap,
  });

  final Contact contact;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              ContactAvatar(contact: contact, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prayerPersonName(contact),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Text(
                meta,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: colors.hairline,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(color: colors.iconColor),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: colors.iconColor),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.count,
    required this.isSaving,
    required this.onPressed,
  });

  final int count;
  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(colors.onPrimary),
      ),
    );
    final style = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: count > 1 ? const StadiumBorder() : const CircleBorder(),
      padding: count > 1
          ? const EdgeInsets.symmetric(horizontal: 18)
          : EdgeInsets.zero,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );
    final handler = isSaving ? null : onPressed;

    if (count > 1) {
      return FilledButton(
        onPressed: handler,
        style: style,
        child: isSaving ? progress : Text('Save $count'),
      );
    }
    return Tooltip(
      message: 'Save request',
      child: FilledButton(
        onPressed: handler,
        style: style,
        child: isSaving
            ? progress
            : const Icon(Icons.check, size: 22, semanticLabel: 'Save request'),
      ),
    );
  }
}
