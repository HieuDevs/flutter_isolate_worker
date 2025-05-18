import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:isolate_worker/isolate_worker.dart';

void main() {
  runApp(const MyApp());
}

// WorkerMessage: Sắp xếp một mảng lớn các số ngẫu nhiên
class SortLargeArrayMessage extends WorkerMessage<int, List<int>> {
  SortLargeArrayMessage({required int size}) : super(null, size);

  @override
  Future<List<int>> execute() async {
    return _sortLargeArray(input);
  }

  List<int> _sortLargeArray(int n) {
    final rand = Random(42);
    final arr = List.generate(n, (_) => rand.nextInt(100000000));
    arr.sort();
    return arr;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isolate Worker Visual Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const WorkerVisualDemoPage(),
    );
  }
}

class WorkerVisualDemoPage extends StatefulWidget {
  const WorkerVisualDemoPage({super.key});

  @override
  State<WorkerVisualDemoPage> createState() => _WorkerVisualDemoPageState();
}

class _WorkerVisualDemoPageState extends State<WorkerVisualDemoPage> {
  late IsolateWorkerPool pool;
  int numIsolates = 3;
  final TextEditingController _inputController = TextEditingController(text: '5');
  final List<String> _logs = [];
  String? _result;
  bool _started = false;
  List<String> _workerTags = [];
  Map<String, String> _workerStatus = {}; // tag -> status emoji
  StreamSubscription? _eventSub;
  final ScrollController _workerScrollController = ScrollController();
  bool _useIsolate = true;
  int? _lastDurationMs;

