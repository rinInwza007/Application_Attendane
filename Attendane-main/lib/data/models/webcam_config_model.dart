// lib/data/models/webcam_config_model.dart
class WebcamConfigModel {
  final String ipAddress;
  final int port;
  final String? username;
  final String? password;
  final bool isConnected;
  final DateTime? lastTested;
  final String? errorMessage;

  WebcamConfigModel({
    required this.ipAddress,
    this.port = 8080,
    this.username,
    this.password,
    this.isConnected = false,
    this.lastTested,
    this.errorMessage,
  });

  String get captureUrl => 'http://$ipAddress:$port/photo.jpg';
  String get streamUrl => 'http://$ipAddress:$port/video';
  String get statusUrl => 'http://$ipAddress:$port/status.json';

  factory WebcamConfigModel.fromJson(Map<String, dynamic> json) {
    return WebcamConfigModel(
      ipAddress: json['ip_address'] ?? '',
      port: json['port'] ?? 8080,
      username: json['username'],
      password: json['password'],
      isConnected: json['is_connected'] ?? false,
      lastTested: json['last_tested'] != null
          ? DateTime.parse(json['last_tested'])
          : null,
      errorMessage: json['error_message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip_address': ipAddress,
      'port': port,
      'username': username,
      'password': password,
      'is_connected': isConnected,
      'last_tested': lastTested?.toIso8601String(),
      'error_message': errorMessage,
    };
  }

  WebcamConfigModel copyWith({
    String? ipAddress,
    int? port,
    String? username,
    String? password,
    bool? isConnected,
    DateTime? lastTested,
    String? errorMessage,
  }) {
    return WebcamConfigModel(
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      isConnected: isConnected ?? this.isConnected,
      lastTested: lastTested ?? this.lastTested,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get isValid => ipAddress.isNotEmpty && port > 0 && port < 65536;

  @override
  String toString() {
    return 'WebcamConfig(ip: $ipAddress:$port, connected: $isConnected)';
  }
}

// lib/data/models/periodic_attendance_model.dart
class PeriodicAttendanceModel {
  final String id;
  final String sessionId;
  final DateTime captureTime;
  final String imagePath;
  final List<DetectedFace> detectedFaces;
  final ProcessingStatus status;
  final DateTime createdAt;
  final String? errorMessage;

  PeriodicAttendanceModel({
    required this.id,
    required this.sessionId,
    required this.captureTime,
    required this.imagePath,
    required this.detectedFaces,
    required this.status,
    required this.createdAt,
    this.errorMessage,
  });

  factory PeriodicAttendanceModel.fromJson(Map<String, dynamic> json) {
    return PeriodicAttendanceModel(
      id: json['id'],
      sessionId: json['session_id'],
      captureTime: DateTime.parse(json['capture_time']),
      imagePath: json['image_path'],
      detectedFaces: (json['detected_faces'] as List)
          .map((face) => DetectedFace.fromJson(face))
          .toList(),
      status: ProcessingStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => ProcessingStatus.pending,
      ),
      createdAt: DateTime.parse(json['created_at']),
      errorMessage: json['error_message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'capture_time': captureTime.toIso8601String(),
      'image_path': imagePath,
      'detected_faces': detectedFaces.map((face) => face.toJson()).toList(),
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'error_message': errorMessage,
    };
  }
}

class DetectedFace {
  final String? studentId;
  final String? studentEmail;
  final double confidence;
  final BoundingBox boundingBox;
  final FaceQuality quality;
  final bool verified;

  DetectedFace({
    this.studentId,
    this.studentEmail,
    required this.confidence,
    required this.boundingBox,
    required this.quality,
    required this.verified,
  });

  factory DetectedFace.fromJson(Map<String, dynamic> json) {
    return DetectedFace(
      studentId: json['student_id'],
      studentEmail: json['student_email'],
      confidence: json['confidence']?.toDouble() ?? 0.0,
      boundingBox: BoundingBox.fromJson(json['bounding_box']),
      quality: FaceQuality.fromJson(json['quality']),
      verified: json['verified'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'student_email': studentEmail,
      'confidence': confidence,
      'bounding_box': boundingBox.toJson(),
      'quality': quality.toJson(),
      'verified': verified,
    };
  }
}

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: json['x']?.toDouble() ?? 0.0,
      y: json['y']?.toDouble() ?? 0.0,
      width: json['width']?.toDouble() ?? 0.0,
      height: json['height']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}

class FaceQuality {
  final double brightness;
  final double contrast;
  final double sharpness;
  final double frontality;
  final double eyeOpenness;
  final double overallScore;

  FaceQuality({
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.frontality,
    required this.eyeOpenness,
    required this.overallScore,
  });

  factory FaceQuality.fromJson(Map<String, dynamic> json) {
    return FaceQuality(
      brightness: json['brightness']?.toDouble() ?? 0.0,
      contrast: json['contrast']?.toDouble() ?? 0.0,
      sharpness: json['sharpness']?.toDouble() ?? 0.0,
      frontality: json['frontality']?.toDouble() ?? 0.0,
      eyeOpenness: json['eye_openness']?.toDouble() ?? 0.0,
      overallScore: json['overall_score']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brightness': brightness,
      'contrast': contrast,
      'sharpness': sharpness,
      'frontality': frontality,
      'eye_openness': eyeOpenness,
      'overall_score': overallScore,
    };
  }

  bool get isGoodQuality => overallScore >= 0.7;
  bool get isAcceptableQuality => overallScore >= 0.5;
}

enum ProcessingStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled
}

// lib/data/models/attendance_analytics_model.dart
class AttendanceAnalyticsModel {
  final String sessionId;
  final String classId;
  final DateTime sessionDate;
  final int totalStudents;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final double attendanceRate;
  final double faceVerificationRate;
  final Map<String, int> hourlyAttendance;
  final List<StudentAttendanceStats> studentStats;

  AttendanceAnalyticsModel({
    required this.sessionId,
    required this.classId,
    required this.sessionDate,
    required this.totalStudents,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.attendanceRate,
    required this.faceVerificationRate,
    required this.hourlyAttendance,
    required this.studentStats,
  });

  factory AttendanceAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return AttendanceAnalyticsModel(
      sessionId: json['session_id'],
      classId: json['class_id'],
      sessionDate: DateTime.parse(json['session_date']),
      totalStudents: json['total_students'],
      presentCount: json['present_count'],
      lateCount: json['late_count'],
      absentCount: json['absent_count'],
      attendanceRate: json['attendance_rate']?.toDouble() ?? 0.0,
      faceVerificationRate: json['face_verification_rate']?.toDouble() ?? 0.0,
      hourlyAttendance: Map<String, int>.from(json['hourly_attendance'] ?? {}),
      studentStats: (json['student_stats'] as List? ?? [])
          .map((stats) => StudentAttendanceStats.fromJson(stats))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'class_id': classId,
      'session_date': sessionDate.toIso8601String(),
      'total_students': totalStudents,
      'present_count': presentCount,
      'late_count': lateCount,
      'absent_count': absentCount,
      'attendance_rate': attendanceRate,
      'face_verification_rate': faceVerificationRate,
      'hourly_attendance': hourlyAttendance,
      'student_stats': studentStats.map((stats) => stats.toJson()).toList(),
    };
  }

  int get totalAttended => presentCount + lateCount;
  double get lateRate => totalStudents > 0 ? lateCount / totalStudents : 0.0;
  double get absentRate => totalStudents > 0 ? absentCount / totalStudents : 0.0;
}

class StudentAttendanceStats {
  final String studentId;
  final String studentEmail;
  final String fullName;
  final String status;
  final DateTime? firstDetected;
  final DateTime? lastDetected;
  final int totalDetections;
  final double averageConfidence;
  final bool faceVerified;

