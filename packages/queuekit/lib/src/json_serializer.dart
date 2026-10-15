/// Rebuilds a [T] from the map produced by the matching [ToJson].
typedef FromJson<T> = T Function(Map<String, dynamic> json);

/// Converts a [T] to a JSON-encodable map.
typedef ToJson<T> = Map<String, dynamic> Function(T data);

/// A pair of functions that convert a [T] to and from JSON.
class JsonSerializer<T> {
  JsonSerializer({required this.fromJson, required this.toJson});

  final FromJson<T> fromJson;
  final ToJson<T> toJson;
}
