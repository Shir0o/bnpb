// Stored updatedAt strings are mixed: UTC with "Z" (current writers),
// offsetless local time (older builds, Drive-merged rows), and SQLite's
// "YYYY-MM-DD HH:MM:SS" column default. Comparing them as text against one
// cursor string skips rows, so SQL only narrows by calendar date (a day of
// slack covers any UTC offset) and the exact cut compares parsed instants.

/// SQL clause for the coarse date narrowing; pair with [updatedSinceDateArg].
const updatedSinceDateClause = 'substr(updatedAt, 1, 10) >= ?';

/// The "YYYY-MM-DD" bound for [updatedSinceDateClause]: the day before [since]
/// in UTC.
String updatedSinceDateArg(DateTime since) => since
    .toUtc()
    .subtract(const Duration(days: 1))
    .toIso8601String()
    .substring(0, 10);

/// The exact cut: rows whose parsed `updatedAt` instant is after [since].
List<Map<String, Object?>> rowsUpdatedAfter(
  List<Map<String, Object?>> rows,
  DateTime since,
) =>
    rows
        .where(
            (row) => DateTime.parse(row['updatedAt'] as String).isAfter(since))
        .toList();
