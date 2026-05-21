import 'dart:io';
import 'dart:math';

import 'package:croppy/croppy.dart';
import 'package:example/custom_cropper.dart';
import 'package:example/settings_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
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

      _imageProviders.add(image);
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path!;

      if (kIsWeb) {
        _imageProviders.insert(0, NetworkImage(path));
      } else {
        _imageProviders.insert(0, FileImage(File(path)));
      }

      setState(() {});
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  final _imageProviders = <ImageProvider>[];
  final _data = <int, CroppableImageData>{};

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
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _pickImage,
            label: const Text('Pick image'),
          ),
          const SizedBox(width: 16.0),
          FloatingActionButton(
            onPressed: () async {
              final page = _pageController.page?.round() ?? 0;
              final imageProvider = _imageProviders[page];
              final initialData = _data[page] ??
                  await CroppableImageData.fromImageProvider(
                    imageProvider,
                    cropPathFn: _cropSettings.cropShapeFn,
                  );
              if (!context.mounted) return;

              showCupertinoImageCropper(
                context,
                contentBuilder: (context) => Image(image: imageProvider),
                initialData: initialData,
                locale: _cropSettings.locale,
                heroTag: 'image-$page',
                showGestureHandlesOn: _cropSettings.showGestureHandlesOn,
                cropPathFn: _cropSettings.cropShapeFn,
                showLoadingIndicatorOnSubmit: false,
                enabledTransformations: _cropSettings.enabledTransformations,
                allowedAspectRatios: _cropSettings.forcedAspectRatio != null
                    ? [_cropSettings.forcedAspectRatio!]
                    : null,
                onSubmit: (result) {
                  setState(() {
                    _data[page] = result;
                  });
                  return result;
                },
              );
            },
            heroTag: 'fab-cupertino',
            child: const Icon(Icons.apple_rounded),
          ),
          const SizedBox(width: 16.0),
          FloatingActionButton(
            onPressed: () async {
              final page = _pageController.page?.round() ?? 0;
              final imageProvider = _imageProviders[page];
              final initialData = _data[page] ??
                  await CroppableImageData.fromImageProvider(
                    imageProvider,
                    cropPathFn: _cropSettings.cropShapeFn,
                  );
              if (!context.mounted) return;

              showMaterialImageCropper(
                context,
                contentBuilder: (context) => Image(image: imageProvider),
                initialData: initialData,
                locale: _cropSettings.locale,
                heroTag: 'image-$page',
                cropPathFn: _cropSettings.cropShapeFn,
                enabledTransformations: _cropSettings.enabledTransformations,
                allowedAspectRatios: _cropSettings.forcedAspectRatio != null
                    ? [_cropSettings.forcedAspectRatio!]
                    : null,
                showLoadingIndicatorOnSubmit: false,
                onSubmit: (result) {
                  setState(() {
                    _data[page] = result;
                  });
                  return result;
                },
              );
            },
            heroTag: 'fab-material',
            child: const Icon(Icons.android_rounded),
          ),
          const SizedBox(width: 16.0),
          FloatingActionButton(
            onPressed: () async {
              final page = _pageController.page?.round() ?? 0;

              final imageProvider = _imageProviders[page];
              final result = await showCustomCropper(
                context,
                imageProvider,
                heroTag: 'image-$page',
                initialData: _data[page],
              );

              if (result != null && mounted) {
                setState(() {
                  _data[page] = result;
                });
              }
            },
            heroTag: 'fab-custom',
            child: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: Center(
        child: PageView.builder(
          controller: _pageController,
          itemCount: _imageProviders.length,
          scrollDirection: Axis.horizontal,
          padEnds: true,
          itemBuilder: (context, i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Hero(
                  tag: 'image-$i',
                  placeholderBuilder: (context, size, child) =>
                      Visibility.maintain(
                    visible: false,
                    child: child,
                  ),
                  child: Image(image: _imageProviders[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
