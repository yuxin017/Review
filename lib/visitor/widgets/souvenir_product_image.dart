import 'package:flutter/material.dart';

/// Display the same Firebase Storage download URL on Flutter web and Android.
/// A browser HTML image fallback helps when the server does not support
/// cross-origin canvas image reads. Invalid or inaccessible URLs still need
/// correcting at the source (Admin product image / Storage).
class SouvenirProductImage extends StatelessWidget {
  const SouvenirProductImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.radius = 0,
  });

  final String url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final src = url.trim();
    final parsed = Uri.tryParse(src);
    final usable = parsed != null &&
        (parsed.scheme == 'https' || parsed.scheme == 'http') &&
        parsed.host.isNotEmpty;
    Widget placeholder() => Container(
      color: const Color(0xFFF5E8E5),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            usable ? Icons.broken_image_outlined : Icons.image_outlined,
            color: const Color(0xFFB78D8F),
            size: 31,
          ),
          const SizedBox(height: 5),
          Text(
            usable ? 'Photo unavailable' : 'No product photo',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A7573)),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: width,
        child: !usable
            ? placeholder()
            : Image.network(
                src,
                width: width,
                height: height,
                fit: fit,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (context, error, stackTrace) {
                  // Don't log download tokens or full Firebase Storage URLs.
                  debugPrint('Souvenir image load failed (${parsed?.host ?? 'unknown'}): '
                      '${error.runtimeType}');
                  return placeholder();
                },
              ),
      ),
    );
  }
}
