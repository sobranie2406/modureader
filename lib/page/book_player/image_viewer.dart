import 'package:modu_reader/utils/app_motion.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:modu_reader/l10n/modu_strings.dart';

import 'package:modu_reader/utils/save_img.dart';
import 'package:modu_reader/utils/get_path/get_temp_dir.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/save_image_to_path.dart';
import 'package:modu_reader/utils/share_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class ImageGalleryIndex {
  final int count;
  final int initialIndex;
  const ImageGalleryIndex(this.count, this.initialIndex);
}

class ImageViewer extends StatefulWidget {
  final String image;
  final String bookName;
  final Future<ImageGalleryIndex> Function()? loadIndex;
  final Future<String> Function(int)? loadImage;

  const ImageViewer(
      {super.key,
      required this.image,
      required this.bookName,
      this.loadIndex,
      this.loadImage});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  PageController? _pages;
  ImageGalleryIndex? _index;
  int _current = 0;
  bool _indexFailed = false;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    if (widget.loadIndex == null) return;
    try {
      final index = await widget.loadIndex!();
      if (!mounted) return;
      if (index.count < 1 ||
          index.initialIndex < 0 ||
          index.initialIndex >= index.count) {
        throw StateError('Invalid gallery index');
      }
      setState(() {
        _index = index;
        _current = index.initialIndex;
        _pages = PageController(initialPage: _current);
      });
    } catch (_) {
      if (mounted) setState(() => _indexFailed = true);
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (index == null)
          _GalleryPage(
              bookName: widget.bookName, load: () async => widget.image)
        else
          PhotoViewGestureDetectorScope(
            axis: Axis.horizontal,
            child: PageView.builder(
              controller: _pages,
              itemCount: index.count,
              onPageChanged: (value) => setState(() => _current = value),
              itemBuilder: (context, position) => _GalleryPage(
                key: ValueKey(position),
                bookName: widget.bookName,
                load: () async => position == index.initialIndex
                    ? widget.image
                    : await widget.loadImage!(position),
              ),
            ),
          ),
        SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white)),
            const Spacer(),
            if (index != null) ...[
              IconButton(
                  onPressed: _current > 0
                      ? () => _pages!.jumpToPage(_current - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  color: Colors.white,
                  disabledColor: Colors.white30),
              Text('${_current + 1} / ${index.count}',
                  style: const TextStyle(color: Colors.white)),
              IconButton(
                  onPressed: _current + 1 < index.count
                      ? () => _pages!.jumpToPage(_current + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  color: Colors.white,
                  disabledColor: Colors.white30),
            ] else if (widget.loadIndex != null)
              Flexible(
                  child: Text(
                      _indexFailed
                          ? ModuStrings.text(
                              context, '图片列表加载失败', 'Image list unavailable')
                          : ModuStrings.text(
                              context, '正在整理图片…', 'Loading image list…'),
                      style: const TextStyle(color: Colors.white))),
          ]),
        )),
      ]),
    );
  }
}

class _GalleryPage extends StatefulWidget {
  final String bookName;
  final Future<String> Function() load;
  const _GalleryPage({super.key, required this.bookName, required this.load});
  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final PhotoViewController _controller = PhotoViewController();
  late Future<String> _image;
  String? _decodedSource;
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    _image = widget.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_bytes != null) MemoryImage(_bytes!).evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: TextButton.icon(
              onPressed: () => setState(() => _image = widget.load()),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: Text(
                  ModuStrings.text(
                      context, '图片加载失败，点击重试', 'Image unavailable. Retry'),
                  style: const TextStyle(color: Colors.white)),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(
                child: EinkStaticIndicator(child: CircularProgressIndicator()));
          }
          return _buildImage(context, snapshot.data!);
        },
      );

  void _handleScroll(PointerScrollEvent event) {
    final double scrollDelta = event.scrollDelta.dy;
    final double currentScale = _controller.scale ?? 1.0;

    // Adjust sensitivity: negative delta = zoom in, positive = zoom out
    final double scaleFactor = scrollDelta > 0 ? 0.95 : 1.05;
    final double newScale = currentScale * scaleFactor;

    // Apply the new scale with constraints
    _controller.scale = newScale;
  }

  Widget _buildImage(BuildContext context, String image) {
    Uint8List? imageBytes;
    String? imgType;

    try {
      final List<String> parts = image.split(',');
      String base64 = parts[1];
      if (_decodedSource != image) {
        _bytes = base64Decode(base64);
        _decodedSource = image;
      }
      imageBytes = _bytes;
      imgType = parts[0].split('/')[1].split(';')[0];
    } catch (e) {
      AnxLog.severe('Error decoding image: $e');
      return const Center(child: Text('Error'));
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(event);
        }
      },
      child: Stack(
        children: [
          PhotoView(
            imageProvider: MemoryImage(imageBytes!),
            controller: _controller,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                  ModuStrings.text(
                      context, '无法显示这张图片', 'Unable to display this image'),
                  style: const TextStyle(color: Colors.white)),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) => const Center(
              child: EinkStaticIndicator(child: CircularProgressIndicator()),
            ),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 3,
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  children: [
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: () {
                            SaveImg.downloadImg(
                                imageBytes!, imgType!, widget.bookName);
                          },
                          icon: const Icon(Icons.download, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: () async {
                            final path = await saveB64ImageToPath(
                              image,
                              (await getAnxTempDir()).path,
                              "Modu_${widget.bookName}",
                            );

                            await shareFile(filePath: path);
                          },
                          icon: const Icon(Icons.share, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
