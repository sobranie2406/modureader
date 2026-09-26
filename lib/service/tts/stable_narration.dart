/// A soft synthesis instruction, not an audio normalizer or a voice identifier.
/// Keep it independent of sentence text so each request receives the same goal.
const stableNarrationInstruction = '连续听书要求：保持已设定的音色和目标语速，吐字节奏均匀、停顿自然。'
    '不要因句子长短、标点或对话情绪突然加速或减速，不刻意拖长尾音。'
    '保持自然表达，不改变原文内容。';

String withStableNarration(String? instructions) {
  final base = instructions?.trim() ?? '';
  if (base.contains(stableNarrationInstruction)) return base;
  return [if (base.isNotEmpty) base, stableNarrationInstruction].join('\n');
}
