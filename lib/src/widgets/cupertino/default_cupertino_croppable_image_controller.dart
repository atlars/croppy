import 'package:croppy/src/src.dart';
import 'package:flutter/material.dart';

class DefaultCupertinoCroppableImageController extends StatefulWidget {
  const DefaultCupertinoCroppableImageController({
    super.key,
    required this.builder,
    required this.initialData,
    this.allowedAspectRatios,
    this.onSubmit,
    this.cropShapeFn,
    this.enabledTransformations,
  });

  final CroppableImageData initialData;
  final CroppableImageOnSubmitFn? onSubmit;
  final CropShapeFn? cropShapeFn;
  final List<CropAspectRatio?>? allowedAspectRatios;
  final List<Transformation>? enabledTransformations;

  final Widget Function(
    BuildContext context,
    CupertinoCroppableImageController controller,
  ) builder;

  @override
  State<DefaultCupertinoCroppableImageController> createState() =>
      _DefaultCupertinoCroppableImageControllerState();
}

class _DefaultCupertinoCroppableImageControllerState
    extends State<DefaultCupertinoCroppableImageController>
    with TickerProviderStateMixin {
  CupertinoCroppableImageController? _controller;

  @override
  void initState() {
    super.initState();
    _prepareController();
  }

  Future<void> _prepareController() async {
    _controller = CupertinoCroppableImageController(
      vsync: this,
      data: widget.initialData,
      onSubmit: widget.onSubmit,
      cropShapeFn: widget.cropShapeFn ?? aabbCropShapeFn,
      allowedAspectRatios: widget.allowedAspectRatios,
      enabledTransformations:
          widget.enabledTransformations ?? Transformation.values,
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const SizedBox.shrink();
    }

    return widget.builder(context, _controller!);
  }
}
