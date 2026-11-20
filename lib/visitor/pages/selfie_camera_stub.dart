import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<Uint8List?> captureWebSelfie(
  BuildContext context, {String facingMode = 'user', String title = 'Take Selfie'}
) =>
    throw UnsupportedError('Use the device camera.');
