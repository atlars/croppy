import 'package:croppy/croppy.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

export 'cupertino_pages.dart';
export 'material_pages.dart';

/// An adaptive method that will use the Cupertino implementation on iOS and
/// macOS and the Material implementation on all other platforms.
///
/// See either [showMaterialImageCropper] or [showCupertinoImageCropper] for
/// more information on the parameters.
Future<CroppableImageData?> showAdaptiveImageCropper(
  BuildContext context, {
  required WidgetBuilder contentBuilder,
  required CroppableImageData initialData,
  CroppableImageOnSubmitFn? onSubmit,
  CropShapeFn? cropPathFn,
  List<CropAspectRatio?>? allowedAspectRatios,
  List<Transformation>? enabledTransformations,
  Object? heroTag,
  bool shouldPopAfterCrop = true,
  Locale? locale,
  ThemeData? materialThemeData,
  CupertinoThemeData? cupertinoThemeData,
  bool showLoadingIndicatorOnSubmit = false,
  List<CropShapeType> showGestureHandlesOn = const [CropShapeType.aabb],
}) async {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => showCupertinoImageCropper(
        context,
        contentBuilder: contentBuilder,
        initialData: initialData,
        onSubmit: onSubmit,
        cropPathFn: cropPathFn,
        allowedAspectRatios: allowedAspectRatios,
        enabledTransformations: enabledTransformations,
        heroTag: heroTag,
        shouldPopAfterCrop: shouldPopAfterCrop,
        locale: locale,
        themeData: cupertinoThemeData,
        showLoadingIndicatorOnSubmit: showLoadingIndicatorOnSubmit,
        showGestureHandlesOn: showGestureHandlesOn,
      ),
    _ => showMaterialImageCropper(
        context,
        contentBuilder: contentBuilder,
        initialData: initialData,
        onSubmit: onSubmit,
        cropPathFn: cropPathFn,
        allowedAspectRatios: allowedAspectRatios,
        enabledTransformations: enabledTransformations,
        heroTag: heroTag,
        shouldPopAfterCrop: shouldPopAfterCrop,
        locale: locale,
        themeData: materialThemeData,
        showLoadingIndicatorOnSubmit: showLoadingIndicatorOnSubmit,
        showGestureHandlesOn: showGestureHandlesOn,
      ),
  };
}
