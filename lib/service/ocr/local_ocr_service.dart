import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'ocr_model_store.dart';
import 'ocr_processing.dart';
import 'ocr_model_metadata.dart';

class OcrCancellation {
  bool cancelled = false;
  void Function()? _notify;
  void cancel() {
    cancelled = true;
    _notify?.call();
  }

  void check() {
    if (cancelled) throw StateError('OCR cancelled');
  }
}

class LocalOcrService {
  static bool _running = false;

  /// Single on-demand job, no persistent queue, no restart/recovery task.
  Future<String> recognize(
          Uint8List image, OcrModelStore store, OcrCancellation cancellation,
          {void Function(int, int)? progress}) =>
      store.withModelFiles(
          () => _recognize(image, store, cancellation, progress: progress));

  Future<String> _recognize(
      Uint8List image, OcrModelStore store, OcrCancellation cancellation,
      {void Function(int, int)? progress}) async {
    if (_running) throw StateError('Another OCR task is running');
    _running = true;
    final port = ReceivePort();
    Isolate? worker;
    try {
      cancellation.check();
      await store.verify();
      cancellation.check();
      final root = await store.root();
      final token = RootIsolateToken.instance;
      if (token == null) throw StateError('OCR worker unavailable');
      worker = await Isolate.spawn(
          _ocrWorker, [port.sendPort, token, root.path, image],
          onError: port.sendPort, onExit: port.sendPort);
      await for (final event in port) {
        if (event is SendPort) {
          cancellation._notify = () => event.send('cancel');
          if (cancellation.cancelled) event.send('cancel');
        } else if (event is List && event.first == 'progress') {
          progress?.call(event[1] as int, event[2] as int);
        } else if (event is List && event.first == 'result') {
          cancellation.check();
          return event[1] as String;
        } else {
          throw StateError(
              'OCR failed or cancelled; select a smaller area and retry');
        }
      }
      throw StateError('OCR worker stopped');
    } finally {
      cancellation._notify = null;
      port.close();
      worker?.kill();
      _running = false;
    }
  }
}

@pragma('vm:entry-point')
void _ocrWorker(List<Object?> args) async {
  final reply = args[0] as SendPort;
  BackgroundIsolateBinaryMessenger.ensureInitialized(
      args[1] as RootIsolateToken);
  final commands = ReceivePort();
  var cancelled = false;
  commands.listen((_) => cancelled = true);
  reply.send(commands.sendPort);
  final sessions = <String, OrtSession>{};
  const android = MethodChannel('com.modu.reader/local_ocr');
  Object? result;
  try {
    final path = args[2] as String;
    final alphabet = ocrAlphabet(await File('$path/rec.onnx').readAsBytes());
    if (Platform.isAndroid) {
      await android.invokeMethod<void>('load', {'path': path});
    } else {
      for (final name in ['det', 'rec']) {
        if (cancelled) throw StateError('cancelled');
        sessions[name] = await OnnxRuntime().createSession('$path/$name.onnx',
            options: OrtSessionOptions(
                providers: const [OrtProvider.CPU],
                intraOpNumThreads: 2,
                interOpNumThreads: 1,
                useArena: false));
      }
    }
    Future<(List<double>, List<int>)> run(
        String name, Float32List values, List<int> shape) async {
      if (cancelled) throw StateError('cancelled');
      if (Platform.isAndroid) {
        final value = await android.invokeMapMethod<String, dynamic>(
            'run', {'name': name, 'data': values, 'shape': shape});
        return (
          (value!['data'] as List).map((v) => (v as num).toDouble()).toList(),
          (value['shape'] as List).cast<int>()
        );
      }
      final session = sessions[name]!;
      final input = await OrtValue.fromList(values, shape);
      Map<String, OrtValue> outputs = {};
      try {
        outputs = await session.run({session.inputNames.first: input});
        final out = outputs[session.outputNames.first]!;
        return (
          (await out.asFlattenedList())
              .map((v) => (v as num).toDouble())
              .toList(),
          out.shape
        );
      } finally {
        await input.dispose();
        for (final value in outputs.values) {
          await value.dispose();
        }
      }
    }

    result = [
      'result',
      await recognizeOcrImage(args[3] as Uint8List, alphabet, run,
          cancelled: () => cancelled,
          progress: (n, total) => reply.send(['progress', n, total]))
    ];
  } catch (_) {
    result = ['error'];
  } finally {
    try {
      if (Platform.isAndroid) {
        await android.invokeMethod<void>('close');
      }
      for (final session in sessions.values) {
        await session.close();
      }
    } catch (_) {
      result = ['error'];
    }
    commands.close();
    reply.send(result);
  }
}
