import 'dart:async';

/// For cumulative snapshots, not deltas. Emit the first immediately and keep
/// only the latest snapshot per interval. Flush the final text before done/error.
Stream<T> coalesceSnapshots<T>(Stream<T> source,
    {Duration interval = const Duration(milliseconds: 80)}) {
  late StreamController<T> output;
  StreamSubscription<T>? subscription;
  Timer? timer;
  T? latest;
  var pending = false;
  void flush() {
    if (!pending) return;
    final value = latest as T;
    pending = false;
    latest = null;
    output.add(value);
  }

  void tick() {
    timer = null;
    if (!pending) return;
    flush();
    timer = Timer(interval, tick);
  }

  output = StreamController<T>(
    onListen: () {
      subscription = source.listen((value) {
        latest = value;
        pending = true;
        if (timer == null) {
          flush();
          timer = Timer(interval, tick);
        }
      }, onError: (Object error, StackTrace stack) {
        timer?.cancel();
        timer = null;
        flush();
        output.addError(error, stack);
      }, onDone: () {
        timer?.cancel();
        flush();
        output.close();
      });
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      timer?.cancel();
      pending = false;
      latest = null;
      await subscription?.cancel();
    },
  );
  return output.stream;
}
