/// 多刷阅读统计：一本书的某一轮阅读记录
///
/// round 1 = 首刷，round 2 = 二刷，依此类推。
/// status: 'reading' = 本轮进行中；'finished' = 本轮已读完（快照已落库）。
class ReadingRound {
  int? id;
  int bookId;
  int roundNumber;
  String status;
  String? startTime;
  String? endTime;
  double startPercentage;
  double endPercentage;

  /// 完成本轮时的阅读位置（用于撤销时精确恢复；可为空）
  String? endPosition;
  int totalReadingTime;
  DateTime createTime;
  DateTime updateTime;

  ReadingRound({
    this.id,
    required this.bookId,
    required this.roundNumber,
    required this.status,
    this.startTime,
    this.endTime,
    required this.startPercentage,
    required this.endPercentage,
    this.endPosition,
    required this.totalReadingTime,
    required this.createTime,
    required this.updateTime,
  });

  bool get isFinished => status == 'finished';

  bool get isCancelled => status == statusCancelled;

  static const String statusReading = 'reading';
  static const String statusFinished = 'finished';

  /// 撤销后保留的行（软取消）：不再参与「当前轮/历史轮」展示，
  /// 但保留行本身，使同步端可以安全地再次复用同一轮次号。
  static const String statusCancelled = 'cancelled';

  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'round_number': roundNumber,
      'status': status,
      'start_time': startTime,
      'end_time': endTime,
      'start_percentage': startPercentage,
      'end_percentage': endPercentage,
      'end_position': endPosition,
      'total_reading_time': totalReadingTime,
      'create_time': createTime.toIso8601String(),
      'update_time': updateTime.toIso8601String(),
    };
  }

  factory ReadingRound.fromDb(Map<String, dynamic> map) {
    return ReadingRound(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      roundNumber: map['round_number'] as int? ?? 1,
      status: map['status'] as String? ?? statusReading,
      startTime: map['start_time'] as String?,
      endTime: map['end_time'] as String?,
      startPercentage: (map['start_percentage'] as num?)?.toDouble() ?? 0.0,
      endPercentage: (map['end_percentage'] as num?)?.toDouble() ?? 0.0,
      endPosition: map['end_position'] as String?,
      totalReadingTime: map['total_reading_time'] as int? ?? 0,
      createTime: DateTime.parse(map['create_time'] as String),
      updateTime: DateTime.parse(map['update_time'] as String),
    );
  }

  ReadingRound copyWith({
    int? id,
    int? bookId,
    int? roundNumber,
    String? status,
    String? startTime,
    String? endTime,
    double? startPercentage,
    double? endPercentage,
    String? endPosition,
    int? totalReadingTime,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    return ReadingRound(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      roundNumber: roundNumber ?? this.roundNumber,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startPercentage: startPercentage ?? this.startPercentage,
      endPercentage: endPercentage ?? this.endPercentage,
      endPosition: endPosition ?? this.endPosition,
      totalReadingTime: totalReadingTime ?? this.totalReadingTime,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
    );
  }
}
