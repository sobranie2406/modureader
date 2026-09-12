class ReadingPositionSnapshot {
  const ReadingPositionSnapshot(this.position, this.percentage, this.revision,
      {this.deleted = false});
  final String position;
  final double percentage;
  final String revision;
  final bool deleted;
}
