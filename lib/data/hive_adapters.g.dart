// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_adapters.dart';

// **************************************************************************
// AdaptersGenerator
// **************************************************************************

class RoleAdapter extends TypeAdapter<Role> {
  @override
  final typeId = 0;

  @override
  Role read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Role.nurse;
      case 1:
        return Role.radiologyTech;
      default:
        return Role.nurse;
    }
  }

  @override
  void write(BinaryWriter writer, Role obj) {
    switch (obj) {
      case Role.nurse:
        writer.writeByte(0);
      case Role.radiologyTech:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PersonAdapter extends TypeAdapter<Person> {
  @override
  final typeId = 1;

  @override
  Person read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Person(
      id: fields[0] as String,
      name: fields[1] as String,
      role: fields[2] as Role,
      isActive: fields[3] == null ? true : fields[3] as bool,
      colorValue: (fields[4] as num?)?.toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, Person obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.isActive)
      ..writeByte(4)
      ..write(obj.colorValue);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HolidayAdapter extends TypeAdapter<Holiday> {
  @override
  final typeId = 2;

  @override
  Holiday read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Holiday(
      date: fields[0] as DateTime,
      name: fields[1] as String,
      isHalfDay: fields[2] == null ? false : fields[2] as bool,
      isPredefined: fields[3] == null ? false : fields[3] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Holiday obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.isHalfDay)
      ..writeByte(3)
      ..write(obj.isPredefined);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HolidayAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DayAssignmentAdapter extends TypeAdapter<DayAssignment> {
  @override
  final typeId = 3;

  @override
  DayAssignment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DayAssignment(
      day: (fields[0] as num).toInt(),
      nurseIds: fields[1] == null
          ? const []
          : (fields[1] as List).cast<String>(),
      techId: fields[2] as String?,
      tech16bId: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DayAssignment obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.day)
      ..writeByte(1)
      ..write(obj.nurseIds)
      ..writeByte(2)
      ..write(obj.techId)
      ..writeByte(3)
      ..write(obj.tech16bId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayAssignmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MonthPlanAdapter extends TypeAdapter<MonthPlan> {
  @override
  final typeId = 4;

  @override
  MonthPlan read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MonthPlan(
      year: (fields[0] as num).toInt(),
      month: (fields[1] as num).toInt(),
      unavailableDays: fields[2] == null
          ? const {}
          : (fields[2] as Map).map(
              (dynamic k, dynamic v) =>
                  MapEntry(k as String, (v as List).cast<int>()),
            ),
      assignments: fields[3] == null
          ? const {}
          : (fields[3] as Map).cast<int, DayAssignment>(),
      generatedAt: fields[4] as DateTime?,
      isLocked: fields[5] == null ? false : fields[5] as bool,
      seed: (fields[6] as num?)?.toInt(),
      nurseOnly: fields[7] == null ? false : fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, MonthPlan obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.year)
      ..writeByte(1)
      ..write(obj.month)
      ..writeByte(2)
      ..write(obj.unavailableDays)
      ..writeByte(3)
      ..write(obj.assignments)
      ..writeByte(4)
      ..write(obj.generatedAt)
      ..writeByte(5)
      ..write(obj.isLocked)
      ..writeByte(6)
      ..write(obj.seed)
      ..writeByte(7)
      ..write(obj.nurseOnly);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthPlanAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RosterSettingsAdapter extends TypeAdapter<RosterSettings> {
  @override
  final typeId = 5;

  @override
  RosterSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RosterSettings(
      nursesPerDay: fields[0] == null ? 2 : (fields[0] as num).toInt(),
      techsPerDay: fields[1] == null ? 1 : (fields[1] as num).toInt(),
      shiftHours: fields[2] == null ? 24 : (fields[2] as num).toInt(),
      secondaryTechShiftHours: fields[10] == null
          ? 16
          : (fields[10] as num).toInt(),
      dailyRequiredHours: fields[3] == null ? 7 : (fields[3] as num).toDouble(),
      maxEveryOtherDayChain: fields[4] == null ? 2 : (fields[4] as num).toInt(),
      maxExtraOverAverage: (fields[5] as num?)?.toInt(),
      forbidConsecutiveDays: fields[6] == null ? true : fields[6] as bool,
      holidayCountsAsWeekend: fields[7] == null ? true : fields[7] as bool,
      halfDayHolidayIsHalfWorkday: fields[8] == null ? true : fields[8] as bool,
      halfDayRequiredHours: fields[9] == null
          ? 5
          : (fields[9] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, RosterSettings obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.nursesPerDay)
      ..writeByte(1)
      ..write(obj.techsPerDay)
      ..writeByte(2)
      ..write(obj.shiftHours)
      ..writeByte(3)
      ..write(obj.dailyRequiredHours)
      ..writeByte(4)
      ..write(obj.maxEveryOtherDayChain)
      ..writeByte(5)
      ..write(obj.maxExtraOverAverage)
      ..writeByte(6)
      ..write(obj.forbidConsecutiveDays)
      ..writeByte(7)
      ..write(obj.holidayCountsAsWeekend)
      ..writeByte(8)
      ..write(obj.halfDayHolidayIsHalfWorkday)
      ..writeByte(9)
      ..write(obj.halfDayRequiredHours)
      ..writeByte(10)
      ..write(obj.secondaryTechShiftHours);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
