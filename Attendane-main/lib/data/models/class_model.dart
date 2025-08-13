class ClassModel {
  final String id;
  final String name;
  final String teacherEmail;
  final String schedule;
  final String room;
  final String inviteCode;
  final DateTime createdAt;
  final bool isFavorite;

  ClassModel({
    required this.id,
    required this.name,
    required this.teacherEmail,
    required this.schedule,
    required this.room,
    required this.inviteCode,
    required this.createdAt,
    this.isFavorite = false,
  });

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['class_id'] ?? '',
      name: json['class_name'] ?? '',
      teacherEmail: json['teacher_email'] ?? '',
      schedule: json['schedule'] ?? '',
      room: json['room'] ?? '',
      inviteCode: json['invite_code'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      isFavorite: json['is_favorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'class_id': id,
      'class_name': name,
      'teacher_email': teacherEmail,
      'schedule': schedule,
      'room': room,
      'invite_code': inviteCode,
      'created_at': createdAt.toIso8601String(),
      'is_favorite': isFavorite,
    };
  }
}
