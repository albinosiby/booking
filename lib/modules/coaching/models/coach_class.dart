import 'package:equatable/equatable.dart';

/// One student's visit in a coaching class.
class CoachStudent extends Equatable {
  const CoachStudent({
    required this.admissionId,
    required this.visitId,
    required this.version,
    required this.name,
    required this.attendance,
    required this.markable,
    this.reference = '',
    this.phone,
  });
  factory CoachStudent.fromJson(Map<String, dynamic> j) => CoachStudent(
    admissionId: j['admission_id'],
    visitId: j['visit_id'],
    version: j['version'],
    name: j['name'] ?? 'Student',
    reference: j['reference'] ?? '',
    phone: j['phone'],
    attendance: j['attendance'] ?? 'unmarked',
    markable: j['markable'] == true,
  );
  final String admissionId, visitId, name, reference, attendance;
  final String? phone;
  final int version;

  /// Whether the coach may make the first mark now; corrections are the
  /// owner's, from the admission.
  final bool markable;
  @override
  List<Object?> get props => [
    admissionId,
    visitId,
    version,
    name,
    reference,
    phone,
    attendance,
    markable,
  ];
}

/// Students of one plan on one space at one time.
class CoachClass extends Equatable {
  CoachClass({
    required this.key,
    required this.businessName,
    required this.planName,
    required this.spaceName,
    required this.localStart,
    required this.localEnd,
    Iterable<CoachStudent> students = const [],
  }) : students = List.unmodifiable(students);
  factory CoachClass.fromJson(Map<String, dynamic> j) => CoachClass(
    key: j['key'],
    businessName: j['business_name'],
    planName: j['plan_name'],
    spaceName: j['space_name'],
    localStart: j['local_start'],
    localEnd: j['local_end'],
    students: (j['students'] as List).map(
      (s) => CoachStudent.fromJson(Map<String, dynamic>.from(s)),
    ),
  );
  final String key, businessName, planName, spaceName;

  /// Local `YYYY-MM-DDTHH:MM` in the business time zone.
  final String localStart, localEnd;
  final List<CoachStudent> students;
  String get time => '${localStart.substring(11)}–${localEnd.substring(11)}';
  int count(String attendance) =>
      students.where((s) => s.attendance == attendance).length;
  @override
  List<Object?> get props => [
    key,
    businessName,
    planName,
    spaceName,
    localStart,
    localEnd,
    students,
  ];
}
