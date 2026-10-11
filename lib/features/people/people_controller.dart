import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../logic/turkish_collation.dart';
import '../../models/models.dart';

/// Kişi kaldırma isteğinin sonucu.
enum RemovalOutcome {
  /// Hiçbir planda geçmediği için kalıcı olarak silindi.
  deleted,

  /// Bir ay planında geçtiği için silinmedi, pasif yapıldı.
  deactivated,

  /// Zaten pasifti ve bir planda geçtiği için silinemez; değişiklik yok.
  keptInactive,
}

/// Kişi listesinin durumu: tüm kişiler, Türkçe alfabe sırasıyla.
class PeopleController extends Notifier<List<Person>> {
  static const _uuid = Uuid();

  @override
  List<Person> build() => ref.watch(peopleRepositoryProvider).getAll();

  /// Yeni kişi ekler, kimliği üretir.
  Future<Person> add({
    required String name,
    required Role role,
    bool isActive = true,
  }) async {
    final person = Person(
      id: _uuid.v4(),
      name: _cleanName(name),
      role: role,
      isActive: isActive,
    );
    await _save(person);
    return person;
  }

  /// Var olan kişiyi günceller.
  Future<void> update(Person person) =>
      _save(person.copyWith(name: _cleanName(person.name)));

  /// Aynı adla (büyük/küçük harf ve boşluk farkı gözetmeden) başka bir kişi
  /// var mı? Düzenlenen kişinin kendisi [exceptId] ile hariç tutulur.
  bool isNameTaken(String name, {String? exceptId}) {
    final normalized = normalizeName(name);
    return state.any(
      (p) => p.id != exceptId && normalizeName(p.name) == normalized,
    );
  }

  /// Kişi herhangi bir ay planında (istenmeyen gün ya da nöbet) geçiyor mu?
  bool isReferenced(String personId) =>
      ref.read(monthPlanRepositoryProvider).isPersonReferenced(personId);

  /// Kişiyi kaldırır: bir planda geçiyorsa silmek yerine pasifleştirir.
  Future<RemovalOutcome> remove(String personId) async {
    final repo = ref.read(peopleRepositoryProvider);
    final RemovalOutcome outcome;
    if (!isReferenced(personId)) {
      // Önce durumdan çıkar: kaydırılan satır aynı karede listeden kalkmalı.
      state = state.where((p) => p.id != personId).toList();
      await repo.delete(personId);
      outcome = RemovalOutcome.deleted;
    } else if (repo.getById(personId)?.isActive ?? false) {
      await repo.deactivate(personId);
      outcome = RemovalOutcome.deactivated;
    } else {
      outcome = RemovalOutcome.keptInactive;
    }
    state = repo.getAll();
    return outcome;
  }

  Future<void> _save(Person person) async {
    final repo = ref.read(peopleRepositoryProvider);
    await repo.save(person);
    state = repo.getAll();
  }

  static String _cleanName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

final peopleProvider = NotifierProvider<PeopleController, List<Person>>(
  PeopleController.new,
);
