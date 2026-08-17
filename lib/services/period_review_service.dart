import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/contact_stage.dart';
import '../models/prayer_request.dart';
import '../models/stage_move.dart';
import 'contact_stage_service.dart';

/// Periods the period review can be computed over, mirroring the design's
/// Month / Semester / Year chips.
enum ReviewPeriod { month, semester, year }

extension ReviewPeriodX on ReviewPeriod {
  String get chip => switch (this) {
        ReviewPeriod.month => 'Month',
        ReviewPeriod.semester => 'Semester',
        ReviewPeriod.year => 'Year',
      };
}

enum ReviewMarkKind { attention, watch, bright }

/// A single observation surfaced on the review, tinted by how urgent it is.
class ReviewMark {
  const ReviewMark({
    required this.kind,
    required this.title,
    required this.detail,
  });

  final ReviewMarkKind kind;
  final String title;
  final String detail;
}

/// One bar of the movement funnel (contacts per stage).
class ReviewFunnelEntry {
  const ReviewFunnelEntry({
    required this.name,
    required this.count,
    required this.fraction,
    required this.color,
    this.note,
  });

  final String name;
  final int count;

  /// 0..1 width of the funnel bar relative to the largest tier.
  final double fraction;

  /// Light/dark swatch for the bar fill.
  final ColorLike color;

  /// Optional annotation drawn beside the tier name (e.g. "the line").
  final String? note;
}

/// A confirmed stage change that happened during the period.
class ReviewTransition {
  const ReviewTransition({
    required this.contactId,
    required this.name,
    required this.initials,
    required this.path,
    required this.forward,
  });

  final String contactId;
  final String name;
  final String initials;
  final String path;
  final bool forward;
}

/// One effort comparison row (this period vs the previous one).
class ReviewEffortRow {
  const ReviewEffortRow({
    required this.label,
    required this.value,
    required this.delta,
  });

  final String label;
  final int value;
  final int delta;
}

/// One of the four "Care" tiles.
class ReviewCareTile {
  const ReviewCareTile({
    required this.value,
    required this.label,
    required this.bad,
  });

  final String value;
  final String label;
  final bool bad;
}

/// Result of building a period review over the user's contacts.
class PeriodReviewData {
  const PeriodReviewData({
    required this.period,
    required this.periodLabel,
    required this.periodRange,
    required this.prevLabel,
    required this.noun,
    required this.hasContacts,
    required this.verdictKind,
    required this.verdictLabel,
    required this.verdict,
    required this.marks,
    required this.attentionCount,
    required this.funnel,
    required this.moveSummary,
    required this.transitions,
    required this.hasMoves,
    required this.noMoves,
    required this.noMovesTitle,
    required this.suggestions,
    required this.hasSuggestions,
    required this.intentionGoal,
    required this.intentionGot,
    required this.intentionPct,
    required this.intentionKind,
    required this.intentionText,
    required this.care,
    required this.effort,
    required this.absent,
  });

  final ReviewPeriod period;
  final String periodLabel;
  final String periodRange;
  final String prevLabel;
  final String noun;
  final bool hasContacts;

  final ReviewMarkKind verdictKind;
  final String verdictLabel;
  final String verdict;

  final List<ReviewMark> marks;
  final int attentionCount;

  final List<ReviewFunnelEntry> funnel;
  final String moveSummary;
  final List<ReviewTransition> transitions;
  final bool hasMoves;
  final bool noMoves;
  final String noMovesTitle;

  final List<StageSuggestion> suggestions;
  final bool hasSuggestions;

  final int intentionGoal;
  final int intentionGot;
  final double intentionPct;
  final ReviewMarkKind intentionKind;
  final String intentionText;

  final List<ReviewCareTile> care;
  final List<ReviewEffortRow> effort;
  final List<String> absent;

  /// The "is not adding up" alert on Home only fires when there is real data
  /// to review and at least one attention mark is present.
  bool get showAlert => hasContacts && attentionCount > 0;

  String get alertTitle => '$periodLabel is not adding up';

  String get alertSub =>
      '$attentionCount thing${attentionCount == 1 ? '' : 's'} needing '
      'attention · open the review';
}

