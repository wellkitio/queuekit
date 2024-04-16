import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:queuekit/queuekit.dart';
import 'package:shared_preferences/shared_preferences.dart';

final startListenable = QueueStartListenable();

late final HydratedQueue queue;

final exampleEventSerializer = JsonSerializer(
  fromJson: (json) {
    return ExampleEvent()
      ..retryConfig = linearRetryConfigSerializer.fromJson(
        json['retryConfig'] as Map<String, dynamic>,
      );
  },
  toJson: (event) {
    return {
      'retryConfig': linearRetryConfigSerializer.toJson(event.retryConfig!),
    };
  },
);

class ExampleEvent extends HydratedEvent<String, LinearRetryConfig> {
  @override
  String get type => 'ExampleEvent';

  @override
  LinearRetryConfig? retryConfig =
      LinearRetryConfig(maxRetries: 10, delay: const Duration(seconds: 1));

  @override
  Future<String> run() {
    return Future.delayed(const Duration(seconds: 1), () => 'Hello World!');
  }

  @override
  JsonSerializer<HydratedEvent<String, LinearRetryConfig>> serializer =
      exampleEventSerializer;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  queue = HydratedQueue(
    startListenable,
    saveCurrentQueue: (json) async {
      await prefs.setString('currentQueue', jsonEncode(json));
    },
    hydrateCurrentQueue: () {
      final json = prefs.getString('currentQueue');
      if (json == null) {
        return [];
      }

      final data = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      return [
        for (final e in data)
          if (e['type'] == 'ExampleEvent')
            ExampleEvent()
              ..retryConfig =
                  linearRetryConfigSerializer.fromJson(e['retryConfig']),
      ];
    },
    saveRetryQueue: (data) async {
      await prefs.setString('retryQueue', jsonEncode(data));
    },
    hydrateRetryQueue: () {
      final json = prefs.getString('retryQueue');
      if (json == null) {
        return {};
      }
      final data = (jsonDecode(json) as List).cast<Map<String, dynamic>>();;
      return {
        for (final value in data)
          if (value['event']['type'] == 'ExampleEvent')
            value['id']: (
              event: exampleEventSerializer.fromJson(value['event']),
              nextExecutionTime:
                  DateTime.parse(value['nextExecutionTime'] as String),
            ),
      };
    },
  );

  await queue.hydrate();
  startListenable.start();

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final StreamSubscription subscription;
  final data = <String>[];

  @override
  void initState() {
    super.initState();
    subscription =
        queue.listenWhere<ExampleEvent, String, LinearRetryConfig>((params) {
      setState(() {
        data.add(params.result);
      });
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data.isEmpty)
                  const Text('Press the button to add an event'),
                for (final item in data) Text(item),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              queue.add(ExampleEvent());
            },
            child: const Icon(Icons.add),
          )),
    );
  }
}
