import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:croppy/croppy.dart';
import 'package:example/custom_cropper.dart';
import 'package:example/settings_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class ExampleScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Croppy Demo',
      scrollBehavior: ExampleScrollBehavior(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          // primary: Colors.purple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var _cropSettings = CropSettings.initial();
  _CroppableItem? _selectedItem;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path!;

      final ImageProvider provider;
      if (kIsWeb) {
        provider = NetworkImage(path);
      } else {
        provider = FileImage(File(path));
      }

      setState(() {
        _selectedItem = _CroppableItem.image(
          originalImageProvider: provider,
          previewImageProvider: provider,
        );
      });
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.first.path;
    if (path == null) return;

    final player = Player();
    final controller = VideoController(player);

    await player.open(Media(path), play: true);
    await player.setPlaylistMode(PlaylistMode.single);
    await player.setVolume(0.0);

    final videoSize = await _waitForVideoSize(player);
    if (videoSize == null) {
      await player.dispose();
      return;
    }

    if (!mounted) {
      await player.dispose();
      return;
    }

    setState(() {
      _selectedItem?.player?.dispose();
      _selectedItem = _CroppableItem.video(
        videoPath: path,
        player: player,
        videoController: controller,
        mediaSize: videoSize,
      );
    });
  }

  Future<Size?> _waitForVideoSize(Player player) async {
    var width = player.state.width ?? 0;
    var height = player.state.height ?? 0;

    if (width > 0 && height > 0) {
      return Size(width.toDouble(), height.toDouble());
    }

    final completer = Completer<Size?>();
    late final StreamSubscription<int?> widthSub;
    late final StreamSubscription<int?> heightSub;

    void completeIfReady() {
      if (width > 0 && height > 0 && !completer.isCompleted) {
        completer.complete(Size(width.toDouble(), height.toDouble()));
      }
    }

    widthSub = player.stream.width.listen((value) {
      width = value ?? 0;
      completeIfReady();
    });
    heightSub = player.stream.height.listen((value) {
      height = value ?? 0;
      completeIfReady();
    });

    final size = await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => null,
    );

    await widthSub.cancel();
    await heightSub.cancel();
    return size;
  }

  @override
  void dispose() {
    _selectedItem?.player?.dispose();
    super.dispose();
  }

  Future<CroppableImageData?> _initialDataFor(_CroppableItem item) async {
    if (item.data != null) return item.data;
    if (item.isVideo) {
      return CroppableImageData.initialWithCropPathFn(
        imageSize: item.mediaSize!,
        cropPathFn: _cropSettings.cropShapeFn,
      );
    }
    return CroppableImageData.fromImageProvider(
      item.originalImageProvider!,
      cropPathFn: _cropSettings.cropShapeFn,
    );
  }

  Future<void> _applyCropResult(CroppableImageData data) async {
    final item = _selectedItem;
    if (item == null) return;
    if (item.isVideo) {
      setState(() {
        item.data = data;
      });
      return;
    }

    final image = await obtainImage(item.originalImageProvider!);
    final cropResult = await cropImage(image, data);

    final byteData = await cropResult.uiImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    cropResult.uiImage.dispose();

    if (!mounted || byteData == null) return;

    setState(() {
      item.data = data;
      item.previewImageProvider = MemoryImage(byteData.buffer.asUint8List());
    });
  }

  Future<void> _openCupertinoCropper() async {
    final item = _selectedItem;
    if (item == null) return;
    final initialData = await _initialDataFor(item);
    if (initialData == null || !mounted) return;

    showCupertinoImageCropper(
      context,
      contentBuilder: (context) => item.isVideo
          ? _VideoCanvas(
              controller: item.videoController!,
              mediaSize: item.mediaSize!,
            )
          : Image(image: item.originalImageProvider!),
      initialData: initialData,
      locale: _cropSettings.locale,
      showGestureHandlesOn: _cropSettings.showGestureHandlesOn,
      cropPathFn: _cropSettings.cropShapeFn,
      showLoadingIndicatorOnSubmit: false,
      enabledTransformations: _cropSettings.enabledTransformations,
      allowedAspectRatios: _cropSettings.forcedAspectRatio != null ? [_cropSettings.forcedAspectRatio!] : null,
      onSubmit: (result) async {
        print("Crop result: $result");
        await _applyCropResult(result);
        return result;
      },
    );
  }

  Future<void> _openMaterialCropper() async {
    final item = _selectedItem;
    if (item == null) return;
    final initialData = await _initialDataFor(item);
    if (initialData == null || !mounted) return;

    showMaterialImageCropper(
      context,
      contentBuilder: (context) => item.isVideo
          ? _VideoCanvas(
              controller: item.videoController!,
              mediaSize: item.mediaSize!,
            )
          : Image(image: item.originalImageProvider!),
      initialData: initialData,
      locale: _cropSettings.locale,
      cropPathFn: _cropSettings.cropShapeFn,
      enabledTransformations: _cropSettings.enabledTransformations,
      allowedAspectRatios: _cropSettings.forcedAspectRatio != null ? [_cropSettings.forcedAspectRatio!] : null,
      showLoadingIndicatorOnSubmit: false,
      onSubmit: (result) async {
        await _applyCropResult(result);
        return result;
      },
    );
  }

  Future<void> _openCustomCropper() async {
    final item = _selectedItem;
    if (item == null) return;
    if (item.isVideo) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom cropper supports images only in this demo.'),
        ),
      );
      return;
    }

    final result = await showCustomCropper(
      context,
      item.originalImageProvider!,
      initialData: item.data,
    );

    if (result != null && mounted) {
      await _applyCropResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = _selectedItem;
    final hasItem = selectedItem != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Croppy Demo'),
        actions: [
          IconButton(
            onPressed: () async {
              final newSettings = await showCropSettingsModal(
                context: context,
                initialSettings: _cropSettings,
              );

              setState(() {
                _cropSettings = newSettings;
              });
            },
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Pick image'),
                  ),
                  FilledButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library_rounded),
                    label: const Text('Pick video'),
                  ),
                  FilledButton.icon(
                    onPressed: hasItem ? _openCupertinoCropper : null,
                    icon: const Icon(Icons.apple_rounded),
                    label: const Text('Cupertino'),
                  ),
                  FilledButton.icon(
                    onPressed: hasItem ? _openMaterialCropper : null,
                    icon: const Icon(Icons.android_rounded),
                    label: const Text('Material'),
                  ),
                  FilledButton.icon(
                    onPressed: hasItem ? _openCustomCropper : null,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Custom'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: hasItem
            ? Padding(
                padding: const EdgeInsets.all(24.0),
                child: selectedItem.isVideo
                    ? _VideoPreview(item: selectedItem)
                    : Image(image: selectedItem.previewImageProvider!),
              )
            : const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'No media selected.\nPick an image or video to start cropping.',
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
}

