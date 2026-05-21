import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';

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
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
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
          seedColor: Colors.orange,
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
  late final PageController _pageController;
  var _cropSettings = CropSettings.initial();
  final _items = <_CroppableItem>[];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.9,
    );

    final random = Random();
    for (var i = 0; i < 80; i++) {
      final image = NetworkImage(
        'https://test-photos-qklwjen.s3.eu-west-3.amazonaws.com/image${random.nextInt(80) + 1}.jpg',
        headers: const {'accept': '*/*'},
      );

      _items.add(
        _CroppableItem.image(
          originalImageProvider: image,
          previewImageProvider: image,
        ),
      );
    }
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

      _items.insert(
        0,
        _CroppableItem.image(
          originalImageProvider: provider,
          previewImageProvider: provider,
        ),
      );

      setState(() {});
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
      _items.insert(
        0,
        _CroppableItem.video(
          videoPath: path,
          player: player,
          videoController: controller,
          mediaSize: videoSize,
        ),
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
    _pageController.dispose();
    for (final item in _items) {
      item.player?.dispose();
    }
    super.dispose();
  }

  int get _currentPage {
    if (_items.isEmpty) return 0;
    final current = _pageController.page?.round() ?? 0;
    return current.clamp(0, _items.length - 1);
  }

  Future<CroppableImageData?> _initialDataFor(_CroppableItem item) async {
    if (item.data != null) return item.data;

    if (item.isImage) {
      return CroppableImageData.fromImageProvider(
        item.originalImageProvider!,
        cropPathFn: _cropSettings.cropShapeFn,
      );
    }

    if (item.mediaSize != null) {
      return CroppableImageData.initialWithCropPathFn(
        imageSize: item.mediaSize!,
        cropPathFn: _cropSettings.cropShapeFn,
      );
    }

    return null;
  }

  Future<void> _applyCropResult(int page, CroppableImageData data) async {
    final item = _items[page];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      floatingActionButton: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          spacing: 12,
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.extended(
              heroTag: 'fab-pick-image',
              onPressed: _pickImage,
              label: const Text('Pick image'),
            ),
            FloatingActionButton.extended(
              heroTag: 'fab-pick-video',
              onPressed: _pickVideo,
              label: const Text('Pick video'),
            ),
            FloatingActionButton(
              heroTag: 'fab-cupertino',
              onPressed: () async {
                if (_items.isEmpty) return;
                final page = _currentPage;
                final item = _items[page];
                final initialData = await _initialDataFor(item);
                if (initialData == null) return;
                if (!context.mounted) return;

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
                  allowedAspectRatios: _cropSettings.forcedAspectRatio != null
                      ? [_cropSettings.forcedAspectRatio!]
                      : null,
                  onSubmit: (result) async {
                    await _applyCropResult(page, result);
                    return result;
                  },
                );
              },
              child: const Icon(Icons.apple_rounded),
            ),
            FloatingActionButton(
              heroTag: 'fab-material',
              onPressed: () async {
                if (_items.isEmpty) return;
                final page = _currentPage;
                final item = _items[page];
                final initialData = await _initialDataFor(item);
                if (initialData == null) return;
                if (!context.mounted) return;

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
                  allowedAspectRatios: _cropSettings.forcedAspectRatio != null
                      ? [_cropSettings.forcedAspectRatio!]
                      : null,
                  showLoadingIndicatorOnSubmit: false,
                  onSubmit: (result) async {
                    await _applyCropResult(page, result);
                    return result;
                  },
                );
              },
              child: const Icon(Icons.android_rounded),
            ),
            FloatingActionButton(
              heroTag: 'fab-custom',
              onPressed: () async {
                if (_items.isEmpty) return;
                final page = _currentPage;
                final item = _items[page];
                if (item.isVideo) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Custom cropper supports images only in this demo.',
                      ),
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
                  await _applyCropResult(page, result);
                }
              },
              child: const Icon(Icons.edit_rounded),
            ),
          ],
        ),
      ),
      body: Center(
        child: PageView.builder(
          controller: _pageController,
          itemCount: _items.length,
          scrollDirection: Axis.horizontal,
          padEnds: true,
          itemBuilder: (context, i) {
            final item = _items[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                  child: item.isVideo
                      ? _VideoPreview(item: item)
                      : Image(image: item.previewImageProvider!)),
            );
          },
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
    return SizedBox(
      width: mediaSize.width,
      height: mediaSize.height,
      child: Video(
        controller: controller,
        width: mediaSize.width,
        height: mediaSize.height,
        fit: BoxFit.fill,
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
    if (item.data == null) {
      return _VideoCanvas(
        controller: item.videoController!,
        mediaSize: item.mediaSize!,
      );
    }

    final data = item.data!;
    final transform = Matrix4.identity()
      ..translateByDouble(-data.cropRect.left, -data.cropRect.top, 0.0, 1.0)
      ..multiply(data.totalImageTransform);

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: data.cropRect.width,
        height: data.cropRect.height,
        child: ClipPath(
          clipper: CropShapeClipper(data.cropShape),
          child: Transform(
            transform: transform,
            child: _VideoCanvas(
              controller: item.videoController!,
              mediaSize: data.imageSize,
            ),
          ),
        ),
      ),
    );
  }
}
