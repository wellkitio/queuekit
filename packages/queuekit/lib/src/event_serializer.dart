import 'package:queuekit/queuekit.dart';

/// Converts the events of one type, [T], to and from JSON for a [HydratedQueue].
///
/// [type] must be the [Event.type] of those events. Declare both from one constant on the event
/// class so they cannot drift apart:
///
/// ```dart
/// class UploadPhoto extends Event<String> {
///   static const typeName = 'UploadPhoto';
///
///   static final serializer = EventSerializer<UploadPhoto>(
///     type: typeName,
///     fromJson: UploadPhoto.fromJson,
///     toJson: (event) => event.toJson(),
///   );
///
///   @override
///   String get type => typeName;
/// }
/// ```
///
/// [toJson] must include everything needed to rebuild the event, including its id and retry
/// config; [fromJson] receives that map back.
final class EventSerializer<T extends Event<Object?>> {
  const EventSerializer({
    required this.type,
    required FromJson<T> fromJson,
    required ToJson<T> toJson,
  }) : _fromJson = fromJson,
       _toJson = toJson;

  /// The [Event.type] this serializer handles.
  final String type;

  final FromJson<T> _fromJson;
  final ToJson<T> _toJson;

  /// Whether [event] is a [T] and therefore can be serialized by this serializer.
  bool accepts(Event<Object?> event) => event is T;

  /// Rebuilds an event from the map produced by [toJson].
  T fromJson(Map<String, dynamic> json) => _fromJson(json);

  /// Converts [event] to JSON.
  ///
  /// Throws an [ArgumentError] if [event] is not a [T], which means it reports a [type] that is
  /// registered for another class.
  Map<String, dynamic> toJson(Event<Object?> event) {
    if (event is! T) {
      throw ArgumentError.value(
        event,
        'event',
        'reports type "${event.type}", which is registered for $T, but is a ${event.runtimeType}',
      );
    }
    return _toJson(event);
  }
}