/// Computes the period review from stored contacts and confirmed stage moves.
///
/// Movement is driven entirely by [StageMove]s — "nothing counts until you
/// confirm it" — while the funnel shows each contact's resolved stage
/// (confirmed, or a default derived from interaction count). Suggestions come
/// from [ContactStageService].
class PeriodReviewService {
  PeriodReviewService({
    DBHelper? dbHelper,
    DateTime Function()? now,
    ContactStageService? stageService,
  })  : _dbHelper = dbHelper ?? DBHelper(),
        _now = now ?? DateTime.now,
        _stageService = stageService ?? ContactStageService();

  final DBHelper _dbHelper;
  final DateTime Function() _now;
  final ContactStageService _stageService;

  /// "Regular contact" is the line a relationship must cross to count as
  /// rooted. Its index within [ContactStage.values].
  static const int rootStageIndex = 2;

  /// Pending prayer requests older than this count toward "open 60+ days".
  static const Duration stalePrayerAge = Duration(days: 60);

  /// A contact whose last interaction was longer ago than this is drifting.
  static const Duration driftThreshold = Duration(days: 60);

  /// Default "bring N people to regular contact" goals per period.
  static const Map<ReviewPeriod, int> intentionGoals = {
    ReviewPeriod.month: 1,
    ReviewPeriod.semester: 3,
    ReviewPeriod.year: 6,
  };

