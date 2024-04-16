typedef FromJson<T> = T Function(Map<String, dynamic> json);

class JsonSerializer<T> {
  JsonSerializer({
    required this.fromJson,
    required this.toJson,
  });

  final FromJson<T> fromJson;
  final Map<String, dynamic> Function(T data) toJson;
}

