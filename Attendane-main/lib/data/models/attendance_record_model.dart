// lib/data/models/attendance_record_model.dart
class AttendanceRecordModel {
  final String id;
  final String sessionId;
  final String studentEmail;
  final String studentId;
  final DateTime checkInTime;
  final String status; // 'present', 'late', 'absent'
  final double? faceMatchScore;
  final String? webcamImageUrl;
  final DateTime createdAt;

  AttendanceRecordModel({
    required this.id,
    required this.sessionId,
    required this.studentEmail,
    required this.studentId,
    required this.checkInTime,
    required this.status,
    this.faceMatchScore,
    this.webcamImageUrl,
    required this.createdAt,
  });

  factory AttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return AttendanceRecordModel(
      id: json['id'] ?? '',
      sessionId: json['session_id'] ?? '',
      studentEmail: json['student_email'] ?? '',
      studentId: json['student_id'] ?? '',
      checkInTime: DateTime.parse(json['check_in_time']),
      status: json['status'] ?? 'absent',
      faceMatchScore: json['face_match_score']?.toDouble(),
      webcamImageUrl: json['webcam_image_url'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'student_email': studentEmail,
      'student_id': studentId,
      'check_in_time': checkInTime.toIso8601String(),
      'status': status,
      'face_match_score': faceMatchScore,
      'webcam_image_url': webcamImageUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// สร้าง copy ของ AttendanceRecord พร้อมแก้ไขค่าใหม่
  AttendanceRecordModel copyWith({
    String? id,
    String? sessionId,
    String? studentEmail,
    String? studentId,
    DateTime? checkInTime,
    String? status,
    double? faceMatchScore,
    String? webcamImageUrl,
    DateTime? createdAt,
  }) {
    return AttendanceRecordModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentEmail: studentEmail ?? this.studentEmail,
      studentId: studentId ?? this.studentId,
      checkInTime: checkInTime ?? this.checkInTime,
      status: status ?? this.status,
      faceMatchScore: faceMatchScore ?? this.faceMatchScore,
      webcamImageUrl: webcamImageUrl ?? this.webcamImageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// ตรวจสอบว่าเป็นสถานะ present หรือ late (ถือว่าเข้าเรียน)
  bool get isAttended => status == 'present' || status == 'late';

  /// ตรวจสอบว่าเป็นสถานะ absent หรือไม่
  bool get isAbsent => status == 'absent';

  /// ตรวจสอบว่าเป็นสถานะ late หรือไม่
  bool get isLate => status == 'late';

  /// ตรวจสอบว่าเป็นสถานะ present หรือไม่
  bool get isPresent => status == 'present';

  /// ได้คะแนน face recognition หรือไม่
  bool get hasFaceMatch => faceMatchScore != null;

  /// คะแนน face recognition เป็นเปอร์เซ็นต์
  double get faceMatchPercentage => (faceMatchScore ?? 0.0) * 100;

  /// สีที่เหมาะสมสำหรับแสดงสถานะ
  String get statusColorHex {
    switch (status) {
      case 'present':
        return '#4CAF50'; // เขียว
      case 'late':
        return '#FF9800'; // ส้ม
      case 'absent':
        return '#F44336'; // แดง
      default:
        return '#9E9E9E'; // เทา
    }
  }

  /// ข้อความสถานะภาษาไทย
  String get statusInThai {
    switch (status) {
      case 'present':
        return 'มาทัน';
      case 'late':
        return 'มาสาย';
      case 'absent':
        return 'ขาด';
      default:
        return 'ไม่ทราบ';
    }
  }

  /// ข้อความสถานะภาษาอังกฤษ (พิมพ์ใหญ่)
  String get statusDisplayText {
    switch (status) {
      case 'present':
        return 'PRESENT';
      case 'late':
        return 'LATE';
      case 'absent':
        return 'ABSENT';
      default:
        return 'UNKNOWN';
    }
  }

  /// แสดงเวลาเช็คชื่อในรูปแบบที่อ่านง่าย
  String get formattedCheckInTime {
    return '${checkInTime.day.toString().padLeft(2, '0')}/'
           '${checkInTime.month.toString().padLeft(2, '0')}/'
           '${checkInTime.year} '
           '${checkInTime.hour.toString().padLeft(2, '0')}:'
           '${checkInTime.minute.toString().padLeft(2, '0')}';
  }

  /// แสดงเฉพาะเวลา (ชั่วโมง:นาที)
  String get timeOnly {
    return '${checkInTime.hour.toString().padLeft(2, '0')}:'
           '${checkInTime.minute.toString().padLeft(2, '0')}';
  }

  /// แสดงเฉพาะวันที่
  String get dateOnly {
    return '${checkInTime.day.toString().padLeft(2, '0')}/'
           '${checkInTime.month.toString().padLeft(2, '0')}/'
           '${checkInTime.year}';
  }

  /// สร้าง AttendanceRecord สำหรับทดสอบ
  static AttendanceRecordModel createSample({
    String? status,
    String? studentEmail,
    String? studentId,
    DateTime? checkInTime,
  }) {
    return AttendanceRecordModel(
      id: 'sample_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: 'sample_session',
      studentEmail: studentEmail ?? 'student@example.com',
      studentId: studentId ?? 'STU001',
      checkInTime: checkInTime ?? DateTime.now(),
      status: status ?? 'present',
      faceMatchScore: 0.95,
      webcamImageUrl: null,
      createdAt: DateTime.now(),
    );
  }

  /// แสดงข้อมูลเป็น string สำหรับ debug
  @override
  String toString() {
    return 'AttendanceRecord(id: $id, student: $studentId, status: $status, time: $formattedCheckInTime)';
  }

  /// เปรียบเทียบว่า record เหมือนกันหรือไม่
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is AttendanceRecordModel &&
        other.id == id &&
        other.sessionId == sessionId &&
        other.studentEmail == studentEmail &&
        other.studentId == studentId &&
        other.checkInTime == checkInTime &&
        other.status == status &&
        other.faceMatchScore == faceMatchScore &&
        other.webcamImageUrl == webcamImageUrl &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        sessionId.hashCode ^
        studentEmail.hashCode ^
        studentId.hashCode ^
        checkInTime.hashCode ^
        status.hashCode ^
        (faceMatchScore?.hashCode ?? 0) ^
        (webcamImageUrl?.hashCode ?? 0) ^
        createdAt.hashCode;
  }
}