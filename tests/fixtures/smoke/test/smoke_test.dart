import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_smoke/model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('system SQLite loads through FFI and executes a query in memory', () {
    final library = DynamicLibrary.open('libsqlite3.so');
    expect(library.providesSymbol('sqlite3_open'), isTrue);
    final db = sqlite3.openInMemory();
    try {
      db.execute('CREATE TABLE smoke (value INTEGER NOT NULL)');
      db.execute('INSERT INTO smoke (value) VALUES (?)', [42]);
      expect(db.select('SELECT value FROM smoke').single['value'], 42);
      expect(db.select('SELECT COUNT(*) AS count FROM smoke').single['count'], 1);
    } finally {
      db.dispose();
    }
  });

  test('the generated JSON codec round trips a value', () {
    expect(Model.fromJson({'value': 42}).toJson(), {'value': 42});
  });
}
