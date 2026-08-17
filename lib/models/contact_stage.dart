/// The relationship stages a contact can occupy, matching the BNPB design's
/// six-tier ladder. "Regular contact" is the line the period review cares
/// about most.
enum ContactStage {
  firstContact,
  secondContact,
  regularContact,
  groupMeeting,
  churchMeeting,
  laboring;

  String get label => switch (this) {
        ContactStage.firstContact => 'First contact',
        ContactStage.secondContact => 'Second contact',
        ContactStage.regularContact => 'Regular contact',
        ContactStage.groupMeeting => 'Group meeting',
        ContactStage.churchMeeting => 'Church meeting',
        ContactStage.laboring => 'Laboring',
      };

  /// Short chip label used on the contact detail stage selector.
  String get shortLabel => switch (this) {
        ContactStage.firstContact => 'First',
        ContactStage.secondContact => 'Second',
        ContactStage.regularContact => 'Regular',
        ContactStage.groupMeeting => 'Group',
        ContactStage.churchMeeting => 'Church',
        ContactStage.laboring => 'Laboring',
      };

  /// True when this stage is at or past the "regular contact" line.
  bool get isAtOrAboveRegular => index >= ContactStage.regularContact.index;

  static ContactStage? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim();
    for (final stage in ContactStage.values) {
      if (stage.label == normalized) return stage;
    }
    return null;
  }
}

/// Derives a sensible starting stage from how many interactions have been
/// logged with a contact. Used as the default until the user confirms one.
ContactStage defaultStageFor(int interactionCount) {
  if (interactionCount <= 1) return ContactStage.firstContact;
  if (interactionCount <= 3) return ContactStage.secondContact;
  return ContactStage.regularContact;
}
