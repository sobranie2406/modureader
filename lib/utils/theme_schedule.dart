/// Start is inclusive, end exclusive. Equal times disable the night interval.
bool isScheduledNight(DateTime now, int start, int end) {
  final minute = now.hour * 60 + now.minute;
  if (start == end) return false;
  return start < end
      ? minute >= start && minute < end
      : minute >= start || minute < end;
}
