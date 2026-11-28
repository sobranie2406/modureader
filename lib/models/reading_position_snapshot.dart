import 'narration_position.dart';

class ReadingPositionSnapshot {
  const ReadingPositionSnapshot(this.position, this.percentage, this.revision,
      {this.deleted = false, this.narration, this.updatedAtMs});
  final int? updatedAtMs;
  final String position;
  final double percentage;
  final String revision;
  final bool deleted;
  final NarrationPosition? narration;

  /// A resumable speech anchor wins over a separately browsed page. Stopped
  /// speech is only a sync tombstone; ordinary reading keeps its page anchor.
  String get resumePosition =>
      narration?.canResume == true ? narration!.cfi : position;
}