  StudentAttendanceStats({
    required this.studentId,
    required this.studentEmail,
    required this.fullName,
    required this.status,
    this.firstDetected,
    this.lastDetected,
    required this.totalDetections,
    required this.averageConfidence,
    required this.faceVerified,
  });

  factory StudentAttendanceStats.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceStats(
      studentId: json['student_id'],
      studentEmail: json['student_email'],
      fullName: json['full_name'],
      status: json['status'],
      firstDetected: json['first_detected'] != null
          ? DateTime.parse(json['first_detected'])
          : null,
      lastDetected: json['last_detected'] != null
          ? DateTime.parse(json['last_detected'])
          : null,
      totalDetections: json['total_detections'] ?? 0,
      averageConfidence: json['average_confidence']?.toDouble() ?? 0.0,
      faceVerified: json['face_verified'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'student_email': studentEmail,
      'full_name': fullName,
      'status': status,
      'first_detected': firstDetected?.toIso8601String(),
      'last_detected': lastDetected?.toIso8601String(),
      'total_detections': totalDetections,
      'average_confidence': averageConfidence,
      'face_verified': faceVerified,
    };
  }

  Duration? get attendanceDuration {
    if (firstDetected == null || lastDetected == null) return null;
    return lastDetected!.difference(firstDetected!);
  }

  bool get wasPresent => status == 'present' || status == 'late';
}