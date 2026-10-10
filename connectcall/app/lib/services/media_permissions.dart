import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class MediaPermissionResult {
  const MediaPermissionResult({required this.camera, required this.microphone, this.permanentlyDenied = false});

  final bool camera;
  final bool microphone;

  /// The user chose "Don't ask again"; only system settings can fix it.
  final bool permanentlyDenied;
}

/// On Android, asks for camera + microphone up front so the meeting screen
/// can explain a refusal. In browsers the permission prompt is shown by the
/// browser itself when the camera/mic is first opened, so this is a no-op.
class MediaPermissions {
  static Future<MediaPermissionResult> request() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const MediaPermissionResult(camera: true, microphone: true);
    }
    final statuses = await [Permission.camera, Permission.microphone].request();
    final cam = statuses[Permission.camera] ?? PermissionStatus.denied;
    final mic = statuses[Permission.microphone] ?? PermissionStatus.denied;
    return MediaPermissionResult(
      camera: cam.isGranted,
      microphone: mic.isGranted,
      permanentlyDenied: cam.isPermanentlyDenied || mic.isPermanentlyDenied,
    );
  }

  static Future<void> openSettings() => openAppSettings();
}
