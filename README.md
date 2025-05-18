<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# Flutter Isolate Worker 🚀

## 🎬 Demo GIF

![Demo](video.gif)

A Dart/Flutter package for running heavy or parallelizable tasks in the background using Dart Isolates, with a simple message-based API and worker pool management.

---

## 📚 Table of Contents

- [Flutter Isolate Worker 🚀](#flutter-isolate-worker-)
  - [🎬 Demo GIF](#-demo-gif)
  - [📚 Table of Contents](#-table-of-contents)
  - [✨ Introduction](#-introduction)
  - [🏗️ Architecture Overview](#️-architecture-overview)
  - [🧩 Main Components](#-main-components)
    - [📦 WorkerMessage](#-workermessage)
    - [👷 IsolateWorker](#-isolateworker)
    - [👷‍♂️👷‍♀️ IsolateWorkerPool](#️️-isolateworkerpool)
    - [🔔 Events](#-events)
  - [🚦 Basic Usage](#-basic-usage)
    - [1️⃣ Define a Task (WorkerMessage)](#1️⃣-define-a-task-workermessage)
    - [2️⃣ Create and Use IsolateWorkerPool](#2️⃣-create-and-use-isolateworkerpool)
    - [3️⃣ Send Task and Get Result](#3️⃣-send-task-and-get-result)
    - [4️⃣ Manage workers: pause, resume, kill, add](#4️⃣-manage-workers-pause-resume-kill-add)
    - [5️⃣ Listen to events](#5️⃣-listen-to-events)
  - [📝 Full Example](#-full-example)
  - [🛡️ Resource \& Memory Management Notes](#️-resource--memory-management-notes)
  - [🔗 References](#-references)
  - [License](#license)
  - [More Info](#more-info)

---

## ✨ Introduction

`flutter_isolate_worker` is a Dart/Flutter package for running heavy or parallelizable tasks in the background using Dart Isolates, with a simple message-based API and convenient worker pool management.

---

## 🏗️ Architecture Overview

- **WorkerMessage**: Defines a task that can be sent to an isolate for execution.
- **IsolateWorker**: Manages a single isolate, receives and executes WorkerMessages.
- **IsolateWorkerPool**: Manages multiple IsolateWorkers, supports round-robin or tag-based task assignment, and provides methods to add, pause, resume, or kill workers.
- **Event & Logging**: Supports event listening and logging for monitoring worker/pool activity.

---

## 🧩 Main Components

### 📦 WorkerMessage

- **abstract class WorkerMessage<T, R>**
  - Represents a unit of work to be sent to an isolate.
  - Properties:
    - `id`: String? (auto-generated if not provided)
    - `input`: T (input data)
  - Method:
    - `FutureOr<R> execute()`: Override to perform the task and return the result.

### 👷 IsolateWorker

- Manages a single isolate.
- Main methods:
  - `Future<void> start()`: Start the isolate.
  - `Future<R> sendMessage<T, R>(WorkerMessage<T, R> message, {Duration? timeout})`: Send a task and get the result.
  - `void kill()`: Kill the isolate.
  - `void pause()`, `void resume()`: Pause/resume receiving tasks.
  - `Stream<IsolateWorkerEvent> get events`: Listen to worker events.

### 👷‍♂️👷‍♀️ IsolateWorkerPool

- Manages multiple workers.
- Main methods:
  - `Future<void> start()`: Start all workers in the pool.
  - `Future<R> sendMessage<T, R>(WorkerMessage<T, R> message)`: Send a task to the next available worker (round-robin).
  - `Future<R> sendMessageToTag<T, R>(String tag, WorkerMessage<T, R> message)`: Send a task to a worker by tag.
  - `void add({String? tag})`: Add a new worker.
  - `void killByTag(String tag)`, `void killAll()`, `void killByTags(List<String> tags)`: Kill workers.
  - `void pauseWorker(String tag)`, `void resumeWorker(String tag)`, `void pauseAll()`, `void resumeAll()`: Pause/resume workers.
  - `List<String> getWorkerTags()`: Get list of worker tags.
  - `Stream<IsolateWorkerEvent> listenWorkerEvents()`: Listen to all worker events.
  - `Stream<IsolateWorkerEvent> listenWorkerEventsByTag(String tag)`: Listen to events of a specific worker.
  - `Stream<IsolateWorkerPoolEvent> get events`: Listen to pool events (add, remove, pause, resume workers).

### 🔔 Events

- **IsolateWorkerEvent**: Indicates when a worker receives or completes a task.
- **IsolateWorkerPoolEvent**: Indicates when the pool adds/removes/pauses/resumes a worker.

---

## 🚦 Basic Usage

### 1️⃣ Define a Task (WorkerMessage)

You need to create a class that extends WorkerMessage and override the execute method:

```dart
import 'package:flutter_isolate_worker/flutter_isolate_worker.dart';

class FactorialMessage extends WorkerMessage<int, int> {
  FactorialMessage(int input) : super(null, input);

  @override
  Future<int> execute() async {
    int result = 1;
    for (int i = 1; i <= input; i++) result *= i;
    return result;
  }
}
```

### 2️⃣ Create and Use IsolateWorkerPool

```dart
final pool = IsolateWorkerPool(numIsolates: 2);
await pool.start();
```

### 3️⃣ Send Task and Get Result

```dart
final result = await pool.sendMessage(FactorialMessage(5));
print('Result: $result'); // 120
```

Or send to a specific worker:

```dart
final result = await pool.sendMessageToTag('worker_1', FactorialMessage(10));
```

### 4️⃣ Manage workers: pause, resume, kill, add

```dart
pool.pauseWorker('worker_1');
pool.resumeWorker('worker_1');
pool.killByTag('worker_1');
await pool.add(); // Add a new worker
pool.killAll(); // Kill all workers
```

### 5️⃣ Listen to events

```dart
pool.listenWorkerEvents().listen((event) {
  print('Worker event: ${event.type} - ${event.message}');
});

pool.events.listen((event) {
  print('Pool event: ${event.type} - ${event.tag}');
});
```

---

## 📝 Full Example

```dart
import 'package:flutter_isolate_worker/flutter_isolate_worker.dart';

class SumMessage extends WorkerMessage<List<int>, int> {
  SumMessage(List<int> input) : super(null, input);

  @override
  Future<int> execute() async {
    return input.fold(0, (a, b) => a + b);
  }
}

void main() async {
  final pool = IsolateWorkerPool(numIsolates: 2);
  await pool.start();

  final result = await pool.sendMessage(SumMessage([1, 2, 3, 4, 5]));
  print('Sum: $result'); // 15

  pool.listenWorkerEvents().listen((event) {
    print('Worker event: ${event.type} - ${event.message}');
  });

  await pool.add(tag: 'custom_worker');
  final result2 = await pool.sendMessageToTag('custom_worker', SumMessage([10, 20]));
  print('Sum2: $result2'); // 30

  pool.killAll();
}
```

---

## 🛡️ Resource & Memory Management Notes

- **Always kill workers when not needed**: Call `killByTag`, `killAll`, or `killByTags` to free isolates.
- **Do not create too many isolates**: The number of isolates should match your CPU cores.
- **Clean up completers**: When an isolate is killed, any pending completers are completed with error to avoid leaks.
- **Do not send tasks to paused workers**: Sending a task to a paused worker will throw a StateError.

---

## 🔗 References

- [Dart Isolates](https://dart.dev/guides/libraries/concurrency)
- [Flutter documentation](https://docs.flutter.dev/)
- [Source code on pub.dev](https://pub.dev/packages/flutter_isolate_worker)

---

If you need a Flutter UI example or more complex tasks (e.g. Fibonacci, large array sorting, API fetching), see the `example/` directory in the package.

## License

MIT

## More Info

- [Dart Isolates](https://dart.dev/guides/libraries/concurrency)
- [Flutter documentation](https://docs.flutter.dev/)
