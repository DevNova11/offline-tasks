import 'dart:async';

/// Minimal async mutex: callers run one at a time, in arrival order.
class Lock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() body) {
    final prev = _last;
    final done = Completer<void>();
    _last = done.future;
    return prev.then((_) => body()).whenComplete(done.complete);
  }
}
