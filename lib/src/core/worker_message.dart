import 'dart:async';

/// Defines the base class for messages sent to isolates for execution.
///
/// This file provides the [WorkerMessage] abstract class, which represents a unit of work
/// that can be sent to an [IsolateWorker] for execution in a separate isolate. Subclass this
/// to define custom tasks with input and output types.

/// Represents a unit of work to be executed in an isolate.
///
/// Extend this class to define the input ([T]) and result ([R]) types for your task.
/// Implement the [execute] method to perform the computation.
abstract class WorkerMessage<T, R> {
  String? id;
  final T input;

  WorkerMessage(this.id, this.input);

  /// Method to execute the task, return the result of type [R].
  FutureOr<R> execute();
}
