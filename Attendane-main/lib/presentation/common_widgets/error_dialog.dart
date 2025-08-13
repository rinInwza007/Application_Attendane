import 'package:flutter/material.dart';

class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final String buttonText;
  final VoidCallback? onPressed;
  final bool showRetry;
  final VoidCallback? onRetry;
  final IconData? icon;
  final Color? iconColor;

  const ErrorDialog({
    super.key,
    this.title = 'เกิดข้อผิดพลาด',
    required this.message,
    this.buttonText = 'ตกลง',
    this.onPressed,
    this.showRetry = false,
    this.onRetry,
    this.icon,
    this.iconColor,
  });

  static Future<bool?> show(
    BuildContext context, {
    String title = 'เกิดข้อผิดพลาด',
    required String message,
    String buttonText = 'ตกลง',
    VoidCallback? onPressed,
    bool showRetry = false,
    VoidCallback? onRetry,
    IconData? icon,
    Color? iconColor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ErrorDialog(
        title: title,
        message: message,
        buttonText: buttonText,
        onPressed: onPressed,
        showRetry: showRetry,
        onRetry: onRetry,
        icon: icon,
        iconColor: iconColor,
      ),
    );
  }

  static Future<bool?> showFaceRecognitionError(
    BuildContext context, {
    required String message,
    bool canRetry = true,
  }) {
    String friendlyMessage = message;
    IconData errorIcon = Icons.error_outline;
    Color errorColor = Colors.red;

    // Categorize error types
    if (message.contains('ไม่พบใบหน้า')) {
      friendlyMessage = 'ไม่พบใบหน้าในรูปภาพ\n\nกรุณา:\n• เลือกรูปที่เห็นใบหน้าชัดเจน\n• ไม่มีวัตถุบดบังใบหน้า\n• มีแสงสว่างเพียงพอ';
      errorIcon = Icons.face_retouching_off;
      errorColor = Colors.orange;
    } else if (message.contains('พบใบหน้าหลาย')) {
      friendlyMessage = 'พบใบหน้าหลายใบในรูปภาพ\n\nกรุณา:\n• เลือกรูปที่มีเพียงใบหน้าของคุณเท่านั้น\n• ไม่มีคนอื่นในรูป\n• ครอบรูปให้เหลือเฉพาะใบหน้าของคุณ';
      errorIcon = Icons.groups;
      errorColor = Colors.orange;
    } else if (message.contains('หันข้าง') || message.contains('เอียง')) {
      friendlyMessage = 'ท่าทางใบหน้าไม่เหมาะสม\n\nกรุณา:\n• หันหน้าตรงไปที่กล้อง\n• ไม่เอียงหัวมากเกินไป\n• ถ่ายรูปในท่าธรรมชาติ';
      errorIcon = Icons.face_6;
      errorColor = Colors.blue;
    } else if (message.contains('ลืมตา')) {
      friendlyMessage = 'ตรวจพบว่าตาหลับ\n\nกรุณา:\n• ลืมตาและมองตรงไปที่กล้อง\n• ไม่ใส่แว่นตาเข้ม\n• ถ่ายรูปในที่ที่มีแสงสว่าง';
      errorIcon = Icons.remove_red_eye;
      errorColor = Colors.indigo;
    } else if (message.contains('ไฟล์')) {
      friendlyMessage = 'ปัญหาเกี่ยวกับไฟล์รูปภาพ\n\nกรุณา:\n• ตรวจสอบว่ารูปภาพไม่เสียหาย\n• เลือกไฟล์ .jpg หรือ .png\n• ขนาดไฟล์ไม่เกิน 10MB';
      errorIcon = Icons.broken_image;
      errorColor = Colors.grey;
    } else if (message.contains('connection') || message.contains('network')) {
      friendlyMessage = 'ปัญหาการเชื่อมต่อ\n\nกรุณา:\n• ตรวจสอบการเชื่อมต่ออินเทอร์เน็ต\n• ลองใช้ Wi-Fi หรือ 4G/5G\n• รอสักครู่แล้วลองใหม่';
      errorIcon = Icons.wifi_off;
      errorColor = Colors.red;
    }

    return show(
      context,
      title: 'ปัญหาการประมวลผลใบหน้า',
      message: friendlyMessage,
      showRetry: canRetry,
      onRetry: canRetry ? () => Navigator.of(context).pop(true) : null,
      icon: errorIcon,
      iconColor: errorColor,
    );
  }

  static Future<bool?> showNetworkError(
    BuildContext context, {
    String? customMessage,
  }) {
    return show(
      context,
      title: 'ปัญหาการเชื่อมต่อ',
      message: customMessage ?? 
        'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้\n\nกรุณา:\n• ตรวจสอบการเชื่อมต่ออินเทอร์เน็ต\n• ลองใช้เครือข่ายอื่น\n• รอสักครู่แล้วลองใหม่',
      showRetry: true,
      onRetry: () => Navigator.of(context).pop(true),
      icon: Icons.wifi_off,
      iconColor: Colors.red,
    );
  }

  static Future<bool?> showValidationError(
    BuildContext context, {
    required String field,
    required String issue,
  }) {
    return show(
      context,
      title: 'ข้อมูลไม่ถูกต้อง',
      message: 'ปัญหา: $field\n\n$issue',
      icon: Icons.info_outline,
      iconColor: Colors.blue,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            icon ?? Icons.error_outline,
            color: iconColor ?? Colors.red,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates, 
                         color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'กดปุ่ม "ลองใหม่" เพื่อดำเนินการอีกครั้ง',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (showRetry && onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            child: const Text(
              'ลองใหม่',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            onPressed?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple.shade400,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(buttonText),
        ),
      ],
      actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
    );
  }
}

// Custom SnackBar helper for consistent error messaging
class ErrorSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 5),
    VoidCallback? onRetry,
    bool showRetry = false,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: showRetry && onRetry != null
            ? SnackBarAction(
                label: 'ลองใหม่',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  static void showSuccess(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showWarning(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: onAction != null && actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  static void showInfo(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}