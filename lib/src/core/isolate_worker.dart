import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';

import '../utils/logger.dart';
import '../utils/unique_id.dart';
import 'worker_message.dart';

/// Provides classes for managing and communicating with Dart isolates in a pool.
///
/// This library defines [IsolateWorker] and [IsolateWorkerPool] for running tasks concurrently
/// in separate isolates, enabling parallel computation and offloading heavy work from the main thread.
///
/// - [IsolateWorker] manages a single isolate and allows sending messages to it using [WorkerMessage].
/// - [IsolateWorkerPool] manages a group of [IsolateWorker]s, supports round-robin or tag-based task assignment,
///   and provides methods to add, pause, resume, or kill workers.
///
/// Events and logging are supported for monitoring worker and pool activity.
///
/// Example usage:
/// ```dart
/// final pool = IsolateWorkerPool(numIsolates: 2);
/// await pool.start();
/// final result = await pool.sendMessage(MyWorkerMessage(...));
/// ```

enum IsolateWorkerEventType { coming, done }

class IsolateWorkerEvent {
  final IsolateWorkerEventType type;
  final Map<String, dynamic> message;
  IsolateWorkerEvent(this.type, this.message);
}

enum IsolateWorkerPoolEventType { add, remove, pause, resume }

class IsolateWorkerPoolEvent {
  final IsolateWorkerPoolEventType type;
  final String tag;
  IsolateWorkerPoolEvent(this.type, this.tag);
}

class IsolateWorker {
  final String _tag;
  late Isolate _isolate;
  late SendPort _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<String, Completer<dynamic>> _completers = {};

  final bool useLogger;

  final StreamController<IsolateWorkerEvent> _eventController = StreamController.broadcast();
  Stream<IsolateWorkerEvent> get events => _eventController.stream;

  StreamSubscription? _subscription;
  bool _isPaused = false;

  IsolateWorker({this.useLogger = false, String? tag}) : _tag = tag ?? "worker_${generateUniqueId()}";

  /// Starts the isolate and sets up communication.
  ///
  /// Waits for the isolate to be ready before returning.
  Future<void> start() async {
    final completer = Completer<SendPort>();

    _subscription = _receivePort.listen((dynamic message) async {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete(message);
      } else if (message is Map<String, dynamic>) {
        final id = message['messageId'] as String;
        _completers.remove(id)?.complete(message['result']);
        _eventController.add(IsolateWorkerEvent(IsolateWorkerEventType.done, {
          'worker': _tag,
          'messageId': id,
          'result': message['result'],
        }));
      }
    });

    _isolate = await Isolate.spawn(_entryPoint, _receivePort.sendPort);

    await completer.future;
  }

  /// Sends a [WorkerMessage] to the isolate for execution and returns the result.
  ///
  /// The message's [id] is set if not already provided. The result is returned as a [Future].
  Future<R> sendMessage<T, R>(
    WorkerMessage<T, R> message, {
    Duration? timeout,
  }) async {
    if (_isPaused) {
      throw StateError('Worker $_tag is paused and cannot accept messages.');
    }
    final completer = Completer<R>();
    final id = message.id ?? generateUniqueId();
    message.id = id;
    _completers[id] = completer;
    final messageMap = {'data': message, 'useLogger': useLogger};

    _eventController.add(IsolateWorkerEvent(IsolateWorkerEventType.coming, {
      'worker': _tag,
      'messageId': message.id,
      'message': message,
    }));
    _sendPort.send(messageMap);

    if (timeout != null) {
      completer.future.timeout(timeout).catchError((_) {
        _completers.remove(id);
      });
      return completer.future.timeout(timeout);
    }

    return completer.future;
  }

  /// Entry point for the spawned isolate. Listens for messages and executes tasks.
  static void _entryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((dynamic message) async {
      if (message is Map<String, dynamic>) {
        final data = message['data'];
        final id = data.id;
        final useLogger = message['useLogger'] == true;
        if (data is WorkerMessage) {
          final stopwatch = Stopwatch()..start();
          if (useLogger) {
            Logger.task(id, 'Task started');
          }
          final result = await data.execute();

          stopwatch.stop();

          if (useLogger) {
            Logger.taskComplete(id, stopwatch.elapsedMilliseconds);
          }
          sendPort.send({'messageId': id, 'result': result});
        } else {
          if (useLogger) {
            Logger.error('message is not a WorkerMessage');
          }
          throw Exception('message is not a WorkerMessage');
        }
      }
    });
  }

  /// Terminates the isolate and closes all associated resources.
  void kill() {
    if (useLogger) {
      Logger.warning('[$_tag] Killing isolate');
    }
    _isolate.kill();
    _receivePort.close();
    _eventController.close();

    // Dọn dẹp các completer còn lại
    for (final c in _completers.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('Isolate killed before completing task'));
      }
    }
    _completers.clear();
  }

  /// Pauses the event subscription for this worker.
  void pause() {
    _subscription?.pause();
    _isPaused = true;
  }

  /// Resumes the event subscription for this worker.
  void resume() {
    _subscription?.resume();
    _isPaused = false;
  }
}