  Future<PeriodReviewData> build(
      {ReviewPeriod period = ReviewPeriod.month}) async {
    final contacts = await _dbHelper.getContacts();
    final now = _now();
    final window = _PeriodWindow.forPeriod(period, now);
    final prev = window.previous;

    final total = contacts.length;
    final contactLookup = {for (final c in contacts) c.id: c};

    int touched = 0;
    int never = 0;
    int ic = 0;
    int mins = 0;
    int ans = 0;
    int newp = 0;
    int openOld = 0;
    int drift = 0;

    final tiers = List.filled(ContactStage.values.length, 0);

    for (final contact in contacts) {
      final interactions = contact.interactions;
      final totalCount = interactions.length;
      if (totalCount == 0) never++;

      int inPeriod = 0;
      int preCount = 0;
      for (final interaction in interactions) {
        if (window.contains(interaction.occurredAt)) {
          inPeriod++;
          ic++;
          mins += interaction.durationMinutes ?? 0;
        } else {
          preCount++;
        }
      }

      if (inPeriod > 0) {
        touched++;
        if (preCount == 0) newp++;
      }

      tiers[contact.resolvedStage.index]++;

      DateTime? latest;
      for (final interaction in interactions) {
        if (latest == null || interaction.occurredAt.isAfter(latest)) {
          latest = interaction.occurredAt;
        }
      }
      if (latest != null && now.difference(latest) > driftThreshold) {
        drift++;
      }

      for (final prayer in contact.prayerRequests) {
        if (prayer.status == PrayerRequestStatus.answered &&
            prayer.answeredAt != null &&
            window.contains(prayer.answeredAt!)) {
          ans++;
        }
        if (prayer.status == PrayerRequestStatus.pending &&
            prayer.requestedAt.isBefore(now.subtract(stalePrayerAge))) {
          openOld++;
        }
      }
    }

    // Confirmed movement this period.
    final moves =
        (await _dbHelper.getStageMoves(start: window.start, end: window.end))
            .where((m) => contactLookup.containsKey(m.contactId))
            .toList();
    final transitions = moves.map((m) {
      final contact = contactLookup[m.contactId]!;
      final from = ContactStage.tryParse(m.fromStage);
      final to = ContactStage.tryParse(m.toStage);
      final forward = to != null && (from == null || to.index > from.index);
      return ReviewTransition(
        contactId: m.contactId,
        name: contact.displayName,
        initials: contact.initials,
        path: '${m.fromStage ?? 'New'} → ${m.toStage}',
        forward: forward,
      );
    }).toList();
    final rooted = moves.where((m) {
      final from = ContactStage.tryParse(m.fromStage);
      final to = ContactStage.tryParse(m.toStage);
      return to != null &&
          to.isAtOrAboveRegular &&
          (from == null || !from.isAtOrAboveRegular);
    }).length;
    final fwd = transitions.where((t) => t.forward).length;
    final bwd = transitions.length - fwd;

    final suggestions =
        await _stageService.buildSuggestions(contacts, now: now);

    // Previous-period numbers for the effort deltas.
    final prevCounts = _prevPeriodCounts(contacts, prev);

    final cov = total == 0 ? 0 : (touched * 100 / total).round();
    final peak = tiers.reduce((a, b) => a > b ? a : b);

    final marks = <ReviewMark>[];
    void add(ReviewMarkKind kind, String title, String detail) {
      marks.add(ReviewMark(kind: kind, title: title, detail: detail));
    }

    if (rooted == 0) {
      add(
        ReviewMarkKind.attention,
        'No one reached regular contact this ${_noun(period)}.',
        'People below the line stayed below it for the whole ${_noun(period)}.',
      );
    } else {
      add(
        ReviewMarkKind.bright,
        _rootedNames(moves, contactLookup, rooted) +
            (rooted == 1
                ? ' became a regular contact'
                : ' became regular contacts'),
        'Crossed the line in ${_periodLabel(period, now)}.',
      );
    }
    if (fwd > 0 && rooted == 0) {
      add(
        ReviewMarkKind.bright,
        '$fwd moved a step forward',
        moves
            .where((m) => _isForward(m))
            .map(
              (m) =>
                  '${contactLookup[m.contactId]!.displayName} → ${m.toStage}',
            )
            .join(' · '),
      );
    }
    if (suggestions.isNotEmpty) {
      add(
        ReviewMarkKind.watch,
        '${suggestions.length} stage change'
            '${suggestions.length == 1 ? '' : 's'} waiting on you',
        '${suggestions.map((s) => '${s.name} → ${s.to}').join(' · ')}. '
            'Confirm below.',
      );
    }
    if (cov < 50) {
      add(
        ReviewMarkKind.watch,
        'Only $cov% of your people heard from you',
        '$touched of $total contacts had any interaction this ${_noun(period)}.',
      );
    }
    if (never > 0) {
      add(
        ReviewMarkKind.watch,
        '$never contacts have never been logged',
        'Added once, then nothing.',
      );
    }
    if (openOld > 0) {
      add(
        ReviewMarkKind.watch,
        '$openOld prayer request${openOld == 1 ? '' : 's'} open 60+ days',
        'Raised, never updated.',
      );
    }
    if (drift > 0) {
      add(
        ReviewMarkKind.watch,
        '$drift drifting relationship${drift == 1 ? '' : 's'}',
        'Quiet for 60+ days.',
      );
    }

    final attentionCount =
        marks.where((m) => m.kind == ReviewMarkKind.attention).length;

    final markRank = {
      ReviewMarkKind.attention: 0,
      ReviewMarkKind.watch: 1,
      ReviewMarkKind.bright: 2,
    };
    marks.sort((a, b) => markRank[a.kind]!.compareTo(markRank[b.kind]!));

    // Verdict.
    final (ReviewMarkKind verdictKind, String verdict) = switch ((
      rooted > 0,
      fwd > 0,
      ic > 0,
    )) {
      (true, _, _) => (
          ReviewMarkKind.bright,
          '${_rootedNames(moves, contactLookup, rooted)} became a regular '
              'contact this ${_noun(period)}. That is the number that counts.',
        ),
      (false, true, _) => (
          ReviewMarkKind.watch,
          'Some movement — $fwd step${fwd == 1 ? '' : 's'} forward — but nobody '
              'crossed into regular contact.',
        ),
      (false, false, true) => (
          ReviewMarkKind.attention,
          'Faithful with the people you already have, but no one moved forward.',
        ),
      (false, false, false) => (
          ReviewMarkKind.attention,
          'A silent ${_noun(period)}. Nothing was logged at all.',
        ),
    };

    final verdictLabel = switch (verdictKind) {
      ReviewMarkKind.attention => 'Needs attention',
      ReviewMarkKind.watch => 'Mixed',
      ReviewMarkKind.bright => 'Good ${_noun(period)}',
    };

    // Movement funnel (resolved stages).
    final funnel = <ReviewFunnelEntry>[
      for (var i = 0; i < ContactStage.values.length; i++)
        ReviewFunnelEntry(
          name: ContactStage.values[i].label,
          count: tiers[i],
          fraction: peak == 0 ? 0 : (tiers[i] / peak).clamp(0.0, 1.0),
          color: _funnelShades[i],
          note: i == rootStageIndex ? 'the line' : null,
        ),
    ];

    // Intention.
    final goal = intentionGoals[period] ?? 1;
    final got = rooted;
    final intentionKind = got >= goal
        ? ReviewMarkKind.bright
        : got > 0
            ? ReviewMarkKind.watch
            : ReviewMarkKind.attention;
    final intentionText = 'Bring $goal ${goal == 1 ? 'person' : 'people'} to '
        'regular contact this ${_noun(period)}. Set at the start of '
        '${_periodLabel(period, now)}.';

    // Care.
    final care = <ReviewCareTile>[
      ReviewCareTile(
        value: '$cov%',
        label: 'of contacts heard from you',
        bad: cov < 50,
      ),
      ReviewCareTile(
          value: '$never', label: 'never logged once', bad: never > 0),
      ReviewCareTile(
        value: '$openOld',
        label: 'prayers open 60+ days',
        bad: openOld > 0,
      ),
      ReviewCareTile(
        value: '$drift',
        label: 'drifting relationships',
        bad: drift > 0,
      ),
    ];

    // Effort vs previous period.
    final effort = <ReviewEffortRow>[
      ReviewEffortRow(
        label: 'Interactions logged',
        value: ic,
        delta: ic - prevCounts.$1,
      ),
      ReviewEffortRow(
        label: 'Minutes invested',
        value: mins,
        delta: mins - prevCounts.$2,
      ),
      ReviewEffortRow(
        label: 'New people met',
        value: newp,
        delta: newp - prevCounts.$3,
      ),
      ReviewEffortRow(
        label: 'Prayers answered',
        value: ans,
        delta: ans - prevCounts.$4,
      ),
    ];

    // What didn't happen.
    final absent = <String>[];
    if (rooted == 0) {
      absent.add('Nobody crossed from second contact into regular contact.');
    }
    if (fwd == 0) absent.add('No one advanced a single stage.');
    if (newp == 0) absent.add('No new person entered the picture.');
    if (never > 0) {
      absent.add(
        '$never ${never == 1 ? 'person' : 'people'} you have met '
        '${never == 1 ? 'was' : 'were'} never followed up.',
      );
    }
    if (openOld > 0) {
      absent.add(
        '$openOld prayer request${openOld == 1 ? '' : 's'} went the '
        'whole ${_noun(period)} without an update.',
      );
    }
    if (total - touched > 0) {
      absent.add(
        '${total - touched} contact${total - touched == 1 ? '' : 's'} '
        'heard nothing from you at all.',
      );
    }
    if (absent.isEmpty) {
      absent.add('Nothing conspicuous was missed this ${_noun(period)}.');
    }

    return PeriodReviewData(
      period: period,
      periodLabel: _periodLabel(period, now),
      periodRange: window.rangeLabel,
      prevLabel: prev.label,
      noun: _noun(period),
      hasContacts: total > 0,
      verdictKind: verdictKind,
      verdictLabel: verdictLabel,
      verdict: verdict,
      marks: marks,
      attentionCount: attentionCount,
      funnel: funnel,
      moveSummary: '$fwd forward · $bwd back',
      transitions: transitions,
      hasMoves: moves.isNotEmpty,
      noMoves: moves.isEmpty,
      noMovesTitle: 'No stage changes recorded this ${_noun(period)}.',
      suggestions: suggestions,
      hasSuggestions: suggestions.isNotEmpty,
      intentionGoal: goal,
      intentionGot: got,
      intentionPct: goal == 0 ? 0 : (got / goal).clamp(0.0, 1.0),
      intentionKind: intentionKind,
      intentionText: intentionText,
      care: care,
      effort: effort,
      absent: absent,
    );
  }

