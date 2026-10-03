DateTime outsideQuietHours(DateTime at, int start, int end) {
  if (start == end) return at;
  final minute = at.hour*60 + at.minute;
  final inside = start < end ? minute >= start && minute < end : minute >= start || minute < end;
  if (!inside) return at;
  final nextDay = start > end && minute >= start ? 1 : 0;
  return DateTime(at.year, at.month, at.day+nextDay, end~/60, end%60);
}
