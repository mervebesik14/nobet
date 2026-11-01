import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Fazla mesai raporunun başlık ve imza bilgileri (`app_meta`).
class ReportInfo {
  const ReportInfo({
    this.institution = '',
    this.unit = '',
    this.preparedBy = '',
    this.preparedTitle = '',
    this.approvedBy = '',
    this.approvedTitle = '',
  });

  factory ReportInfo.fromJson(Map<dynamic, dynamic> json) => ReportInfo(
    institution: json['institution'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    preparedBy: json['preparedBy'] as String? ?? '',
    preparedTitle: json['preparedTitle'] as String? ?? '',
    approvedBy: json['approvedBy'] as String? ?? '',
    approvedTitle: json['approvedTitle'] as String? ?? '',
  );

  /// Hastane / kurum adı.
  final String institution;

  /// Birim (ör. "Acil Servis").
  final String unit;

  /// Hazırlayan ad soyad ve unvanı.
  final String preparedBy;
  final String preparedTitle;

  /// Onaylayan ad soyad ve unvanı.
  final String approvedBy;
  final String approvedTitle;

  Map<String, String> toJson() => {
    'institution': institution,
    'unit': unit,
    'preparedBy': preparedBy,
    'preparedTitle': preparedTitle,
    'approvedBy': approvedBy,
    'approvedTitle': approvedTitle,
  };
}

class ReportInfoNotifier extends Notifier<ReportInfo> {
  static const _key = 'reportInfo';

  @override
  ReportInfo build() {
    final v = ref.watch(hiveBoxesProvider).meta.get(_key);
    return v is Map ? ReportInfo.fromJson(v) : const ReportInfo();
  }

  Future<void> set(ReportInfo info) async {
    state = info;
    await ref.read(hiveBoxesProvider).meta.put(_key, info.toJson());
  }
}

final reportInfoProvider = NotifierProvider<ReportInfoNotifier, ReportInfo>(
  ReportInfoNotifier.new,
);
