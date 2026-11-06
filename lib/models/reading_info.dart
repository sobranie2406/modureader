import 'package:flutter/painting.dart';
import 'package:anx_reader/models/text_color.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_info.freezed.dart';
part 'reading_info.g.dart';

@freezed
abstract class ReadingInfoSectionModel with _$ReadingInfoSectionModel {
  const factory ReadingInfoSectionModel({
    @Default(ReadingInfoEnum.none) ReadingInfoEnum left,
    @Default(ReadingInfoEnum.none) ReadingInfoEnum center,
    @Default(ReadingInfoEnum.none) ReadingInfoEnum right,
    @Default(0) double verticalMargin,
    @Default(20) double leftMargin,
    @Default(20) double rightMargin,
    @Default(10) double fontSize,
    @Default('') String font,
    @Default('') String color,
    double? opacity,
  }) = _ReadingInfoSectionModel;

  factory ReadingInfoSectionModel.fromJson(Map<String, dynamic> json) =>
      _$ReadingInfoSectionModelFromJson(json);
}

@freezed
abstract class ReadingInfoModel with _$ReadingInfoModel {
  const factory ReadingInfoModel({
    @Default(
      ReadingInfoSectionModel(
        left: ReadingInfoEnum.chapterTitle,
      ),
    )
    ReadingInfoSectionModel header,
    @Default(
      ReadingInfoSectionModel(
        left: ReadingInfoEnum.batteryAndTime,
        center: ReadingInfoEnum.chapterProgress,
        right: ReadingInfoEnum.bookProgress,
      ),
    )
    ReadingInfoSectionModel footer,
  }) = _ReadingInfoModel;

  factory ReadingInfoModel.fromJson(Map<String, dynamic> json) =>
      _$ReadingInfoModelFromJson(json);
}

extension ReadingInfoAppearance on ReadingInfoSectionModel {
  Color textColor(Color body, {double defaultOpacity = 150 / 255}) {
    final base = color.isNotEmpty && validTextColor(color)
        ? Color(int.parse('FF${color.substring(1)}', radix: 16))
        : body;
    final alpha = opacity;
    return base.withValues(
        alpha: alpha != null && alpha.isFinite
            ? alpha.clamp(0.0, 1.0)
            : defaultOpacity);
  }
}
