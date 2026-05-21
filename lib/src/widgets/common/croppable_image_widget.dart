import 'package:croppy/src/src.dart';
import 'package:flutter/material.dart';

/// Renders the interactive crop viewport content.
///
/// This widget composes three visual layers:
/// - the transformed media content [image]
/// - a dimmed mask outside the active crop shape
/// - interactive crop controls [cropHandles]
///
/// The media transform is derived from [controller] and applied in widget
/// space to support any kind of widgets (images, videos, etc.).
///
/// Dimming behavior is controlled by:
/// - [overlayOpacity] for overall mask/handle visibility
/// - [backgroundOpacity] for the darkness of the non-cropped region
class CroppableImageWidget extends StatelessWidget {
  const CroppableImageWidget({
    super.key,
    required this.controller,
    required this.image,
    required this.cropHandles,
    this.overlayOpacity = 1.0,
    this.gesturePadding = 0.0,
    this.backgroundOpacity = 0.85,
  });

  final Widget image;
  final Widget cropHandles;
  final CroppableImageController controller;
  final double gesturePadding;
  final double overlayOpacity;
  final double backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final staticCropRect = (controller is ResizeStaticLayoutMixin)
        ? (controller as ResizeStaticLayoutMixin).staticCropRect
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageData = controller.data;
        final viewportScale = controller.viewportScale;

        var scaledSize = imageData.cropRect.size * viewportScale;
        var layoutSize =
            (staticCropRect?.size ?? imageData.cropRect.size) * viewportScale;

        scaledSize = constraints
            .constrainSizeAndAttemptToPreserveAspectRatio(scaledSize);
        layoutSize = constraints
            .constrainSizeAndAttemptToPreserveAspectRatio(layoutSize);

        final padding = Offset(gesturePadding * 2, gesturePadding * 2);
        final handlesSize = scaledSize + padding;
        final layoutSizeWithPadding = layoutSize + padding;

        final imageOffset = Offset(gesturePadding, gesturePadding);
        final layoutCropRect = staticCropRect ?? imageData.cropRect;

        final scaleTransform = Matrix4.identity()
          ..scaleByDouble(viewportScale, viewportScale, 1.0, 1.0);
        final translationTransform = Matrix4.identity()
          ..translateByDouble(
            -layoutCropRect.left,
            -layoutCropRect.top,
            0.0,
            1.0,
          );
        final matrix = scaleTransform *
            translationTransform *
            imageData.totalImageTransform;

        var additionalOffset = Offset.zero;
        if (staticCropRect != null) {
          additionalOffset =
              (imageData.cropRect.topLeft - staticCropRect.topLeft) *
                  viewportScale;
        }

        final cropPath = imageData.cropShape
            .getTransformedPath(additionalOffset, viewportScale)
            .toUiPath()
            .shift(imageOffset);

        Widget transformedMedia() {
          return Positioned(
            left: imageOffset.dx,
            top: imageOffset.dy,
            width: imageData.imageSize.width,
            height: imageData.imageSize.height,
            child: IgnorePointer(
              child: Transform(
                alignment: Alignment.topLeft,
                transform: matrix,
                child: SizedBox.fromSize(
                  size: imageData.imageSize,
                  child: image,
                ),
              ),
            ),
          );
        }

        return SizedBox.fromSize(
          size: layoutSizeWithPadding,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              transformedMedia(),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CropOverlayPainter(
                      cropPath: cropPath,
                      overlayOpacity: overlayOpacity,
                      backgroundOpacity: backgroundOpacity,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: additionalOffset.dx,
                top: additionalOffset.dy,
                width: handlesSize.width,
                height: handlesSize.height,
                child: Opacity(
                  opacity: overlayOpacity,
                  child: cropHandles,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.cropPath,
    required this.overlayOpacity,
    required this.backgroundOpacity,
  });

  final Path cropPath;
  final double overlayOpacity;
  final double backgroundOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (overlayOpacity < epsilon || backgroundOpacity < epsilon) return;

    // The transformed media can render outside this widget's layout bounds.
    // Expand the dimming region so overflowed media is also darkened.
    final expandedOverlayRect = Rect.fromLTWH(
      -size.width * 2,
      -size.height * 2,
      size.width * 5,
      size.height * 5,
    );

    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(expandedOverlayRect)
      ..addPath(cropPath, Offset.zero);

    canvas.drawPath(
      overlayPath,
      Paint()
        ..color = Colors.black.withValues(
          alpha: overlayOpacity * backgroundOpacity,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropPath != cropPath ||
        oldDelegate.overlayOpacity != overlayOpacity ||
        oldDelegate.backgroundOpacity != backgroundOpacity;
  }
}