  @override
  void initState() {
    super.initState();
    _startPool();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_started) pool.killAll();
    _workerScrollController.dispose();
    super.dispose();
  }

  Future<void> _startPool() async {
    pool = IsolateWorkerPool(numIsolates: numIsolates, useLogger: false);
    await pool.start();
    _workerTags = pool.getWorkerTags();
    _workerStatus = {for (var tag in _workerTags) tag: '🟢'};
    _eventSub = pool.listenWorkerEvents().listen((event) {
      final tag = event.message['worker']?.toString() ?? '';
      setState(() {
        if (event.type == IsolateWorkerEventType.coming) {
          _workerStatus[tag] = '🟡'; // Đang xử lý
          _logs.insert(0, '📦 Task sent to $tag');
        } else if (event.type == IsolateWorkerEventType.done) {
          _workerStatus[tag] = '🟢'; // Xong, sẵn sàng
          _logs.insert(0, '✅ $tag finished');
        }
      });
    });
    setState(() {
      _started = true;
    });
  }

  Future<void> _sendTask() async {
    final size = int.tryParse(_inputController.text) ?? 1000000;
    setState(() {
      _result = '';
      _lastDurationMs = null;
    });
    final sw = Stopwatch()..start();
    try {
      List<int> sorted = [];
      if (_useIsolate) {
        sorted = await pool.sendMessage(SortLargeArrayMessage(size: size));
      } else {
        sorted = await SortLargeArrayMessage(size: size).execute();
      }
      sw.stop();
      setState(() {
        _result = '✅ Sorted ${sorted.length} numbers\nFirst: ${sorted.first}, Last: ${sorted.last}';
        _lastDurationMs = sw.elapsedMilliseconds;
      });
    } catch (e) {
      sw.stop();
      setState(() {
        _result = '⚠️ Error: $e';
        _lastDurationMs = sw.elapsedMilliseconds;
      });
    }
  }

  Future<void> _addWorker() async {
    await pool.add();
    setState(() {
      _workerTags = pool.getWorkerTags();
      _workerStatus[_workerTags.last] = '🟢';
      _logs.insert(0, '➕ Added worker ${_workerTags.last}');
    });
    // Listen to events
    _eventSub?.cancel();
    _eventSub = pool.listenWorkerEvents().listen((event) {
      final tag = event.message['worker']?.toString() ?? '';
      setState(() {
        if (event.type == IsolateWorkerEventType.coming) {
          _workerStatus[tag] = '🟡'; // Đang xử lý
          _logs.insert(0, '📦 Task sent to $tag');
        } else if (event.type == IsolateWorkerEventType.done) {
          _workerStatus[tag] = '🟢'; // Xong, sẵn sàng
          _logs.insert(0, '✅ $tag finished');
        }
      });
    });
  }

  void _killWorker(String tag) {
    pool.killByTag(tag);
    setState(() {
      _workerStatus[tag] = '❌';
      _logs.insert(0, '❌ Killed worker $tag');
      _workerTags = pool.getWorkerTags();
    });
  }

  void _pauseWorker(String tag) {
    pool.pauseWorker(tag);
    setState(() {
      _workerStatus[tag] = '⏸️';
      _logs.insert(0, '⏸️ Paused $tag');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Worker $tag paused'), duration: const Duration(milliseconds: 800)),
    );
  }

  void _resumeWorker(String tag) {
    pool.resumeWorker(tag);
    setState(() {
      _workerStatus[tag] = '🟢';
      _logs.insert(0, '▶️ Resumed $tag');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Worker $tag resumed'), duration: const Duration(milliseconds: 800)),
    );
  }

  void _killAll() {
    pool.killAll();
    setState(() {
      for (var tag in _workerTags) {
        _workerStatus[tag] = '❌';
      }
      _logs.insert(0, '❌ Killed all workers');
      _workerTags.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Isolate Worker Visual Demo')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: _useIsolate,
                          onChanged: (v) => setState(() {
                            _useIsolate = true;
                            _result = '';
                            _lastDurationMs = null;
                          }),
                        ),
                        const Text('Isolate'),
                        Radio<bool>(
                          value: false,
                          groupValue: _useIsolate,
                          onChanged: (v) => setState(() {
                            _useIsolate = false;
                            _result = '';
                            _lastDurationMs = null;
                          }),
                        ),
                        const Text('Main Thread'),
                      ],
                    ),
                  ),
                  if (_lastDurationMs != null)
                    Text('⏱ ${_lastDurationMs}ms', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            // Task input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Flexible(
                      child: TextField(
                        controller: _inputController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          labelText: 'Array Size',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Send'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(60, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
                      onPressed: _workerTags.isNotEmpty ? _sendTask : null,
                    ),
                  ],
                ),
              ),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Text(_result!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            // Worker actions
            if (_useIsolate)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Worker'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                      onPressed: _addWorker,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('Kill All'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                      onPressed: _killAll,
                    ),
                  ],
                ),
              ),
            // Worker list
            if (_useIsolate) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Workers:',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _workerTags.map(_buildWorkerBox).toList(),
                ),
              ),
            ],
            const Divider(height: 10),
            // Logs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  const Text('Logs:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear Logs',
                    onPressed: () {
                      setState(() {
                        _logs.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.grey[50],
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  itemCount: _logs.length,
                  itemBuilder: (context, idx) => Text(_logs[idx], style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkerBox(String tag) {
    Color bgColor;
    if (_workerStatus[tag] == '🟡') {
      bgColor = Colors.amber[200]!;
    } else if (_workerStatus[tag] == '⏸️') {
      bgColor = Colors.grey[300]!;
    } else if (_workerStatus[tag] == '❌') {
      bgColor = Colors.red[200]!;
    } else {
      bgColor = Colors.green[100]!;
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          if (_workerStatus[tag] != '❌')
            IconButton(
              icon: Icon(_workerStatus[tag] == '⏸️' ? Icons.play_arrow : Icons.pause, size: 13),
              tooltip: _workerStatus[tag] == '⏸️' ? 'Resume' : 'Pause',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                if (_workerStatus[tag] == '⏸️') {
                  _resumeWorker(tag);
                } else {
                  _pauseWorker(tag);
                }
              },
            ),
          if (_workerStatus[tag] != '❌')
            IconButton(
              icon: const Icon(Icons.close, size: 13),
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _killWorker(tag),
            ),
        ],
      ),
    );
  }
}
