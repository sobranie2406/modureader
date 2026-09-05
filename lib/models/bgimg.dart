import 'package:anx_reader/enums/bgimg_alignment.dart';
import 'package:anx_reader/enums/bgimg_theme_mode.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bgimg.freezed.dart';
part 'bgimg.g.dart';

@freezed
abstract class BgimgModel with _$BgimgModel {
  const factory BgimgModel({
    required BgimgType type,
    required String path,
    String? nightPath,
    required BgimgAlignment alignment,
    BgimgThemeMode? selectedMode,
    @Default(0.0) double blur,
    @Default(1.0) double opacity,
  }) = _BgimgModel;

  factory BgimgModel.fromJson(Map<String, dynamic> json) =>
      _$BgimgModelFromJson(json);

  const BgimgModel._();

  String _imageUrl(String imagePath, String source) => Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: Server().port,
        pathSegments: ['bgimg', source, ...imagePath.split('/')],
      ).toString();

  String get url => switch (type) {
        BgimgType.none => 'none',
        BgimgType.assets => _imageUrl(path, 'assets'),
        BgimgType.localFile => _imageUrl(path, 'local'),
      };

  String? get nightUrl => switch (type) {
        BgimgType.none => null,
        BgimgType.assets =>
          nightPath != null ? _imageUrl(nightPath!, 'assets') : null,
        BgimgType.localFile =>
          nightPath != null ? _imageUrl(nightPath!, 'local') : null,
      };

  /// Get the effective URL based on user selection and auto-adjust settings
  String getEffectiveUrl({
    required bool isDarkMode,
    required bool autoAdjust,
  }) {
    if (autoAdjust) {
      // Auto mode: use system dark mode to determine
      return isDarkMode && nightUrl != null ? nightUrl! : url;
    } else {
      // Manual mode: use user's selected mode
      if (selectedMode == BgimgThemeMode.night && nightUrl != null) {
        return nightUrl!;
      }
      return url;
    }
  }
}
