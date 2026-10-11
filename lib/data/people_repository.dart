import 'package:hive_ce/hive_ce.dart';

import '../logic/turkish_collation.dart';
import '../models/models.dart';

/// Kişileri saklar; anahtar kişinin kimliğidir.
class PeopleRepository {
  PeopleRepository(this._box);

  final Box<Person> _box;

  /// Tüm kişiler, ada göre Türkçe alfabe sırasıyla.
  List<Person> getAll() =>
      _box.values.toList()..sort((a, b) => compareTurkish(a.name, b.name));

  List<Person> getActive() => getAll().where((p) => p.isActive).toList();

  List<Person> getByRole(Role role, {bool activeOnly = true}) => getAll()
      .where((p) => p.role == role && (!activeOnly || p.isActive))
      .toList();

  Person? getById(String id) => _box.get(id);

  Future<void> save(Person person) => _box.put(person.id, person);

  Future<void> delete(String id) => _box.delete(id);

  /// Kişiyi silmeden pasifleştirir.
  Future<void> deactivate(String id) async {
    final person = _box.get(id);
    if (person != null) await save(person.copyWith(isActive: false));
  }

  /// Herhangi bir değişiklikte tetiklenir.
  Stream<BoxEvent> watch() => _box.watch();
}
