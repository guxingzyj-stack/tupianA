import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

final photoPickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

final photoPickerControllerProvider = Provider<PhotoPickerController>((ref) {
  return PhotoPickerController(ref.watch(photoPickerProvider));
});

class PickedPhoto {
  const PickedPhoto({required this.path});

  final String path;
}

class PhotoPermissionException implements Exception {
  const PhotoPermissionException(this.message);

  final String message;
}

class PhotoPickerController {
  const PhotoPickerController(this._picker);

  final ImagePicker _picker;

  Future<PickedPhoto?> pickFromGallery() async {
    await _ensureGalleryPermission();
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (file == null) {
      return null;
    }
    return PickedPhoto(path: await _copyToAppTemp(file));
  }

  Future<PickedPhoto?> takePhoto() async {
    await _ensurePermission(Permission.camera, '需要相机权限才能拍照');
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) {
      return null;
    }
    return PickedPhoto(path: await _copyToAppTemp(file));
  }

  Future<void> _ensureGalleryPermission() async {
    if (Platform.isIOS) {
      await _ensurePermission(Permission.photos, '需要相册权限才能选照片');
      return;
    }

    final photos = await Permission.photos.request();
    if (photos.isGranted || photos.isLimited) {
      return;
    }

    final storage = await Permission.storage.request();
    if (!storage.isGranted) {
      throw const PhotoPermissionException('需要相册权限才能选照片');
    }
  }

  Future<void> _ensurePermission(Permission permission, String message) async {
    final status = await permission.request();
    if (!status.isGranted && !status.isLimited) {
      throw PhotoPermissionException(message);
    }
  }

  Future<String> _copyToAppTemp(XFile pickedFile) async {
    final tempDir = await getTemporaryDirectory();
    final safeName = pickedFile.name.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]+'),
      '_',
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'picked_${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    await File(pickedFile.path).copy(target.path);
    return target.path;
  }
}