class IsolateWorkerPool {
  final bool useLogger;
  final List<IsolateWorker> _workers;
  int _next = 0;
  final StreamController<IsolateWorkerPoolEvent> _eventController = StreamController.broadcast();
  Stream<IsolateWorkerPoolEvent> get events => _eventController.stream;

  IsolateWorkerPool({int numIsolates = 1, this.useLogger = false})
      : _workers = List.generate(
          (numIsolates < 1 ? 1 : numIsolates),
          (i) => IsolateWorker(tag: 'worker_${i + 1}', useLogger: useLogger),
        );

  /// Starts all workers in the pool.
  Future<void> start() async {
    for (final worker in _workers) {
      await worker.start();
    }
  }

  /// Sends a [WorkerMessage] to the worker with the given [tag].
  ///
  /// Throws if no worker with the tag exists or if the worker is paused.
  Future<R> sendMessageToTag<T, R>(String tag, WorkerMessage<T, R> message) {
    final worker = _workers.firstWhere(
      (w) => w._tag == tag,
      orElse: () => throw ArgumentError('No worker with tag $tag'),
    );
    if (worker._isPaused) {
      throw StateError('Worker $tag is paused and cannot accept messages.');
    }
    return worker.sendMessage<T, R>(message);
  }

  /// Sends a [WorkerMessage] to the next available worker in round-robin order.
  Future<R> sendMessage<T, R>(WorkerMessage<T, R> message) {
    if (_workers.isEmpty) {
      throw StateError('No workers available in the pool.');
    }
    // Tìm worker không pause
    int checked = 0;
    while (checked < _workers.length) {
      final worker = _workers[_next];
      _next = (_next + 1) % _workers.length;
      if (!worker._isPaused) {
        return worker.sendMessage<T, R>(message);
      }
      checked++;
    }
    throw StateError('No available (unpaused) workers in the pool.');
  }

  /// Terminates the worker with the given [tag].
  ///
  /// Throws if no worker with the tag exists.
  void killByTag(String tag) {
    final worker = _workers.firstWhere(
      (w) => w._tag == tag,
      orElse: () => throw ArgumentError('No worker with tag $tag'),
    );
    worker.kill();
    _workers.remove(worker);
    if (_workers.isEmpty) {
      _next = 0;
    } else if (_next >= _workers.length) {
      _next = 0;
    }
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.remove, tag));
  }

  /// Terminates all workers in the pool.
  void killAll() {
    for (final worker in _workers) {
      worker.kill();
    }
    _workers.clear();
    _next = 0;
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.remove, 'all'));
  }

  /// Terminates all workers with the given [tags].
  ///
  /// Throws if any tag does not exist.
  void killByTags(List<String> tags) {
    for (final tag in tags) {
      final worker = _workers.firstWhere(
        (w) => w._tag == tag,
        orElse: () => throw ArgumentError('No worker with tag $tag'),
      );
      worker.kill();
      _workers.remove(worker);
      _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.remove, tag));
    }
    if (_workers.isEmpty) {
      _next = 0;
    } else if (_next >= _workers.length) {
      _next = 0;
    }
  }

  /// Adds a new worker to the pool and starts it.
  ///
  /// Optionally specify a [tag] for the new worker.
  Future<void> add({String? tag}) async {
    tag ??= 'worker_${_workers.length + 1}';
    final worker = IsolateWorker(tag: tag, useLogger: useLogger);
    await worker.start();
    _workers.add(worker);
    if (_workers.length == 1) {
      _next = 0;
    }
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.add, worker._tag));
  }

  /// Returns a list of all worker tags in the pool.
  List<String> getWorkerTags() {
    return _workers.map((w) => w._tag).toList();
  }

  /// Returns a stream of all worker events in the pool.
  Stream<IsolateWorkerEvent> listenWorkerEvents() {
    return StreamGroup.merge(_workers.map((w) => w.events));
  }

  /// Returns a stream of events for the worker with the given [tag].
  ///
  /// Throws if no worker with the tag exists.
  Stream<IsolateWorkerEvent> listenWorkerEventsByTag(String tag) {
    return _workers.firstWhere((w) => w._tag == tag).events;
  }

  /// Pauses the worker with the given [tag].
  ///
  /// Throws if no worker with the tag exists.
  void pauseWorker(String tag) {
    final worker = _workers.firstWhere(
      (w) => w._tag == tag,
      orElse: () => throw ArgumentError('No worker with tag $tag'),
    );
    worker.pause();
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.pause, tag));
  }

  /// Resumes the worker with the given [tag].
  ///
  /// Throws if no worker with the tag exists.
  void resumeWorker(String tag) {
    final worker = _workers.firstWhere(
      (w) => w._tag == tag,
      orElse: () => throw ArgumentError('No worker with tag $tag'),
    );
    worker.resume();
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.resume, tag));
  }

  /// Pauses all workers in the pool.
  void pauseAll() {
    for (final worker in _workers) {
      worker.pause();
    }
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.pause, 'all'));
  }

  /// Resumes all workers in the pool.
  void resumeAll() {
    for (final worker in _workers) {
      worker.resume();
    }
    _eventController.add(IsolateWorkerPoolEvent(IsolateWorkerPoolEventType.resume, 'all'));
  }
}
