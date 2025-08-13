class UserModel {
  final String email;
  final String fullName;
  final String schoolId;
  final String userType;
  final bool hasFaceData;

  UserModel({
    required this.email,
    required this.fullName,
    required this.schoolId,
    required this.userType,
    this.hasFaceData = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
      schoolId: json['school_id'] ?? '',
      userType: json['user_type'] ?? '',
      hasFaceData: json['has_face_data'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'full_name': fullName,
      'school_id': schoolId,
      'user_type': userType,
      'has_face_data': hasFaceData,
    };
  }
}
