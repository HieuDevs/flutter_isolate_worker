import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_worker/isolate_worker.dart';

class AddMessage extends WorkerMessage<int, int> {
  AddMessage(String? id, int input) : super(id, input);

  @override
  Future<int> execute() async => input + 1;
}

void main() {
  group('IsolateWorker', () {
    late IsolateWorker worker;

    setUp(() async {
      worker = IsolateWorker(useLogger: false);
      await worker.start();
    });

    tearDown(() {
      worker.kill();
    });

    test('sendMessage returns correct result', () async {
      final result = await worker.sendMessage(AddMessage('1', 2));
      expect(result, 3);
    });

    test('events stream emits coming and done', () async {
      final events = <IsolateWorkerEventType>[];
      final sub = worker.events.listen((event) {
        events.add(event.type);
      });
      await worker.sendMessage(AddMessage('2', 5));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(events, contains(IsolateWorkerEventType.coming));
      expect(events, contains(IsolateWorkerEventType.done));
      await sub.cancel();
    });
  });

  group('IsolateWorkerPool', () {
    late IsolateWorkerPool pool;

    setUp(() async {
      pool = IsolateWorkerPool(numIsolates: 2, useLogger: false);
      await pool.start();
    });

    tearDown(() {
      pool.killAll();
    });

    test('sendMessage works', () async {
      final result = await pool.sendMessage(AddMessage('10', 10));
      expect(result, 11);
    });

    test('add worker and getWorkerTags', () async {
      await pool.add(tag: 'custom');
      final tags = pool.getWorkerTags();
      expect(tags, contains('custom'));
    });

    test('sendMessageToTag works', () async {
      await pool.add(tag: 'special');
      final result = await pool.sendMessageToTag('special', AddMessage('100', 100));
      expect(result, 101);
    });

    test('killByTag, killByTags, killAll', () async {
      await pool.add(tag: 'A');
      await pool.add(tag: 'B');
      pool.killByTag('A');
      pool.killByTags(['B']);
      // After killing, tags should still be present, but workers are dead.
      final tags = pool.getWorkerTags();
      expect(tags, containsAll(['A', 'B']));
      pool.killAll();
    });

    test('pool events stream emits add/remove', () async {
      final events = <String>[];
      final sub = pool.events.listen((event) {
        events.add('${event.type}:${event.tag}');
      });
      await pool.add(tag: 'E1');
      pool.killByTag('E1');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(events.any((e) => e.contains('add')), isTrue);
      expect(events.any((e) => e.contains('remove')), isTrue);
      await sub.cancel();
    });

    test('listenWorkerEvents emits coming and done', () async {
      final events = <IsolateWorkerEventType>[];
      final sub = pool.listenWorkerEvents().listen((event) {
        events.add(event.type);
      });
      await pool.sendMessage(AddMessage('20', 20));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(events, contains(IsolateWorkerEventType.coming));
      expect(events, contains(IsolateWorkerEventType.done));
      await sub.cancel();
    });

    test('listenWorkerEventsByTag emits for correct worker', () async {
      await pool.add(tag: 'listen_tag');
      final tagEvents = <IsolateWorkerEventType>[];
      final tagSub = pool.listenWorkerEventsByTag('listen_tag').listen((event) {
        tagEvents.add(event.type);
      });
      await pool.sendMessageToTag('listen_tag', AddMessage('50', 50));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(tagEvents, contains(IsolateWorkerEventType.coming));
      expect(tagEvents, contains(IsolateWorkerEventType.done));
      await tagSub.cancel();
    });
  });
}
