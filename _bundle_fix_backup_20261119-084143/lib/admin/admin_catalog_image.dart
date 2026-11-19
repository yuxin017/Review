import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Pick a small catalogue cover photo; never upload face photos through this helper.
/// Upload is performed with the separately authenticated ThemeParkAdmin app.
Future<PlatformFile?> pickParkCatalogImage() async {
  // file_picker v12 uses static methods and asynchronous byte reads.
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );
  if (file == null) return null;
  if ((await file.readAsBytes()).length > 2 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 2 MB.');
  }
  final imageBytes = await file.readAsBytes();
  if (imageBytes.isEmpty) {
    throw const FormatException('Could not read the selected image.');
  }
  return file;
}

Future<String> uploadParkCatalogImage(PlatformFile file, String group) async {
  if (!['tickets', 'bundles'].contains(group)) {
    throw ArgumentError.value(group, 'group', 'Unsupported catalogue folder');
  }
  final suffix = (file.extension ?? '').toLowerCase();
  final extension = suffix == 'jpeg' ? 'jpg' : suffix;
  final contentType = switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'jpg' => 'image/jpeg',
    _ => throw const FormatException('Only JPG, PNG or WebP images are supported.'),
  };
  final app = Firebase.app('ThemeParkAdmin');
  final storage = FirebaseStorage.instanceFor(app: app);
  final filename = '${DateTime.now().microsecondsSinceEpoch}.$extension';
  final ref = storage.ref('catalog-images/$group/$filename');
  await ref.putData(await file.readAsBytes(), SettableMetadata(contentType: contentType));
  return ref.getDownloadURL();
}

class ParkCatalogImagePicker extends StatelessWidget {
  const ParkCatalogImagePicker({super.key,
    required this.label,
    required this.onPick,
    this.bytes,
    this.existingUrl,
  });
  final String label;
  final Uint8List? bytes;
  final String? existingUrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasPreview = bytes != null || (existingUrl?.isNotEmpty ?? false);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F1F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6D8D6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (hasPreview)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(height: 120, child: bytes != null
                ? Image.memory(bytes!, fit: BoxFit.cover)
                : Image.network(existingUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined))),
          ))
        else
          Container(height: 100,
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.add_photo_alternate_outlined,
              size: 32, color: Color(0xFFBF7E82))),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.upload_file_outlined, size: 17),
          label: Text(hasPreview ? 'Replace photo' : 'Choose photo'),
        ),
      ]),
    );
  }
}
