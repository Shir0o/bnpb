import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/contact.dart';
import '../../models/prayer_request.dart';

class PrayerDiaryEntry extends StatefulWidget {
  final PrayerRequest request;
  final List<Contact> contacts;
  final bool isEditing;
  final VoidCallback onEditStart;
  final ValueChanged<PrayerRequest> onEditSave;
  final VoidCallback onEditCancel;

  const PrayerDiaryEntry({
    super.key,
    required this.request,
    this.contacts = const [],
    required this.isEditing,
    required this.onEditStart,
    required this.onEditSave,
    required this.onEditCancel,
  });

  @override
  State<PrayerDiaryEntry> createState() => _PrayerDiaryEntryState();
}

class _PrayerDiaryEntryState extends State<PrayerDiaryEntry> {
  late TextEditingController _descriptionController;
  late PrayerRequestStatus _status;
  // Duration? _duration; // Future feature: track duration

  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.request.description,
    );
    _status = widget.request.status;
  }

  @override
  void didUpdateWidget(covariant PrayerDiaryEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing && !oldWidget.isEditing) {
      // Reset values when entering edit mode
      _descriptionController.text = widget.request.description;
      _status = widget.request.status;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final updatedRequest = widget.request.copyWith(
      description: _descriptionController.text,
      status: _status,
      // answeredAt logic could be handled here or in the parent
      answeredAt:
          _status == PrayerRequestStatus.answered &&
              widget.request.status != PrayerRequestStatus.answered
          ? DateTime.now()
          : widget.request.answeredAt,
    );
    widget.onEditSave(updatedRequest);
  }

  @override
  Widget build(BuildContext context) {
    // If editing, show the active edit card style
    if (widget.isEditing) {
      return _buildEditMode();
    }

    // Otherwise show the view mode with hover detection
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onDoubleTap: widget.onEditStart,
        child: _buildViewMode(),
      ),
    );
  }

  Widget _buildViewMode() {
    final timeStr = DateFormat(
      'h:mm a',
    ).format(widget.request.answeredAt ?? widget.request.requestedAt);
    final contactNames = widget.contacts.isEmpty
        ? 'Unknown'
        : widget.contacts.map((c) => c.displayName).join(', ');
    final isAnswered = widget.request.status == PrayerRequestStatus.answered;
    final isArchived = widget.request.status == PrayerRequestStatus.archived;

    return Container(
      // Match Stitch "entry-card" styling (padding, border)
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF5F5F7)), // separator-light
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Time • Contact Badge ... Edit Button
          Row(
            children: [
              // Time
              SizedBox(
                width: 60,
                child: Text(
                  timeStr,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[400], // text-gray-400
                  ),
                ),
              ),
              Text('•', style: TextStyle(color: Colors.grey[300])),
              const SizedBox(width: 8),

              // Contact Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF0D7CF2,
                  ).withValues(alpha: 0.1), // primary/10
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person,
                      size: 14,
                      color: Color(0xFF0D7CF2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      contactNames,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0D7CF2),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Status (if not pending) or Duration/Details
              if (widget.request.status != PrayerRequestStatus.pending) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAnswered)
                        const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Colors.green,
                          ),
                        ),
                      if (isArchived)
                        const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.inventory_2,
                            size: 12,
                            color: Colors.grey,
                          ),
                        ),
                      Text(
                        widget.request.status.label,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Edit Button (Show on hover)
              AnimatedOpacity(
                opacity: _isHovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: InkWell(
                  onTap: widget.onEditStart,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      'Edit',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0D7CF2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Content with vertical line
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFE5E5E5)), // gray-200
                ),
              ),
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                widget.request.description,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditMode() {
    final timeStr = DateFormat(
      'h:mm a',
    ).format(widget.request.answeredAt ?? widget.request.requestedAt);
    final contactNamesLabel = widget.contacts.isEmpty
        ? 'Unknown'
        : widget.contacts.map((c) => c.displayName).join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFF5F5F7))),
        // Active edit shadow
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withValues(alpha: 0.1),
            spreadRadius: 0,
            blurRadius: 0,
            offset: const Offset(0, 0),
          ),
          // Simulate the "ring" effect
          BoxShadow(
            color: const Color.fromRGBO(0, 122, 255, 0.15), // focus-ring color?
            spreadRadius: 2, // approximation
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  timeStr,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[400],
                  ),
                ),
              ),
              Text('•', style: TextStyle(color: Colors.grey[300])),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D7CF2).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person,
                      size: 14,
                      color: Color(0xFF0D7CF2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      contactNamesLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0D7CF2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Edit Area
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0xFFE5E5E5))),
                  ),
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    children: [
                      // Text Area
                      TextField(
                        controller: _descriptionController,
                        autofocus: true,
                        maxLines: null,
                        minLines: 3,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFF007AFF,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFF007AFF,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFF007AFF,
                              ).withValues(alpha: 0.6),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Controls Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Status Toggles
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Row(
                              children: [
                                _buildStatusToggle(
                                  PrayerRequestStatus.pending,
                                  'Pending',
                                  Icons.schedule,
                                ),
                                _buildStatusToggle(
                                  PrayerRequestStatus.answered,
                                  'Answered',
                                  Icons.check_circle,
                                  activeColor: Colors.green,
                                ),
                                _buildStatusToggle(
                                  PrayerRequestStatus.archived,
                                  'Archived',
                                  Icons.inventory_2,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Action Buttons
                          Row(
                            children: [
                              TextButton(
                                onPressed: widget.onEditCancel,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey[600],
                                  textStyle: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _handleSave,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D7CF2),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  textStyle: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusToggle(
    PrayerRequestStatus status,
    String label,
    IconData icon, {
    Color? activeColor,
  }) {
    final isSelected = _status == status;
    final color = activeColor ?? Colors.grey[700]!;

    return InkWell(
      onTap: () {
        setState(() {
          _status = status;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? color : Colors.grey[400]),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? color : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
