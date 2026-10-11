import 'package:flutter/material.dart';

import '../theme.dart';

/// 시트 안 사진: 잘리지 않게 전체를 보여주고(최대 높이 안에서 contain), 누르면 전체 화면으로 열려 확대·이동할 수 있어요.
class ZoomImage extends StatelessWidget {
  const ZoomImage({super.key, required this.provider, this.maxHeight = 340, this.background, this.onError});

  final ImageProvider provider;
  final double maxHeight;
  final Color? background;
  final Widget? onError;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showZoom(context, provider),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              color: background ?? AppColors.line.withValues(alpha: 0.35),
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Image(
                image: provider,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (c, e, s) => onError ?? const SizedBox(height: 120),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                child: const Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showZoom(BuildContext context, ImageProvider provider) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.of(ctx).pop(),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: Image(image: provider, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
