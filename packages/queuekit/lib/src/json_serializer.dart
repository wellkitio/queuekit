typedef FromJson<T> = T Function(Map<String, dynamic> json);
typedef ToJson<T> = Map<String, dynamic> Function(T data);

class JsonSerializer<T> {
  JsonSerializer({
    required this.fromJson,
    required this.toJson,
  });

  final FromJson<T> fromJson;
  final ToJson<T> toJson;
}
