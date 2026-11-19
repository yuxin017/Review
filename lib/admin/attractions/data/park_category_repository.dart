import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../attractions/models/attraction.dart';

/// Facility types are independent from categories. Categories are editable
/// master data, while a place always keeps the same stable type.
class ParkCategory {
  const ParkCategory({
    required this.id,
    required this.kind,
    required this.name,
    required this.active,
  });

  final String id;
  final ParkPlaceKind kind;
  final String name;
  final bool active;

  static ParkCategory? fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null || data['name'] is! String ||
        data['kind'] is! String) {
      return null;
    }
    final matches = ParkPlaceKind.values.where(
      (value) => value.name == data['kind'],
    );
    if (matches.isEmpty) return null;
    return ParkCategory(
      id: snapshot.id,
      kind: matches.first,
      name: (data['name'] as String).trim(),
      active: data['active'] == true,
    );
  }
}

class ParkCategoryRepository {
  ParkCategoryRepository(this.db);
  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _collection =>
      db.collection('parkCategories');

  static String? validateName(String? raw) {
    final name = raw?.trim() ?? '';
    if (name.isEmpty) return 'Enter a category name.';
    if (name.length < 2) return 'Enter at least 2 characters.';
    if (name.length > 60) return 'Use 60 characters or fewer.';
    if (!RegExp(r'[A-Za-z\u00C0-\u024F\u4E00-\u9FFF]').hasMatch(name)) {
      return 'Enter a valid category name.';
    }
    return null;
  }

  Stream<List<ParkCategory>> watchAll() => _collection.snapshots().map((snapshot) {
    final values = snapshot.docs.map(ParkCategory.fromSnapshot)
        .whereType<ParkCategory>().toList();
    values.sort((a, b) {
      final typeOrder = a.kind.index.compareTo(b.kind.index);
      return typeOrder != 0 ? typeOrder :
          a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return values;
  });

  Future<List<ParkCategory>> _forKind(ParkPlaceKind kind) async {
    final snapshot = await _collection.where('kind', isEqualTo: kind.name).get();
    return snapshot.docs.map(ParkCategory.fromSnapshot)
        .whereType<ParkCategory>().toList();
  }

  Future<void> add(ParkPlaceKind kind, String rawName) async {
    final error = validateName(rawName);
    if (error != null) throw ArgumentError(error);
    final name = rawName.trim();
    final all = await _forKind(kind);
    if (all.any((c) => c.name.toLowerCase() == name.toLowerCase())) {
      throw StateError('This category already exists.');
    }
    // Auto IDs stay stable when an administrator renames a category.
    await _collection.add({
      'kind': kind.name,
      'name': name,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rename(ParkCategory category, String rawName) async {
    final error = validateName(rawName);
    if (error != null) throw ArgumentError(error);
    final name = rawName.trim();
    if (name == category.name) return;
    final all = await _forKind(category.kind);
    if (all.any((c) => c.id != category.id &&
        c.name.toLowerCase() == name.toLowerCase())) {
      throw StateError('This category already exists.');
    }
    final linked = await db.collection('attractions')
        .where('categoryId', isEqualTo: category.id).get();
    // One atomic batch keeps visitor labels in sync with the renamed category.
    if (linked.docs.length > 12) {
      throw StateError('Rename smaller groups of places first.');
    }
    final batch = db.batch();
    batch.update(_collection.doc(category.id), {
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final doc in linked.docs) {
      batch.update(doc.reference, {
        'category': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> setActive(ParkCategory category, bool active) =>
      _collection.doc(category.id).update({
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> remove(ParkCategory category) async {
    final linked = await db.collection('attractions')
        .where('categoryId', isEqualTo: category.id).limit(1).get();
    if (linked.docs.isNotEmpty) {
      throw StateError('Move the places to another category first.');
    }
    // Protect records created before the category-ID migration, too.
    final legacy = await db.collection('attractions')
        .where('category', isEqualTo: category.name).get();
    if (legacy.docs.any((doc) {
      final data = doc.data();
      final type = data['kind'] as String?;
      return type == category.kind.name ||
          (type == null &&
              ParkPlaceKind.fromCategory(category.name) == category.kind);
    })) {
      throw StateError('Move the places to another category first.');
    }
    await _collection.doc(category.id).delete();
  }
}
