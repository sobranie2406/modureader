import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'reader_menu_group.dart';
import 'reader_settings_scroll_view.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/tts_page_source.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/service/tts/system_tts_support.dart';
import 'package:anx_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:anx_reader/widgets/reading_page/tts_value_control.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import 'dart:async';

class TtsWidget extends StatefulWidget {
  const TtsWidget(
      {super.key,
      required this.epubPlayerKey,
      this.extractedText,
      this.pageSource});

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  // OCR previews must never read from the underlying original-page WebView.
  final String? extractedText;
  final TtsPageSource? pageSource;

  @override
  State<TtsWidget> createState() => _TtsWidgetState();
}

class _TtsWidgetState extends State<TtsWidget> {
  double volume = Prefs().ttsVolume;
  double pitch = Prefs().ttsPitch;
  double rate = Prefs().ttsRate;
  double stopSeconds = 0;
  Timer? stopTimer;
  String? _startupError;
  late final TtsPageSource? _pageSource = widget.pageSource ??
      (widget.extractedText == null
          ? null
          : TtsPageSource(widget.extractedText!, chapter: ''));

  bool get _unsupportedSystem =>
      Prefs().ttsService == 'system' && !supportsSystemTts();

  String _unitLabel(BuildContext context, {required bool previous}) {
    final paragraph = _pageSource == null &&
        tts_svc.getTtsService(Prefs().ttsService).isOnline;
    return paragraph
        ? (previous
            ? ModuStrings.text(context, '上一段', 'Previous passage')
            : ModuStrings.text(context, '下一段', 'Next passage'))
        : (previous
            ? ModuStrings.text(context, '上一句', 'Previous sentence')
            : ModuStrings.text(context, '下一句', 'Next sentence'));
  }

  @override
  void initState() {
    super.initState();
    if (!_unsupportedSystem &&
        ((_pageSource != null &&
                !identical(TtsHandler().tts.pageSource, _pageSource)) ||
            TtsHandler().ttsStateNotifier.value == TtsStateEnum.stopped)) {
      unawaited(_startReading());
    }
  }

  Future<void> _startReading() async {
    final reader = widget.epubPlayerKey.currentState;
    if (reader == null) return;
    try {
      final source = _pageSource;
      if (source != null) {
        if (!source.valid) return;
        await audioHandler.stop();
        if (!mounted || !source.valid) return;
        await TtsHandler().init(
            source.currentText, source.nextTextContinuous, source.previousText,
            pageSource: source);
      } else {
        await TtsHandler().init(reader.initTts, reader.ttsNext, reader.ttsPrev);
      }
      if (!mounted ||
          source?.valid == false ||
          !reader.mounted ||
          widget.epubPlayerKey.currentState != reader) {
        return;
      }
      await audioHandler.play();
    } catch (error) {
      AnxLog.warning('TTS panel startup failed: ${error.runtimeType}');
      if (mounted) {
        setState(() => _startupError = ModuStrings.text(
            context,
            '朗读启动失败，请重新打开朗读面板重试。',
            'Could not start speech. Reopen the narration panel to retry.'));
      }
    }
  }

  @override
  void dispose() {
    if (widget.pageSource == null) _pageSource?.invalidate();
    super.dispose();
  }

