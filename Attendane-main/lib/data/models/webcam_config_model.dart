// lib/data/models/webcam_config_model.dart
class WebcamConfigModel {
  final String ipAddress;
  final int port;
  final String username;
  final String password;
  final String streamPath;
  final bool isConnected;

  WebcamConfigModel({
    required this.ipAddress,
    this.port = 8080,
    this.username = '',
    this.password = '',
    this.streamPath = '/video',
    this.isConnected = false,
  });

  /// URL สำหรับดู video stream
  String get streamUrl => 'http://192.168.1.9:8000/video';
  
  /// URL สำหรับถ่ายภาพ
  String get captureUrl => 'http://192.168.1.9:8000/photo.jpg';
  
  /// URL สำหรับดู video ใน browser
  String get browserUrl => 'http://192.168.1.9:8080';
  
  factory WebcamConfigModel.fromJson(Map<String, dynamic> json) {
    return WebcamConfigModel(
      ipAddress: json['ip_address'] ?? '',
      port: json['port'] ?? 8080,
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      streamPath: json['stream_path'] ?? '/video',
      isConnected: json['is_connected'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip_address': ipAddress,
      'port': port,
      'username': username,
      'password': password,
      'stream_path': streamPath,
      'is_connected': isConnected,
    };
  }

  /// สร้าง copy ของ WebcamConfig พร้อมแก้ไขค่าใหม่
  WebcamConfigModel copyWith({
    String? ipAddress,
    int? port,
    String? username,
    String? password,
    String? streamPath,
    bool? isConnected,
  }) {
    return WebcamConfigModel(
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      streamPath: streamPath ?? this.streamPath,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  /// ตรวจสอบว่า config ถูกต้องหรือไม่
  bool get isValid {
    return ipAddress.isNotEmpty && 
           port > 0 && 
           port <= 65535 &&
           _isValidIPAddress(ipAddress);
  }

  /// ตรวจสอบว่า IP address ถูกต้องหรือไม่
  bool _isValidIPAddress(String ip) {
    // ตรวจสอบ format IP address แบบง่ายๆ
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) {
        return false;
      }
    }
    return true;
  }

  /// แสดงข้อมูลเป็น string สำหรับ debug
  @override
  String toString() {
    return 'WebcamConfig(ip: $ipAddress, port: $port, connected: $isConnected)';
  }

  /// เปรียบเทียบว่า config เหมือนกันหรือไม่
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is WebcamConfigModel &&
        other.ipAddress == ipAddress &&
        other.port == port &&
        other.username == username &&
        other.password == password &&
        other.streamPath == streamPath &&
        other.isConnected == isConnected;
  }

  @override
  int get hashCode {
    return ipAddress.hashCode ^
        port.hashCode ^
        username.hashCode ^
        password.hashCode ^
        streamPath.hashCode ^
        isConnected.hashCode;
  }

  /// สร้าง WebcamConfig แบบ default สำหรับทดสอบ
  static WebcamConfigModel get defaultConfig {
    return WebcamConfigModel(
      ipAddress: '192.168.1.100',
      port: 8080,
      username: '',
      password: '',
      streamPath: '/video',
      isConnected: false,
    );
  }

  /// สร้าง WebcamConfig จาก URL
  static WebcamConfigModel? fromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return WebcamConfigModel(
        ipAddress: uri.host,
        port: uri.port,
        username: '',
        password: '',
        streamPath: uri.path.isEmpty ? '/video' : uri.path,
        isConnected: false,
      );
    } catch (e) {
      return null;
    }
  }
}