  bool _isForward(StageMove m) {
    final from = ContactStage.tryParse(m.fromStage);
    final to = ContactStage.tryParse(m.toStage);
    return to != null && (from == null || to.index > from.index);
  }

  String _rootedNames(
    List<StageMove> moves,
    Map<String, Contact> lookup,
    int rooted,
  ) {
    final names = moves
        .where((m) {
          final from = ContactStage.tryParse(m.fromStage);
          final to = ContactStage.tryParse(m.toStage);
          return to != null &&
              to.isAtOrAboveRegular &&
              (from == null || !from.isAtOrAboveRegular);
        })
        .map((m) => lookup[m.contactId]!.displayName)
        .toList();
    if (names.isEmpty) return rooted == 1 ? 'Someone' : '$rooted people';
    return _joinNames(names);
  }

  /// (interactions, minutes, new people, answered prayers) for the previous
  /// period, used to build the effort deltas.
  (int, int, int, int) _prevPeriodCounts(
    List<Contact> contacts,
    _PeriodWindow prev,
  ) {
    var prevIc = 0;
    var prevMins = 0;
    var prevNewp = 0;
    var prevAns = 0;
    for (final contact in contacts) {
      var inPrev = 0;
      var beforePrev = 0;
      for (final interaction in contact.interactions) {
        if (prev.contains(interaction.occurredAt)) {
          inPrev++;
          prevIc++;
          prevMins += interaction.durationMinutes ?? 0;
        } else {
          beforePrev++;
        }
      }
      if (inPrev > 0 && beforePrev == 0) prevNewp++;
      for (final prayer in contact.prayerRequests) {
        if (prayer.status == PrayerRequestStatus.answered &&
            prayer.answeredAt != null &&
            prev.contains(prayer.answeredAt!)) {
          prevAns++;
        }
      }
    }
    return (prevIc, prevMins, prevNewp, prevAns);
  }

