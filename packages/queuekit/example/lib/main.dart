import 'dart:async';

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

class ExampleEvent extends HydratedEvent<String> {
  @override
  String get id => 'id';

  @override
  String get type => 'ExampleEvent';

  @override
  LinearRetryConfig? retryConfig = LinearRetryConfig(maxRetries: 10, delay: const Duration(seconds: 1));

  @override
  Future<String> run() {
    return Future.delayed(const Duration(seconds: 1), () => 'Hello World!');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  queue = HydratedQueue(
    startListenable,
    eventSerializers: {
      'ExampleEvent': (
        fromJson: exampleEventSerializer.fromJson,
        toJson: (event) => exampleEventSerializer.toJson(event as ExampleEvent),
      ),
    },
    saveCurrentQueue: (data) async {
      await prefs.setString('currentQueue', data);
    },
    hydrateCurrentQueue: () {
      return prefs.getString('currentQueue');
    },
    saveRetryQueue: (data) async {
      await prefs.setString('retryQueue', data);
    },
    hydrateRetryQueue: () {
      return prefs.getString('retryQueue');
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
    subscription = queue.listenWhere<ExampleEvent, String>((params) {
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
                if (data.isEmpty) const Text('Press the button to add an event'),
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
