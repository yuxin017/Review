import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/souvenir_shop_page.dart';
import 'souvenir_product_image.dart';

/// Ticket Hub preview: real Admin-managed products, never hardcoded souvenirs.
class LiveSouvenirsSection extends StatelessWidget {
  const LiveSouvenirsSection({super.key});

  static const _rose = Color(0xFFA74F55);
  static const _ink = Color(0xFF302A2A);
  static const _muted = Color(0xFF8B7878);

  bool _isShop(Map<String, dynamic> data) {
    if (data['deletedAt'] != null) return false;
    final kind = (data['kind'] ?? data['category'] ?? '')
        .toString().toLowerCase();
    return kind.contains('shop') || kind.contains('retail') ||
        kind.contains('souvenir') || kind.contains('shopping') ||
        kind.contains('gift');
  }

  void _openShop(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SouvenirShopPage()),
      );

  Widget _productCard(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = (data['name'] ?? 'Souvenir').toString();
    final imageUrl = (data['imageUrl'] ?? '').toString();
    final price = (data['priceMinor'] as num?)?.toInt() ?? 0;
    final stock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
    return SizedBox(
      width: 146,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFF0DFDC)),
        ),
        child: InkWell(
          onTap: () => _openShop(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              SouvenirProductImage(url: imageUrl, width: 146, height: 105),
              if (stock <= 0)
                Positioned(right: 5, top: 5, child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Text('Sold out',
                        style: TextStyle(color: _rose, fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                )),
            ]),
            Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: _ink))),
            const Spacer(),
            Padding(padding: const EdgeInsets.fromLTRB(10, 3, 10, 10),
              child: Row(children: [
                Expanded(child: Text('RM ${(price / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                      color: _rose))),
                const Icon(Icons.arrow_outward, size: 14, color: _muted),
              ])),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('Shop Souvenirs',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
              color: _ink))),
        TextButton.icon(onPressed: () => _openShop(context),
          label: const Text('See All'),
          icon: const Icon(Icons.chevron_right, size: 17),
          iconAlignment: IconAlignment.end,
          style: TextButton.styleFrom(foregroundColor: _rose)),
      ]),
      const SizedBox(height: 4),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('attractions').snapshots(),
        builder: (context, shopsSnapshot) {
          if (shopsSnapshot.hasError) {
            return const Text('Shops could not be loaded.',
              style: TextStyle(color: _muted));
          }
          if (!shopsSnapshot.hasData) {
            return const SizedBox(height: 32,
                child: Center(child: LinearProgressIndicator()));
          }
          final ids = shopsSnapshot.data!.docs
              .where((doc) => _isShop(doc.data()))
              .map((doc) => doc.id).toSet();
          if (ids.isEmpty) {
            return const Text('No souvenir shops available yet.',
                style: TextStyle(color: _muted));
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('parkMenuItems')
                .where('active', isEqualTo: true).snapshots(),
            builder: (context, productsSnapshot) {
              if (productsSnapshot.hasError) {
                return const Text('Unable to load souvenirs.',
                  style: TextStyle(color: _rose));
              }
              if (!productsSnapshot.hasData) {
                return const SizedBox(height: 32,
                    child: Center(child: LinearProgressIndicator()));
              }
              final products = productsSnapshot.data!.docs
                  .where((doc) => ids.contains(doc.data()['storeId']))
                  .toList()..sort((a, b) {
                    final aTime = a.data()['createdAt'] as Timestamp?;
                    final bTime = b.data()['createdAt'] as Timestamp?;
                    return (bTime?.millisecondsSinceEpoch ?? 0)
                        .compareTo(aTime?.millisecondsSinceEpoch ?? 0);
                  });
              if (products.isEmpty) {
                return const Text('No souvenirs available yet.',
                    style: TextStyle(color: _muted));
              }
              return SizedBox(height: 185,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: products.length < 3 ? products.length : 3,
                  separatorBuilder: (_, index) => const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _productCard(context, products[index]),
                ),
              );
            },
          );
        },
      ),
    ]);
  }
}
