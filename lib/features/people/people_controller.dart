import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../logic/turkish_collation.dart';
import '../../models/models.dart';

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
    bool isChargeNurse = false,
  }) async {
    final person = Person(
      id: _uuid.v4(),
      name: _cleanName(name),
      role: role,
      isActive: isActive,
      isChargeNurse: isChargeNurse,
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

  /// Kişiyi kalıcı olarak siler. Ay planlarında geçiyorsa oradaki nöbetleri
  /// geçmiş kaydı olarak kalır ve listelerde "Silinmiş kişi" diye görünür.
  Future<void> delete(String personId) async {
    final repo = ref.read(peopleRepositoryProvider);
    // Önce durumdan çıkar: kaydırılan satır aynı karede listeden kalkmalı.
    state = state.where((p) => p.id != personId).toList();
    await repo.delete(personId);
    state = repo.getAll();
  }

  /// Kişiyi pasif yapar: yeni listelere alınmaz, geçmiş listelerde adıyla
  /// kalır.
  Future<void> deactivate(String personId) async {
    final repo = ref.read(peopleRepositoryProvider);
    await repo.deactivate(personId);
    state = repo.getAll();
  }

  Future<void> _save(Person person) async {
    final repo = ref.read(peopleRepositoryProvider);
    // Sorumlu hemşire yalnızca hemşire olabilir ve tek kişidir: yenisi
    // işaretlenince öncekinin işareti kalkar.
    final saved = person.role == Role.nurse
        ? person
        : person.copyWith(isChargeNurse: false);
    if (saved.isChargeNurse) {
      for (final other in repo.getAll()) {
        if (other.id != saved.id && other.isChargeNurse) {
          await repo.save(other.copyWith(isChargeNurse: false));
        }
      }
    }
    await repo.save(saved);
    state = repo.getAll();
  }

  /// Aktif sorumlu hemşire (yoksa null).
  Person? get chargeNurse {
    for (final p in state) {
      if (p.isActive && p.isChargeNurse && p.role == Role.nurse) return p;
    }
    return null;
  }

  static String _cleanName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

final peopleProvider = NotifierProvider<PeopleController, List<Person>>(
  PeopleController.new,
);
