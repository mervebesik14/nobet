import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';

// Adaptörleri yeniden üretmek için:
//   dart run build_runner build
// Alan eklerken/çıkarırken hive_adapters.g.yaml şeması da güncellenir;
// bu dosyayı da commit et ki eski kayıtlar okunabilmeye devam etsin.
@GenerateAdapters([
  AdapterSpec<Role>(),
  AdapterSpec<Person>(),
  AdapterSpec<Holiday>(),
  AdapterSpec<DayAssignment>(),
  AdapterSpec<MonthPlan>(),
  AdapterSpec<RosterSettings>(),
])
part 'hive_adapters.g.dart';
