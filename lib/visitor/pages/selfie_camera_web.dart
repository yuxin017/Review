// The browser camera is only imported by the web build.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<Uint8List?> captureWebSelfie(BuildContext context) async {
  final devices = html.window.navigator.mediaDevices;
  if (devices == null) {
    throw StateError('Open the app on localhost or HTTPS to use the camera.');
  }
  late final html.MediaStream stream;
  try {
    stream = await devices.getUserMedia({
      'audio': false,
      'video': {'facingMode': 'user', 'width': {'ideal': 960}},
    });
  } catch (_) {
    throw StateError('Camera unavailable. Allow camera access or upload a selfie.');
  }
  final video = html.VideoElement()
    ..muted = true
    ..autoplay = true
    ..setAttribute('playsinline', '')
    ..srcObject = stream;
  video.style
    ..width = '100%'
    ..height = '100%'
    ..objectFit = 'contain';
  try {
    if (!context.mounted) return null;
    return await showDialog<Uint8List>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Take Selfie'),
        content: SizedBox(
          width: 380,
          height: 285,
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            onElementCreated: (element) => (element as html.DivElement).append(video),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (video.videoWidth == 0 || video.videoHeight == 0) return;
            final canvas = html.CanvasElement(width: video.videoWidth, height: video.videoHeight);
            canvas.context2D.drawImage(video, 0, 0);
            Navigator.pop(dialog, base64Decode(canvas.toDataUrl('image/jpeg', .85).split(',').last));
          }, child: const Text('Capture')),
        ],
      ),
    );
  } finally {
    for (final track in stream.getTracks()) {
      track.stop();
    }
    video.srcObject = null;
  }
}