class _CroppableItem {
  _CroppableItem.image({
    required this.originalImageProvider,
    required this.previewImageProvider,
  })  : isVideo = false,
        videoPath = null,
        player = null,
        videoController = null,
        mediaSize = null;

  _CroppableItem.video({
    required this.videoPath,
    required this.player,
    required this.videoController,
    required this.mediaSize,
  })  : isVideo = true,
        originalImageProvider = null,
        previewImageProvider = null;

  final bool isVideo;
  bool get isImage => !isVideo;

  final String? videoPath;
  final Player? player;
  final VideoController? videoController;
  final Size? mediaSize;

  final ImageProvider? originalImageProvider;
  ImageProvider? previewImageProvider;

  CroppableImageData? data;
}

class _VideoCanvas extends StatelessWidget {
  const _VideoCanvas({
    required this.controller,
    required this.mediaSize,
  });

  final VideoController controller;
  final Size mediaSize;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: mediaSize.aspectRatio,
      child: Video(
        fill: Colors.transparent,
        controller: controller,
        controls: null,
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.item});

  final _CroppableItem item;

  @override
  Widget build(BuildContext context) {
    final mediaSize = item.mediaSize!;

    if (item.data == null) {
      return _fitToScreen(
        size: mediaSize,
        child: _VideoCanvas(
          controller: item.videoController!,
          mediaSize: mediaSize,
        ),
      );
    }

    final data = item.data!;
    final cropRect = data.cropRect;
    final imageSize = data.imageSize;

    final matrix = Matrix4.identity()
      ..translateByDouble(-cropRect.left, -cropRect.top, 0.0, 1.0)
      ..multiply(data.totalImageTransform);

    return _fitToScreen(
      size: Size(cropRect.width, cropRect.height),
      child: ClipRect(
        child: Transform(
          alignment: Alignment.topLeft,
          transform: matrix,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: imageSize.width,
            maxWidth: imageSize.width,
            minHeight: imageSize.height,
            maxHeight: imageSize.height,
            child: _VideoCanvas(
              controller: item.videoController!,
              mediaSize: mediaSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// Scales [child], laid out at [size], down to fit available space.
Widget _fitToScreen({required Size size, required Widget child}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      );
    },
  );
}
