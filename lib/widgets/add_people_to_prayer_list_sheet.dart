import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../main.dart'; // CrispColorScheme extension on ColorScheme
import '../models/contact.dart';

/// Bottom sheet for adding contacts to the single prayer list. Pops with the
/// list of newly selected contact ids (or null when cancelled).
class AddPeopleToPrayerListSheet extends StatefulWidget {
  const AddPeopleToPrayerListSheet({
    super.key,
    required this.onListIds,
    this.dbHelper,
  });

  /// Contacts already on the list; shown greyed and not selectable.
  final Set<String> onListIds;
  final DBHelper? dbHelper;

  static Future<List<String>?> show(
    BuildContext context, {
    required Set<String> onListIds,
    DBHelper? dbHelper,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddPeopleToPrayerListSheet(
        onListIds: onListIds,
        dbHelper: dbHelper,
      ),
    );
  }

  @override
  State<AddPeopleToPrayerListSheet> createState() =>
      _AddPeopleToPrayerListSheetState();
}

class _AddPeopleToPrayerListSheetState
    extends State<AddPeopleToPrayerListSheet> {
  late final DBHelper _dbHelper = widget.dbHelper ?? DBHelper();
  final Set<String> _selected = {};
  List<Contact> _contacts = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await _dbHelper.getContacts();
    contacts.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final rows = _contacts
        .where((c) => q.isEmpty || c.fullName.toLowerCase().contains(q))
        .toList();
    final count = _selected.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.hairline)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.switchOff,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 76,
                      height: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            foregroundColor: scheme.secondaryText,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Add to prayer list',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 76,
                      child: Text(
                        '$count selected',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SearchField(
                  hint: 'Search contacts',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(
                        child: Text(
                          'No contacts match.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.secondaryText,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final c = rows[i];
                          return _PickRow(
                            contact: c,
                            onList: widget.onListIds.contains(c.id),
                            selected: _selected.contains(c.id),
                            onTap: () => _toggle(c.id),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.hairline)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  disabledBackgroundColor: scheme.cardBorder,
                  disabledForegroundColor: scheme.secondaryText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: count == 0
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                child: Text(
                  count == 0
                      ? 'Select people to add'
                      : count == 1
                          ? 'Add 1 person'
                          : 'Add $count people',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.hairline,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 17, color: scheme.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: scheme.secondaryText),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.contact,
    required this.onList,
    required this.selected,
    required this.onTap,
  });

  final Contact contact;
  final bool onList;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onList ? 0.55 : 1,
      child: InkWell(
        onTap: onList ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.hairline)),
          ),
          child: Row(
            children: [
              CircleInitials(initials: contact.initials, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.fullName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (contact.location != null &&
                        contact.location!.isNotEmpty)
                      Text(
                        contact.location!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              if (onList)
                Text(
                  'On list',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.secondaryText,
                  ),
                )
              else
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.transparent,
                    border: selected
                        ? null
                        : Border.all(color: scheme.switchOff, width: 2),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 15, color: scheme.onPrimary)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round initials avatar used by the prayer list and add-people sheet.
class CircleInitials extends StatelessWidget {
  const CircleInitials({super.key, required this.initials, this.size = 42});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(shape: BoxShape.circle, color: scheme.greenTint),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: scheme.primary,
        ),
      ),
    );
  }
}
