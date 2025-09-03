// lib/data/services/auth_service.dart
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myproject2/data/models/user_model.dart';
import 'package:myproject2/data/models/class_model.dart';
import 'dart:math' as Math;

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== Authentication ====================
  
  Future<void> signUpWithEmailPassword(String email, String password) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      
      if (response.user == null) {
        throw Exception('Failed to create account');
      }
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user == null) {
        throw Exception('Login failed');
      }
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Logout failed: $e');
    }
  }

  String? getCurrentUserEmail() {
    return _supabase.auth.currentUser?.email;
  }

  // ==================== User Profile ====================
  
  Future<Map<String, dynamic>> checkUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return {'exists': false, 'userType': null};
      }

      final response = await _supabase
          .from('users')
          .select('user_type')
          .eq('email', user.email!)
          .maybeSingle();

      if (response == null) {
        return {'exists': false, 'userType': null};
      }

      return {'exists': true, 'userType': response['user_type']};
    } catch (e) {
      throw Exception('Error checking user profile: $e');
    }
  }

  Future<void> saveUserProfile({
    required String fullName,
    required String schoolId,
    required String userType,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      await _supabase.from('users').upsert({
        'email': user.email,
        'full_name': fullName,
        'school_id': schoolId,
        'user_type': userType,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to save user profile: $e');
    }
  }
  Future<void> saveFaceEmbeddingFromMultipleImages(
  List<String> imagePaths, 
  String userEmail,
) async {
  try {
    print('🔄 Processing multi-step face embedding for: $userEmail');
    
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('No authenticated user');

    final userProfile = await getUserProfile();
    if (userProfile == null) throw Exception('User profile not found');

    final schoolId = userProfile['school_id'];
    if (schoolId == null) throw Exception('School ID not found');

    // ใช้ UnifiedFaceService เพื่อประมวลผลภาพหลายมุม
    final faceService = UnifiedFaceService();
    await faceService.initialize();

    // สร้าง embeddings จากภาพทั้งหมด
    List<List<double>> allEmbeddings = [];
    List<double> qualityScores = [];
    
    for (int i = 0; i < imagePaths.length; i++) {
      final imagePath = imagePaths[i];
      print('📸 Processing image ${i + 1}/${imagePaths.length}: $imagePath');
      
      try {
        final imageFile = File(imagePath);
        if (!await imageFile.exists()) {
          print('⚠️ Image file not found: $imagePath');
          continue;
        }

        // Extract face embedding และ quality
        final result = await faceService.extractFaceEmbedding(imagePath);
        if (result['success'] == true && result['embedding'] != null) {
          final embedding = List<double>.from(result['embedding']);
          final quality = result['quality'] ?? 0.8;
          
          allEmbeddings.add(embedding);
          qualityScores.add(quality);
          
          print('✅ Processed image ${i + 1}: quality = ${(quality * 100).toInt()}%');
        } else {
          print('⚠️ Failed to process image ${i + 1}: ${result['error']}');
        }
      } catch (e) {
        print('❌ Error processing image ${i + 1}: $e');
      }
    }

    if (allEmbeddings.isEmpty) {
      throw Exception('No valid face embeddings could be extracted from the images');
    }

    // คำนวณ average embedding จากภาพทั้งหมด (weighted by quality)
    final avgEmbedding = _calculateWeightedAverageEmbedding(allEmbeddings, qualityScores);
    final avgQuality = qualityScores.reduce((a, b) => a + b) / qualityScores.length;

    // บันทึกลง Supabase
    final embeddingJson = jsonEncode(avgEmbedding);
    
    await _supabase.from('student_face_embeddings').upsert({
      'student_id': schoolId,
      'face_embedding_json': embeddingJson,
      'face_quality': avgQuality,
      'embedding_source': 'multi_step_capture',
      'total_images_used': allEmbeddings.length,
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Clean up image files
    await _cleanupImageFiles(imagePaths);

    print('✅ Multi-step face embedding saved successfully');
    print('📊 Used ${allEmbeddings.length} images with avg quality: ${(avgQuality * 100).toInt()}%');
    
  } catch (e) {
    print('❌ Error saving multi-step face embedding: $e');
    throw Exception('Failed to save multi-step face embedding: $e');
  }
}

/// อัพเดท Face Embedding จากภาพหลายมุม
Future<void> updateFaceEmbeddingFromMultipleImages(
  List<String> imagePaths, 
  String userEmail,
) async {
  try {
    print('🔄 Updating multi-step face embedding for: $userEmail');
    
    // Deactivate old embedding first
    await deactivateFaceEmbedding();
    
    // Save new embedding
    await saveFaceEmbeddingFromMultipleImages(imagePaths, userEmail);
    
    print('✅ Multi-step face embedding updated successfully');
  } catch (e) {
    throw Exception('Failed to update multi-step face embedding: $e');
  }
}

/// ตรวจสอบใบหน้าจากภาพหลายมุมเพื่อการเช็คชื่อ
Future<Map<String, dynamic>> verifyFaceFromMultipleImages(
  String studentId, 
  List<String> imagePaths,
) async {
  try {
    print('🔍 Verifying face from ${imagePaths.length} images for: $studentId');
    
    // ดึง stored embedding
    final response = await _supabase
        .from('student_face_embeddings')
        .select('face_embedding_json, face_quality')
        .eq('student_id', studentId)
        .eq('is_active', true)
        .maybeSingle();

    if (response == null) {
      return {
        'verified': false,
        'error': 'No stored face embedding found',
        'similarity_score': 0.0,
      };
    }

    final storedEmbeddingJson = response['face_embedding_json'];
    final storedEmbedding = List<double>.from(jsonDecode(storedEmbeddingJson));
    final storedQuality = response['face_quality'] ?? 0.8;

    // ประมวลผลภาพที่ส่งมา
    final faceService = UnifiedFaceService();
    await faceService.initialize();

    List<double> allSimilarities = [];
    List<double> capturedQualities = [];
    
    for (int i = 0; i < imagePaths.length; i++) {
      final imagePath = imagePaths[i];
      
      try {
        final result = await faceService.extractFaceEmbedding(imagePath);
        if (result['success'] == true && result['embedding'] != null) {
          final capturedEmbedding = List<double>.from(result['embedding']);
          final quality = result['quality'] ?? 0.8;
          
          final similarity = _calculateCosineSimilarity(capturedEmbedding, storedEmbedding);
          allSimilarities.add(similarity);
          capturedQualities.add(quality);
          
          print('📸 Image ${i + 1}: similarity = ${(similarity * 100).toInt()}%, quality = ${(quality * 100).toInt()}%');
        }
      } catch (e) {
        print('⚠️ Error processing verification image ${i + 1}: $e');
      }
    }

    if (allSimilarities.isEmpty) {
      return {
        'verified': false,
        'error': 'Could not extract face embeddings from any image',
        'similarity_score': 0.0,
      };
    }

    // คำนวณ weighted average similarity (โดย quality)
    double weightedSimilarity = 0.0;
    double totalWeight = 0.0;
    
    for (int i = 0; i < allSimilarities.length; i++) {
      final weight = capturedQualities[i];
      weightedSimilarity += allSimilarities[i] * weight;
      totalWeight += weight;
    }
    
    final avgSimilarity = weightedSimilarity / totalWeight;
    final maxSimilarity = allSimilarities.reduce((a, b) => a > b ? a : b);
    final avgQuality = capturedQualities.reduce((a, b) => a + b) / capturedQualities.length;
    
    // Dynamic threshold based on quality
    double threshold = 0.7; // Base threshold
    if (storedQuality > 0.9 && avgQuality > 0.9) {
      threshold = 0.75; // Higher threshold for high quality
    } else if (storedQuality < 0.7 || avgQuality < 0.7) {
      threshold = 0.65; // Lower threshold for lower quality
    }
    
    final isVerified = avgSimilarity > threshold;
    
    // Clean up image files
    await _cleanupImageFiles(imagePaths);
    
    print('🔍 Verification result: ${isVerified ? 'VERIFIED' : 'REJECTED'}');
    print('📊 Avg similarity: ${(avgSimilarity * 100).toInt()}%, Threshold: ${(threshold * 100).toInt()}%');
    
    return {
      'verified': isVerified,
      'similarity_score': avgSimilarity,
      'max_similarity': maxSimilarity,
      'threshold_used': threshold,
      'images_processed': allSimilarities.length,
      'average_quality': avgQuality,
      'stored_quality': storedQuality,
    };
    
  } catch (e) {
    print('❌ Error in multi-image face verification: $e');
    return {
      'verified': false,
      'error': e.toString(),
      'similarity_score': 0.0,
    };
  }
}

/// ตรวจสอบคุณภาพของ Face Embedding ที่เก็บไว้
Future<Map<String, dynamic>> getFaceEmbeddingInfo() async {
  try {
    final user = _supabase.auth.currentUser;
    if (user == null) return {'exists': false};

    final userProfile = await getUserProfile();
    if (userProfile == null) return {'exists': false};

    final schoolId = userProfile['school_id'];
    if (schoolId == null) return {'exists': false};

    final response = await _supabase
        .from('student_face_embeddings')
        .select('face_quality, embedding_source, total_images_used, created_at, updated_at')
        .eq('student_id', schoolId)
        .eq('is_active', true)
        .maybeSingle();

    if (response == null) return {'exists': false};

    return {
      'exists': true,
      'quality': response['face_quality'],
      'source': response['embedding_source'] ?? 'single_capture',
      'images_used': response['total_images_used'] ?? 1,
      'created_at': response['created_at'],
      'updated_at': response['updated_at'],
    };
  } catch (e) {
    print('❌ Error getting face embedding info: $e');
    return {'exists': false, 'error': e.toString()};
  }
}

// ==================== Helper Methods for Multi-Step ====================

/// คำนวณ weighted average embedding
List<double> _calculateWeightedAverageEmbedding(
  List<List<double>> embeddings, 
  List<double> weights,
) {
  if (embeddings.isEmpty) return [];
  
  final embeddingSize = embeddings.first.length;
  List<double> avgEmbedding = List.filled(embeddingSize, 0.0);
  double totalWeight = weights.reduce((a, b) => a + b);
  
  for (int i = 0; i < embeddings.length; i++) {
    final embedding = embeddings[i];
    final weight = weights[i] / totalWeight;
    
    for (int j = 0; j < embeddingSize; j++) {
      avgEmbedding[j] += embedding[j] * weight;
    }
  }
  
  return avgEmbedding;
}

/// ล้างไฟล์รูปภาพหลังใช้งาน
Future<void> _cleanupImageFiles(List<String> imagePaths) async {
  for (final imagePath in imagePaths) {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Cleaned up: $imagePath');
      }
    } catch (e) {
      print('⚠️ Could not delete $imagePath: $e');
    }
  }
}

/// ปรับปรุง quality calculation ให้ดีขึ้น
double _calculateAdvancedEmbeddingQuality(List<double> embedding) {
  if (embedding.isEmpty) return 0.0;
  
  // คำนวณ variance (ความแปรปรวน)
  double sum = embedding.reduce((a, b) => a + b);
  double mean = sum / embedding.length;
  
  double variance = 0;
  for (double value in embedding) {
    variance += (value - mean) * (value - mean);
  }
  variance /= embedding.length;
  
  // คำนวณ L2 norm
  double norm = 0;
  for (double value in embedding) {
    norm += value * value;
  }
  norm = Math.sqrt(norm);
  
  // รวมปัจจัยต่างๆ เข้าด้วยกัน
  double qualityScore = 0.0;
  
  // Variance component (ความหลากหลายของ features)
  qualityScore += (variance * 2).clamp(0.0, 0.4);
  
  // Norm component (ความแรงของ signal)
  qualityScore += (norm / 50).clamp(0.0, 0.3);
  
  // Stability component (ไม่มีค่าผิดปกติ)
  double stability = 1.0;
  for (double value in embedding) {
    if (value.abs() > 10) stability -= 0.1; // ลดคะแนนถ้ามีค่าผิดปกติ
  }
  qualityScore += (stability * 0.3).clamp(0.0, 0.3);
  
  return qualityScore.clamp(0.0, 1.0);
}

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('users')
          .select()
          .eq('email', user.email!)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Error getting user profile: $e');
    }
  }

  // ==================== Class Management ====================
  
  Future<List<Map<String, dynamic>>> getTeacherClasses() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No authenticated user');

      final response = await _supabase
          .from('classes')
          .select()
          .eq('teacher_email', user.email!)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error getting teacher classes: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getStudentClasses() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No authenticated user');

      final response = await _supabase
          .from('class_students')
          .select('''
            class_id,
            joined_at,
            classes!inner(
              class_id,
              class_name,
              teacher_email,
              schedule,
              room
            )
          ''')
          .eq('student_email', user.email!)
          .order('joined_at', ascending: false);

      return response.map<Map<String, dynamic>>((item) {
        final classInfo = item['classes'];
        return {
          'id': classInfo['class_id'],
          'name': classInfo['class_name'],
          'teacher': classInfo['teacher_email'],
          'schedule': classInfo['schedule'],
          'room': classInfo['room'],
          'joinedDate': DateTime.parse(item['joined_at']),
          'isFavorite': false,
        };
      }).toList();
    } catch (e) {
      throw Exception('Error getting student classes: $e');
    }
  }

  Future<bool> checkClassExists(String classId) async {
    try {
      final response = await _supabase
          .from('classes')
          .select('class_id')
          .eq('class_id', classId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> createClass({
    required String classId,
    required String className,
    required String schedule,
    required String room,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No authenticated user');

      // Generate random invite code
      final inviteCode = _generateInviteCode();

      await _supabase.from('classes').insert({
        'class_id': classId,
        'class_name': className,
        'teacher_email': user.email,
        'schedule': schedule,
        'room': room,
        'invite_code': inviteCode,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to create class: $e');
    }
  }

  Future<void> updateClass({
    required String classId,
    required String className,
    required String schedule,
    required String room,
  }) async {
    try {
      await _supabase
          .from('classes')
          .update({
            'class_name': className,
            'schedule': schedule,
            'room': room,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('class_id', classId);
    } catch (e) {
      throw Exception('Failed to update class: $e');
    }
  }

  Future<void> deleteClass(String classId) async {
    try {
      await _supabase
          .from('classes')
          .delete()
          .eq('class_id', classId);
    } catch (e) {
      throw Exception('Failed to delete class: $e');
    }
  }

  Future<Map<String, dynamic>> getClassDetail(String classId) async {
    try {
      final response = await _supabase
          .from('classes')
          .select()
          .eq('class_id', classId)
          .single();

      return response;
    } catch (e) {
      throw Exception('Error getting class detail: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getClassStudents(String classId) async {
    try {
      final response = await _supabase
          .from('class_students')
          .select('''
            student_email,
            joined_at,
            users!inner(
              email,
              full_name,
              school_id
            )
          ''')
          .eq('class_id', classId)
          .order('joined_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error getting class students: $e');
    }
  }

  Future<Map<String, dynamic>?> getClassByInviteCode(String inviteCode) async {
    try {
      final response = await _supabase
          .from('classes')
          .select()
          .eq('invite_code', inviteCode)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }

  Future<void> joinClass({
    required String classId,
    required String studentEmail,
  }) async {
    try {
      await _supabase.from('class_students').insert({
        'class_id': classId,
        'student_email': studentEmail,
        'joined_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to join class: $e');
    }
  }

  Future<void> leaveClass({
    required String classId,
    required String studentEmail,
  }) async {
    try {
      await _supabase
          .from('class_students')
          .delete()
          .eq('class_id', classId)
          .eq('student_email', studentEmail);
    } catch (e) {
      throw Exception('Failed to leave class: $e');
    }
  }

  // ==================== Face Recognition ====================
  
  Future<bool> hasFaceEmbedding() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final userProfile = await getUserProfile();
      if (userProfile == null) return false;

      final schoolId = userProfile['school_id'];
      if (schoolId == null) return false;

      final response = await _supabase
          .from('student_face_embeddings')
          .select('id')
          .eq('student_id', schoolId)
          .eq('is_active', true)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> saveFaceEmbedding(List<double> embedding) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No authenticated user');

      final userProfile = await getUserProfile();
      if (userProfile == null) throw Exception('User profile not found');

      final schoolId = userProfile['school_id'];
      if (schoolId == null) throw Exception('School ID not found');

      final embeddingJson = jsonEncode(embedding);
      final quality = _calculateEmbeddingQuality(embedding);

      await _supabase.from('student_face_embeddings').upsert({
        'student_id': schoolId,
        'face_embedding_json': embeddingJson,
        'face_quality': quality,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to save face embedding: $e');
    }
  }

  Future<void> deactivateFaceEmbedding() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No authenticated user');

      final userProfile = await getUserProfile();
      if (userProfile == null) throw Exception('User profile not found');

      final schoolId = userProfile['school_id'];
      if (schoolId == null) throw Exception('School ID not found');

      await _supabase
          .from('student_face_embeddings')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('student_id', schoolId);
    } catch (e) {
      throw Exception('Failed to deactivate face embedding: $e');
    }
  }

  Future<bool> verifyFace(String studentId, List<double> capturedEmbedding) async {
    try {
      final response = await _supabase
          .from('student_face_embeddings')
          .select('face_embedding_json')
          .eq('student_id', studentId)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return false;

      final storedEmbeddingJson = response['face_embedding_json'];
      final storedEmbedding = List<double>.from(jsonDecode(storedEmbeddingJson));

      final similarity = _calculateCosineSimilarity(capturedEmbedding, storedEmbedding);
      return similarity > 0.7; // Threshold for face verification
    } catch (e) {
      return false;
    }
  }

  // ==================== Helper Methods ====================
  
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String code = '';
    
    for (int i = 0; i < 6; i++) {
      code += chars[(random + i) % chars.length];
    }
    
    return code;
  }

  double _calculateEmbeddingQuality(List<double> embedding) {
    // Simple quality calculation based on variance
    double sum = embedding.reduce((a, b) => a + b);
    double mean = sum / embedding.length;
    
    double variance = 0;
    for (double value in embedding) {
      variance += (value - mean) * (value - mean);
    }
    variance /= embedding.length;
    
    return (variance * 10).clamp(0.0, 1.0);
  }

  double _calculateCosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0.0 || normB == 0.0) return 0.0;
    
    return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
  }
}


