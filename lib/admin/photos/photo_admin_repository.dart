import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../photos/photo_repository.dart';
import '../../services/application_api.dart';

abstract class PhotoAdminRepository {
  Stream<List<ParkPhoto>> records(String collection);
  Stream<List<Map<String, dynamic>>> places();
  Future<Map<String, dynamic>> request(
    String action,
    Map<String, dynamic> data,
  );
  String newRequestId();
}

class FirebasePhotoAdminRepository implements PhotoAdminRepository {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final String? staffPhotographerUid;
  FirebasePhotoAdminRepository({required this.db, required this.auth, this.staffPhotographerUid});
  @override
  Stream<List<ParkPhoto>> records(String collection) {
    if (![
      'parkPhotos',
      'photoOrders',
      'photoMatches',
      'photoMatchReviews',
    ].contains(collection)) {
      throw ArgumentError('Unknown photo section.');
    }
    if (staffPhotographerUid != null && collection != 'parkPhotos') {
      return Stream.value(const <ParkPhoto>[]);
    }
    final query = staffPhotographerUid == null
        ? db.collection(collection)
        : db.collection('parkPhotos').where(
            'photographerUid', isEqualTo: staffPhotographerUid);
    return query.snapshots()
        .map((s) => s.docs.map((d) => ParkPhoto(d.id, d.data())).toList());
  }

  @override
  Stream<List<Map<String, dynamic>>> places() => db
      .collection('attractions')
      .snapshots()
      .map(
        (s) => s.docs
            .where((d) => d.data()['deletedAt'] == null)
            .map((d) => {'id': d.id, 'name': d.data()['name']})
            .toList(),
      );
  @override
  Future<Map<String, dynamic>> request(
    String action,
    Map<String, dynamic> data,
  ) {
    final route = staffPhotographerUid != null && action == 'upload'
        ? 'staffUpload' : action;
    return ApplicationApi(auth: auth).post('/v1/photos/$route', data);
  }
  @override
  String newRequestId() => db.collection('parkPhotos').doc().id;
}
