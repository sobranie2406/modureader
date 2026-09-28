import 'package:anx_reader/utils/ai_reasoning_parser.dart';

const conciseAnswerGuidance = '''
直接回答用户的问题，不输出准备过程或工具调用旁白，例如“我先确认一下你当前的阅读上下文”。
不要把当前书名、章节和阅读位置作为例行开场白；仅在用户询问出处或解释确实需要时引用必要来源。
保留实际答案、必要的依据和错误说明，不用“你正在读……”重复界面上已有的信息。
''';

/// Hide routine reader context fetches, not failures, generated artifacts, or
/// actions that need user review/confirmation. Keep raw history intact.
List<ParsedReasoningEntry> visibleAnswerTimeline(
        List<ParsedReasoningEntry> timeline) =>
    timeline.where((entry) {
      final step = entry.toolStep;
      if (step == null ||
          !const {'current_reading_metadata', 'current_chapter_content'}
              .contains(step.name)) {
        return true;
      }
      return !const {'running', 'success'}.contains(step.status) ||
          (step.error?.trim().isNotEmpty ?? false);
    }).toList(growable: false);
