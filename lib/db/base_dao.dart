import 'package:sqflite_sqlcipher/sqflite.dart';
import 'db_helper.dart';

abstract class BaseDao {
  final DBHelper dbHelper;

  BaseDao(this.dbHelper);

  Future<Database> get database => dbHelper.database;

  /// Utility to perform a query with a large IN clause by chunking it.
  /// This avoids SQLite limits on the number of host parameters.
  Future<List<Map<String, Object?>>> chunkedQuery({
    required String table,
    required String inColumn,
    required List<dynamic> values,
    int chunkSize = 900,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (values.isEmpty) return [];

    final db = await database;
    final allRows = <Map<String, Object?>>[];

    for (var i = 0; i < values.length; i += chunkSize) {
      final end = (i + chunkSize < values.length)
          ? i + chunkSize
          : values.length;
      final chunk = values.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');

      String finalWhere = '$inColumn IN ($placeholders)';
      List<Object?> finalWhereArgs = [...chunk];

      if (where != null) {
        finalWhere = '($finalWhere) AND ($where)';
        if (whereArgs != null) {
          finalWhereArgs.addAll(whereArgs);
        }
      }

      final rows = await db.query(
        table,
        where: finalWhere,
        whereArgs: finalWhereArgs,
      );
      allRows.addAll(rows);
    }

    return allRows;
  }
}
