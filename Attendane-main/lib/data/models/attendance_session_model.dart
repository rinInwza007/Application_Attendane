// lib/data/models/attendance_session_model.dart
class AttendanceSessionModel {
  final String id;
  final String classId;
  final String teacherEmail;
  final DateTime startTime;
  final DateTime endTime;
  final int onTimeLimitMinutes; // เวลาที่ถือว่ามาทัน (นาที)
  final String status; // 'active', 'ended', 'cancelled'
  final DateTime createdAt;
  final DateTime? updatedAt;

  AttendanceSessionModel({
    required this.id,
    required this.classId,
    required this.teacherEmail,
    required this.startTime,
    required this.endTime,
    required this.onTimeLimitMinutes,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });


  factory AttendanceSessionModel.fromJson(Map<String, dynamic> json) {
    return AttendanceSessionModel(
      id: json['id'] ?? '',
      classId: json['class_id'] ?? '',
      teacherEmail: json['teacher_email'] ?? '',
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      onTimeLimitMinutes: json['on_time_limit_minutes'] ?? 30,
      status: json['status'] ?? 'active',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'class_id': classId,
      'teacher_email': teacherEmail,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'on_time_limit_minutes': onTimeLimitMinutes,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// สร้าง copy ของ AttendanceSession พร้อมแก้ไขค่าใหม่
  AttendanceSessionModel copyWith({
    String? id,
    String? classId,
    String? teacherEmail,
    DateTime? startTime,
    DateTime? endTime,
    int? onTimeLimitMinutes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AttendanceSessionModel(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      teacherEmail: teacherEmail ?? this.teacherEmail,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      onTimeLimitMinutes: onTimeLimitMinutes ?? this.onTimeLimitMinutes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// ตรวจสอบว่า session ยังทำงานอยู่หรือไม่
  bool get isActive => status == 'active' && DateTime.now().isBefore(endTime);
  
  /// ตรวจสอบว่า session จบแล้วหรือไม่
  bool get isEnded => status == 'ended' || DateTime.now().isAfter(endTime);
  
  /// ตรวจสอบว่า session ถูกยกเลิกหรือไม่
  bool get isCancelled => status == 'cancelled';
  
  /// เวลาสุดท้ายที่ถือว่ามาทัน
  DateTime get onTimeDeadline => startTime.add(Duration(minutes: onTimeLimitMinutes));
  
  /// ตรวจสอบว่าเวลาที่ให้มายังถือว่าทันหรือไม่
  bool isOnTime(DateTime checkInTime) {
    return checkInTime.isBefore(onTimeDeadline);
  }

  /// ระยะเวลาทั้งหมดของ session
  Duration get totalDuration => endTime.difference(startTime);

  /// เวลาที่เหลือของ session
  Duration get timeRemaining {
    final now = DateTime.now();
    if (now.isAfter(endTime)) {
      return Duration.zero;
    }
    return endTime.difference(now);
  }

  /// เวลาที่ผ่านไปแล้วของ session
  Duration get timeElapsed {
    final now = DateTime.now();
    if (now.isBefore(startTime)) {
      return Duration.zero;
    }
    final elapsed = now.difference(startTime);
    return elapsed > totalDuration ? totalDuration : elapsed;
  }

  /// เปอร์เซ็นต์ความคืบหน้าของ session
  double get progressPercentage {
    if (timeElapsed == Duration.zero) return 0.0;
    if (timeElapsed >= totalDuration) return 100.0;
    return (timeElapsed.inMinutes / totalDuration.inMinutes) * 100;
  }

  /// ตรวจสอบว่าอยู่ในช่วงเวลามาทันหรือไม่
  bool get isInOnTimePeriod {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(onTimeDeadline);
  }

  /// ตรวจสอบว่าอยู่ในช่วงเวลามาสายหรือไม่
  bool get isInLatePeriod {
    final now = DateTime.now();
    return now.isAfter(onTimeDeadline) && now.isBefore(endTime);
  }

  /// สถานะภาษาไทย
  String get statusInThai {
    switch (status) {
      case 'active':
        return 'กำลังทำงาน';
      case 'ended':
        return 'จบแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return 'ไม่ทราบ';
    }
  }

  /// สถานะภาษาอังกฤษ (พิมพ์ใหญ่)
  String get statusDisplayText {
    switch (status) {
      case 'active':
        return 'ACTIVE';
      case 'ended':
        return 'ENDED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return 'UNKNOWN';
    }
  }

  /// แสดงเวลาเริ่มต้นในรูปแบบที่อ่านง่าย
  String get formattedStartTime {
    return '${startTime.day.toString().padLeft(2, '0')}/'
           '${startTime.month.toString().padLeft(2, '0')}/'
           '${startTime.year} '
           '${startTime.hour.toString().padLeft(2, '0')}:'
           '${startTime.minute.toString().padLeft(2, '0')}';
  }

  /// แสดงเวลาสิ้นสุดในรูปแบบที่อ่านง่าย
  String get formattedEndTime {
    return '${endTime.day.toString().padLeft(2, '0')}/'
           '${endTime.month.toString().padLeft(2, '0')}/'
           '${endTime.year} '
           '${endTime.hour.toString().padLeft(2, '0')}:'
           '${endTime.minute.toString().padLeft(2, '0')}';
  }

  /// แสดงช่วงเวลาของ session
  String get timeRange {
    final startTimeStr = '${startTime.hour.toString().padLeft(2, '0')}:'
                        '${startTime.minute.toString().padLeft(2, '0')}';
    final endTimeStr = '${endTime.hour.toString().padLeft(2, '0')}:'
                      '${endTime.minute.toString().padLeft(2, '0')}';
    return '$startTimeStr - $endTimeStr';
  }

  /// แสดงระยะเวลาทั้งหมดเป็นชั่วโมงและนาที
  String get durationText {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// แสดงเวลาที่เหลือเป็นข้อความ
  String get timeRemainingText {
    if (isEnded) return 'Session ended';
    
    final remaining = timeRemaining;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
    } else if (minutes > 0) {
      return '${minutes}m remaining';
    } else {
      return 'Ending soon';
    }
  }

  /// สีที่เหมาะสมสำหรับแสดงสถานะ
  String get statusColorHex {
    switch (status) {
      case 'active':
        return '#4CAF50'; // เขียว
      case 'ended':
        return '#9E9E9E'; // เทา
      case 'cancelled':
        return '#F44336'; // แดง
      default:
        return '#9E9E9E'; // เทา
    }
  }

  /// สร้าง AttendanceSession สำหรับทดสอบ
  static AttendanceSessionModel createSample({
    String? classId,
    String? teacherEmail,
    DateTime? startTime,
    int? durationHours,
    int? onTimeLimitMinutes,
    String? status,
  }) {
    final start = startTime ?? DateTime.now();
    final duration = durationHours ?? 2;
    
    return AttendanceSessionModel(
      id: 'sample_${DateTime.now().millisecondsSinceEpoch}',
      classId: classId ?? 'CS101',
      teacherEmail: teacherEmail ?? 'teacher@example.com',
      startTime: start,
      endTime: start.add(Duration(hours: duration)),
      onTimeLimitMinutes: onTimeLimitMinutes ?? 30,
      status: status ?? 'active',
      createdAt: start,
      updatedAt: null,
    );
  }

  /// แสดงข้อมูลเป็น string สำหรับ debug
  @override
  String toString() {
    return 'AttendanceSession(id: $id, class: $classId, status: $status, '
           'time: $timeRange, duration: $durationText)';
  }

  /// เปรียบเทียบว่า session เหมือนกันหรือไม่
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is AttendanceSessionModel &&
        other.id == id &&
        other.classId == classId &&
        other.teacherEmail == teacherEmail &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.onTimeLimitMinutes == onTimeLimitMinutes &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        classId.hashCode ^
        teacherEmail.hashCode ^
        startTime.hashCode ^
        endTime.hashCode ^
        onTimeLimitMinutes.hashCode ^
        status.hashCode ^
        createdAt.hashCode ^
        (updatedAt?.hashCode ?? 0);
  
  }
  
}