  String _getTtsServiceLabel(BuildContext context) {
    final serviceId = Prefs().ttsService;
    if (serviceId == 'system') {
      return L10n.of(context).ttsTypeSystem;
    }
    return tts_svc.getTtsService(serviceId).getLabel(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupportedSystem) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(systemTtsUnsupportedMessage(
          chinese: Localizations.localeOf(context).languageCode == 'zh',
        )),
      );
    }
    return ValueListenableBuilder<TtsStateEnum>(
      valueListenable: TtsHandler().ttsStateNotifier,
      builder: (context, ttsState, child) {
        Widget volume() {
          return Row(
            children: [
              Text(L10n.of(context).ttsVolume),
              Expanded(
                child: Slider(
                  value: TtsHandler().volume,
                  onChanged: (newVolume) {
                    setState(() {
                      TtsHandler().volume = newVolume;
                    });
                  },
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: TtsHandler().volume.toStringAsFixed(1),
                ),
              ),
            ],
          );
        }

        Widget voiceControls() => TtsVoiceControls(
              pitch: pitch,
              rate: rate,
              onPitchChanged: (value) {
                setState(() => pitch = value);
                TtsHandler().pitch = value;
              },
              onRateChanged: (value) {
                setState(() => rate = value);
                TtsHandler().rate = value;
              },
            );

        Widget sliders() {
          return Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              children: [
                volume(),
                voiceControls(),
                Row(
                  children: [
                    Expanded(
                        child: (_pageSource != null ||
                                tts_svc
                                    .getTtsService(Prefs().ttsService)
                                    .isOnline)
                            ? SettingHelpTitle(
                                title: L10n.of(context).ttsType,
                                description: _pageSource != null
                                    ? ModuStrings.text(context, "朗读当前重排页。",
                                        "Read the current reflowed page aloud.")
                                    : ModuStrings.text(
                                        context,
                                        "按段落连贯朗读，可用前后按钮跳转。",
                                        "Read in passages. Use the previous and next buttons to navigate."))
                            : Text(L10n.of(context).ttsType)),
                    Flexible(
                        child: GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          sheetAnimationStyle: AppMotion.style,
                          context: context,
                          isScrollControlled: true,
                          builder: (context) {
                            return FractionallySizedBox(
                              heightFactor: Prefs()
                                      .readerPopupMaxHeightPercent
                                      .clamp(40, 70) /
                                  100,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: const ReaderMenuGroup(
                                    child: NarrateSettings()),
                              ),
                            );
                          },
                        ).then((_) {
                          // Refresh state if needed when sheet closes
                          setState(() {});
                        });
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                              child: Text(
                            _getTtsServiceLabel(context),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ],
            ),
          );
        }

        Widget buttons() {
          if (_pageSource?.valid == false) {
            return Text(ModuStrings.text(context, '本页已切换，请重新打开朗读。',
                'The page has changed. Reopen narration.'));
          }
          return Wrap(
            alignment: WrapAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: _pageSource != null
                    ? null
                    : () async {
                        await audioHandler.stop();
                        final text = await widget.epubPlayerKey.currentState!
                            .ttsPrevSection();
                        if (text.isNotEmpty) await audioHandler.play();
                      },
                icon: const Icon(EvaIcons.arrowhead_left),
              ),
              IconButton(
                tooltip: _unitLabel(context, previous: true),
                onPressed: () {
                  TtsHandler().playPrevious();
                },
                icon: const Icon(EvaIcons.chevron_left),
              ),
              IconButton(
                onPressed: () async {
                  ttsState == TtsStateEnum.playing
                      ? audioHandler.pause()
                      : audioHandler.play();
                },
                icon: ttsState == TtsStateEnum.playing
                    ? const Icon(EvaIcons.pause_circle_outline)
                    : const Icon(EvaIcons.play_circle_outline),
              ),
              IconButton(
                onPressed: () {
                  audioHandler.stop();
                },
                icon: const Icon(EvaIcons.stop_circle_outline),
              ),
              IconButton(
                tooltip: _unitLabel(context, previous: false),
                onPressed: () {
                  TtsHandler().playNext();
                },
                icon: const Icon(EvaIcons.chevron_right),
              ),
              IconButton(
                onPressed: _pageSource != null
                    ? null
                    : () async {
                        await audioHandler.stop();
                        final text = await widget.epubPlayerKey.currentState!
                            .ttsNextSection();
                        if (text.isNotEmpty) await audioHandler.play();
                      },
                icon: const Icon(EvaIcons.arrowhead_right),
              ),
            ],
          );
        }

        Widget stopTimerWidget() {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
            child: Row(
              children: [
                const Icon(EvaIcons.clock_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Slider(
                    value: stopSeconds / 60,
                    onChanged: (newValue) {
                      setState(() {
                        stopSeconds = newValue * 60;
                        stopTimer?.cancel();

                        if (stopSeconds > 0) {
                          stopTimer = Timer.periodic(
                            const Duration(seconds: 5),
                            (timer) {
                              if (_pageSource != null &&
                                  (!_pageSource.valid ||
                                      !identical(TtsHandler().tts.pageSource,
                                          _pageSource))) {
                                timer.cancel();
                                return;
                              }
                              if (stopSeconds > 5) {
                                stopSeconds -= 5;
                                if (mounted) {
                                  setState(() {});
                                }
                                return;
                              } else {
                                TtsHandler().stop();
                                stopSeconds = 0;
                                timer.cancel();
                                if (mounted) {
                                  setState(() {});
                                }
                              }
                            },
                          );
                        }
                      });
                    },
                    min: 0.0,
                    max: 60.0,
                    label: L10n.of(context)
                        .commonMinutesFull((stopSeconds / 60).round()),
                  ),
                ),
                Text(
                  L10n.of(context).ttsStopAfter((stopSeconds / 60).ceil()),
                ),
              ],
            ),
          );
        }

        return ReaderSettingsScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              widgetTitle(
                L10n.of(context).ttsNarrator,
                ReadingSettings.style,
              ),
              ReaderMenuGroup(
                  padding: const EdgeInsets.all(12), child: buttons()),
              if (_startupError case final String error)
                Text(error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (TtsHandler().tts.playbackError case final String error)
                Text(error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ReaderMenuGroup(
                  padding: const EdgeInsets.all(12), child: stopTimerWidget()),
              ReaderMenuGroup(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                  child: sliders()),
            ],
          ),
        );
      },
    );
  }
}
