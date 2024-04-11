import 'package:barrel_files_annotation/barrel_files_annotation.dart';

@includeInBarrelFile
abstract class Event {
  String get type;
}
