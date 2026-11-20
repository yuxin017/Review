import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'; // PARKSMART_V20_TWO_ANDROID_FLAVORS
import 'firebase_options.dart';
import 'firebase_emulator_session_stub.dart'
    if (dart.library.js_interop) 'firebase_emulator_session_web.dart';

Future<void> initializeFirebaseEnvironment() async {
  resetFirebaseAuthEmulatorCache();
  // Camera uses its own Android google-services.json (distinct Firebase app ID),
  // while Visitor/Web retain the existing FlutterFire options unchanged.
  // Never hard-code Visitor's Firebase appId into the Camera variant.
  const cameraStation = bool.fromEnvironment('ATTRACTION_CAMERA_STATION');
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && cameraStation) {
    await Firebase.initializeApp();
  } else {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
}