  String _noun(ReviewPeriod period) => switch (period) {
        ReviewPeriod.month => 'month',
        ReviewPeriod.semester => 'semester',
        ReviewPeriod.year => 'year',
      };

  String _periodLabel(ReviewPeriod period, DateTime now) {
    final year = now.year;
    switch (period) {
      case ReviewPeriod.month:
        return DateFormat('MMMM yyyy').format(now);
      case ReviewPeriod.semester:
        return now.month <= 6 ? 'January–June $year' : 'July–December $year';
      case ReviewPeriod.year:
        return '$year';
    }
  }

  static String _joinNames(Iterable<String> names) {
    final list = names.toList();
    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
  }

  static const List<ColorLike> _funnelShades = [
    ColorLike(0xFFC3CCC6, 0xFF4B564F),
    ColorLike(0xFFA9C4B6, 0xFF4F6A5D),
    ColorLike(0xFF7FC7A6, 0xFF3E6B55),
    ColorLike(0xFF2AA06E, 0xFF2F8B5F),
    ColorLike(0xFF0D7A4F, 0xFF22A36D),
    ColorLike(0xFF0B5F3E, 0xFF15885A),
  ];
}

/// Light/dark swatch used by the review's decorative bars. Kept as raw ints so
/// the service stays UI-free; the page resolves them against the theme.
class ColorLike {
  const ColorLike(this.light, this.dark);

  final int light;
  final int dark;
}

/// A [start, end) date window for a review period plus its display label.
class _PeriodWindow {
  const _PeriodWindow({
    required this.period,
    required this.start,
    required this.end,
    required this.rangeLabel,
    required this.label,
  });

  final ReviewPeriod period;
  final DateTime start;
  final DateTime end;
  final String rangeLabel;
  final String label;

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);

  _PeriodWindow get previous => _previousFor(period, start);

  static _PeriodWindow forPeriod(ReviewPeriod period, DateTime now) {
    final year = now.year;
    final month = now.month;
    switch (period) {
      case ReviewPeriod.month:
        final start = DateTime(year, month, 1);
        return _PeriodWindow(
          period: period,
          start: start,
          end: DateTime(year, month + 1, 1),
          rangeLabel:
              '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(DateTime(year, month + 1, 0))}',
          label: DateFormat('MMMM').format(DateTime(year, month - 1, 1)),
        );
      case ReviewPeriod.semester:
        final first = month <= 6;
        final start = DateTime(year, first ? 1 : 7, 1);
        return _PeriodWindow(
          period: period,
          start: start,
          end: DateTime(year, first ? 7 : 13, 1),
          rangeLabel:
              '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(DateTime(year, first ? 6 : 12, 30))}',
          label: 'Last half',
        );
      case ReviewPeriod.year:
        return _PeriodWindow(
          period: period,
          start: DateTime(year, 1, 1),
          end: DateTime(year + 1, 1, 1),
          rangeLabel: 'Jan 1 – Dec 31',
          label: '${year - 1}',
        );
    }
  }

  static _PeriodWindow _previousFor(ReviewPeriod period, DateTime start) {
    switch (period) {
      case ReviewPeriod.month:
        return forPeriod(
          ReviewPeriod.month,
          DateTime(start.year, start.month - 1, 1),
        );
      case ReviewPeriod.semester:
        return forPeriod(
          ReviewPeriod.semester,
          start.month == 1
              ? DateTime(start.year - 1, 7, 1)
              : DateTime(start.year, 1, 1),
        );
      case ReviewPeriod.year:
        return forPeriod(ReviewPeriod.year, DateTime(start.year - 1, 1, 1));
    }
  }
}
