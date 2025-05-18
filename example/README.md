# isolate_worker_example

A Flutter example app demonstrating the usage of the [`isolate_worker`](../README.md) package for running heavy background tasks in parallel using Dart Isolates, and comparing it with running on the main thread.

## Features

- Create and manage a pool of isolates (workers)
- Send heavy tasks (sort a large random array) to workers and receive results asynchronously
- Add, remove, pause, and resume workers dynamically (when using isolate)
- View real-time event logs from the worker pool
- **Compare:** Run the same task on the main thread to see UI lag/blocking

## Getting Started

1. **Install dependencies:**

   ```sh
   flutter pub get
   ```

2. **Run the example app:**

   ```sh
   flutter run -d <device> --target=example/lib/main.dart
   ```

   Or open the `example/` folder in your IDE and run `main.dart`.

## Usage Example

```dart
// Define a WorkerMessage for sorting a large array
class SortLargeArrayMessage extends WorkerMessage<int, List<int>> {
  SortLargeArrayMessage({required int size}) : super(null, size);
  @override
  Future<List<int>> execute() async {
    final rand = Random(42);
    final arr = List.generate(size, (_) => rand.nextInt(100000000));
    arr.sort();
    return arr;
  }
}

// Create a pool and send a task
final pool = IsolateWorkerPool(numIsolates: 2);
await pool.start();
final result = await pool.sendMessage(SortLargeArrayMessage(size: 2000000));
print('First: ${result.first}, Last: ${result.last}');
```

## UI Demo

- Enter the array size (e.g. 2000000) and choose **Isolate** or **Main Thread**.
- Press **Send** to sort a large random array in the background or on the main thread.
- When using **Main Thread** with a large array, the UI will freeze until the task completes.
- When using **Isolate**, the UI remains responsive.
- Add, pause, resume, or remove workers (when using isolate).
- View logs of all events and results in real time.

## Learn More

- [isolate_worker package documentation](../README.md)
- [Dart Isolates](https://dart.dev/guides/libraries/concurrency)
- [Flutter documentation](https://docs.flutter.dev/)
