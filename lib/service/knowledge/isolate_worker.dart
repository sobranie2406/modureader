import 'dart:async';
import 'dart:isolate';

/// Small request/reply actor. Native objects stay in the worker; only plain
/// data crosses ports. Unexpected exits fail pending requests instead of hanging.
class IsolateWorker {
  IsolateWorker._();
  final _events = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _send;
  var _nextId = 0;
  var _closed = false;

  static Future<IsolateWorker> start(
      void Function(List<Object?>) entry, Object? initialization) async {
    final worker = IsolateWorker._();
    worker._subscription = worker._events.listen(worker._receive);
    Future<void> spawn() async {
      try {
        worker._isolate = await Isolate.spawn(
            entry, <Object?>[worker._events.sendPort, initialization],
            onExit: worker._events.sendPort,
            onError: worker._events.sendPort,
            errorsAreFatal: true);
      } catch (error) {
        worker._fail(error);
        rethrow;
      }
    }

    try {
      await Future.wait<void>([
        spawn(),
        worker._ready.future.then((port) {
          worker._send = port;
        }),
      ]);
      return worker;
    } catch (_) {
      worker.dispose();
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      if (!_ready.isCompleted) _ready.complete(message);
    } else if (message is List && message.length == 3 && message[0] is int) {
      final response = _pending.remove(message[0]);
      if (message[1] == true) {
        response?.complete(message[2]);
      } else {
        response?.completeError(StateError(message[2].toString()));
      }
    } else {
      _fail(StateError('后台向量处理进程已退出，请重试。'));
    }
  }

  Future<Object?> call(String method, Object? arguments) {
    if (_closed || _send == null) {
      return Future.error(StateError('后台向量处理进程不可用'));
    }
    final id = _nextId++;
    final result = Completer<Object?>();
    _pending[id] = result;
    try {
      _send!.send([id, method, arguments]);
    } catch (error, stack) {
      _pending.remove(id);
      result.completeError(error, stack);
    }
    return result.future;
  }

  void _fail(Object error) {
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final result in _pending.values) {
      result.completeError(error);
    }
    _pending.clear();
  }

  /// Only dispose after the native close reply; killing Dart does not cancel
  /// an in-flight native inference request.
  void dispose() {
    _fail(StateError('后台向量处理进程已关闭'));
    _isolate?.kill(priority: Isolate.immediate);
    _subscription?.cancel();
    _events.close();
  }
}

/// Serial worker-side loop, shared with tests. Close errors are returned too.
Future<void> serveIsolateWorker(
    SendPort replies, Future<Object?> Function(String, Object?) handle) async {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  await for (final dynamic request in requests) {
    final message = request as List;
    final id = message[0] as int;
    final method = message[1] as String;
    try {
      replies.send([id, true, await handle(method, message[2])]);
    } catch (error) {
      replies.send([id, false, error.toString()]);
    }
    if (method == 'close') {
      requests.close();
      break;
    }
  }
}
