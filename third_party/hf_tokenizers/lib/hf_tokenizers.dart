/// HuggingFace tokenizers for Dart, over FFI.
///
/// Load any model's `tokenizer.json` with [Tokenizer.fromFile] or
/// [Tokenizer.fromBytes], then [Tokenizer.encode] text to token ids and
/// [Tokenizer.decode] them back. The ids are byte-exact with the reference
/// Rust implementation, so they match what the model was trained on.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

/// Copies [text] as UTF-8 into a freshly `calloc`ed buffer and returns the
/// pointer with the byte length.
///
/// The FFI encode/lookup calls take an explicit length, so a U+0000 byte inside
/// [text] is passed through rather than cutting the string short the way a
/// NUL-terminated buffer would. The buffer is at least one byte, so the pointer
/// is never null even for empty input; free it with `calloc.free`.
(Pointer<Uint8>, int) _allocUtf8(String text) {
  final bytes = utf8.encode(text);
  final ptr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) {
    ptr.asTypedList(bytes.length).setAll(0, bytes);
  }
  return (ptr, bytes.length);
}

/// The largest token id the native side can take: vocabularies are indexed by
/// `uint32`, and anything above this would wrap into a different, valid id.
const int _maxTokenId = 0xFFFFFFFF;

/// One token from [Tokenizer.encodeWithOffsets]: its [id] and the `[start, end)`
/// span of the input it came from.
///
/// [start] and [end] are **byte** offsets into the UTF-8 encoding of the input,
/// matching what the underlying `tokenizers` crate reports. For ASCII text a
/// byte offset equals a character index, but for anything else it does not, so
/// slice the UTF-8 bytes rather than calling `String.substring` (which counts
/// UTF-16 units):
///
/// ```dart
/// final bytes = utf8.encode(text);
/// final piece = utf8.decode(bytes.sublist(token.start, token.end));
/// ```
///
/// This is what token-accurate chunking and span highlighting need. A special
/// token added by the model (such as `[CLS]`) has an empty span where
/// `start == end`.
final class TokenOffset {
  /// Creates a token offset.
  const TokenOffset(this.id, this.start, this.end);

  /// The token id, the same value [Tokenizer.encode] would return in this
  /// position.
  final int id;

  /// The start byte offset of this token in the UTF-8 input (inclusive).
  final int start;

  /// The end byte offset of this token in the UTF-8 input (exclusive).
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TokenOffset &&
      other.id == id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, start, end);

  @override
  String toString() => 'TokenOffset($id, $start..$end)';
}

/// A tokenizer loaded from a HuggingFace `tokenizer.json`.
///
/// Backed by the Rust `tokenizers` crate, so every normalizer, pre-tokenizer,
/// model (BPE, byte-level BPE, WordPiece, Unigram), and post-processor in the
/// file is applied exactly as the reference does.
final class Tokenizer implements Finalizable {
  Tokenizer._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  final Pointer<Void> _handle;
  static final NativeFinalizer _finalizer = NativeFinalizer(tkFreePtr);
  bool _closed = false;

  /// Loads a tokenizer from the raw bytes of a `tokenizer.json`.
  ///
  /// Throws [FormatException] if the bytes are not a valid tokenizer.
  factory Tokenizer.fromBytes(Uint8List json) {
    final buffer = calloc<Uint8>(json.length);
    buffer.asTypedList(json.length).setAll(0, json);
    final handle = tkFromBytes(buffer, json.length);
    calloc.free(buffer);
    if (handle == nullptr) {
      throw const FormatException('Not a valid tokenizer.json');
    }
    return Tokenizer._(handle);
  }

  /// Loads a tokenizer from a `tokenizer.json` file on disk.
  factory Tokenizer.fromFile(String path) =>
      Tokenizer.fromBytes(File(path).readAsBytesSync());

  /// The vocabulary size, including any added tokens.
  int get vocabSize {
    _ensureOpen();
    return tkVocabSize(_handle);
  }

  /// The id of a single [token] string, or null if it is not in the vocabulary.
  ///
  /// Useful for finding a model's special tokens, for example
  /// `tokenToId('[CLS]')`, without encoding a whole string.
  int? tokenToId(String token) {
    _ensureOpen();
    final (input, inputLen) = _allocUtf8(token);
    final outId = calloc<Uint32>();
    try {
      final found = tkTokenToId(_handle, input, inputLen, outId);
      return found ? outId.value : null;
    } finally {
      calloc.free(input);
      calloc.free(outId);
    }
  }

  /// The token string for a single [id], or null if it is not in the
  /// vocabulary.
  ///
  /// This is the inverse of [tokenToId]. Unlike [decode], it returns the raw
  /// token, including any sub-word markers the model uses (such as WordPiece's
  /// `##` prefix), rather than a detokenized piece of text.
  ///
  /// An [id] outside the `uint32` range the vocabulary is indexed by is not in
  /// it either, so this returns null rather than letting the value wrap.
  String? idToToken(int id) {
    _ensureOpen();
    if (id < 0 || id > _maxTokenId) return null;
    final ptr = tkIdToToken(_handle, id);
    if (ptr == nullptr) return null;
    final token = ptr.toDartString();
    tkFreeString(ptr);
    return token;
  }

  /// The number of tokens [text] encodes to.
  ///
  /// Same value as `encode(text, addSpecialTokens: addSpecialTokens).length`,
  /// including the same default: [addSpecialTokens] is true, so on this
  /// package's BERT fixture an empty string counts as 2 (`[CLS]` and `[SEP]`).
  ///
  /// The HuggingFace crate has `encode_fast`, which skips converting each
  /// token's span back to offsets in the original string. It still runs
  /// normalize, pre-tokenize, the model and post-process: those steps are
  /// what determine the count, and there is no crate API that skips them.
  /// Measured on the BERT fixture this package ships (`tool/measure_count.dart`),
  /// that skip is lost in the tokenize work, so this method does not claim a
  /// faster path. It exists so a caller who only needs the number does not
  /// have to take `.length` of a list they immediately throw away.
  int count(String text, {bool addSpecialTokens = true}) =>
      encode(text, addSpecialTokens: addSpecialTokens).length;

  /// Encodes [text] into token ids.
  ///
  /// [addSpecialTokens] controls whether the model's special tokens (such as
  /// BERT's `[CLS]`/`[SEP]`) are added, matching the reference default of true.
  List<int> encode(String text, {bool addSpecialTokens = true}) {
    _ensureOpen();
    final (input, inputLen) = _allocUtf8(text);
    final outLen = calloc<IntPtr>();
    try {
      final ptr = tkEncode(_handle, input, inputLen, addSpecialTokens, outLen);
      if (ptr == nullptr) throw StateError('Failed to encode text');
      final ids = ptr.asTypedList(outLen.value).toList();
      tkFreeIds(ptr, outLen.value);
      return ids;
    } finally {
      calloc.free(input);
      calloc.free(outLen);
    }
  }

  /// Encodes [text] into tokens, keeping each token's byte span in the input.
  ///
  /// Like [encode], but every token comes back as a [TokenOffset] carrying the
  /// `[start, end)` UTF-8 byte range it was produced from, so you can map tokens
  /// back to the text (see [TokenOffset] for how to slice with those offsets).
  /// This is what token-accurate chunking, span highlighting and named-entity
  /// extraction need. [addSpecialTokens] behaves as in [encode].
  List<TokenOffset> encodeWithOffsets(
    String text, {
    bool addSpecialTokens = true,
  }) {
    _ensureOpen();
    final (input, inputLen) = _allocUtf8(text);
    final outLen = calloc<IntPtr>();
    final outIds = calloc<Pointer<Uint32>>();
    try {
      final offsetsPtr = tkEncodeOffsets(
        _handle,
        input,
        inputLen,
        addSpecialTokens,
        outLen,
        outIds,
      );
      if (offsetsPtr == nullptr) throw StateError('Failed to encode text');
      final count = outLen.value;
      final idsPtr = outIds.value;
      final ids = idsPtr.asTypedList(count);
      final offsets = offsetsPtr.asTypedList(count * 2);
      final result = [
        for (var i = 0; i < count; i++)
          TokenOffset(ids[i], offsets[i * 2], offsets[i * 2 + 1]),
      ];
      tkFreeIds(idsPtr, count);
      tkFreeIds(offsetsPtr, count * 2);
      return result;
    } finally {
      calloc.free(input);
      calloc.free(outLen);
      calloc.free(outIds);
    }
  }

  /// Decodes token [ids] back into text.
  ///
  /// Throws [ArgumentError] if an id falls outside the `uint32` range the
  /// vocabulary is indexed by. The native call takes `uint32`, so such a value
  /// would otherwise be truncated into a different, valid id and decode to the
  /// wrong token instead of failing.
  String decode(List<int> ids, {bool skipSpecialTokens = true}) {
    _ensureOpen();
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (id < 0 || id > _maxTokenId) {
        throw ArgumentError.value(
          id,
          'ids[$i]',
          'token id must be between 0 and $_maxTokenId',
        );
      }
    }
    final array = calloc<Uint32>(ids.length);
    array.asTypedList(ids.length).setAll(0, ids);
    try {
      final ptr = tkDecode(_handle, array, ids.length, skipSpecialTokens);
      if (ptr == nullptr) throw StateError('Failed to decode ids');
      final text = ptr.toDartString();
      tkFreeString(ptr);
      return text;
    } finally {
      calloc.free(array);
    }
  }

  /// Returns the longest prefix of [text] that encodes to at most [maxTokens]
  /// tokens.
  ///
  /// Model context windows and embedding endpoints are measured in tokens, but
  /// `String.substring` counts UTF-16 units, so the usual guess of "about four
  /// characters per token" either wastes budget or overshoots it. This cuts at
  /// the exact boundary the tokenizer itself reports.
  ///
  /// ```dart
  /// final head = tk.truncateToTokens(document, 512);
  /// ```
  ///
  /// The cut lands on a token boundary, which is always a UTF-8 boundary, so
  /// no character is split in half. [addSpecialTokens] is passed through and
  /// counts toward the budget the same way the model will count it: with
  /// BERT's `[CLS]` and `[SEP]`, a budget of 512 leaves 510 for text.
  ///
  /// Returns [text] unchanged when it already fits, and an empty string when
  /// [maxTokens] is 0. Throws [ArgumentError] if [maxTokens] is negative, or
  /// if it is smaller than the number of special tokens the model adds: with
  /// BERT's two, no text at all fits a budget of 1 or 2, and returning an
  /// empty string would still encode to 2.
  String truncateToTokens(
    String text,
    int maxTokens, {
    bool addSpecialTokens = true,
  }) {
    if (maxTokens < 0) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must not be negative');
    }
    if (maxTokens == 0 || text.isEmpty) return '';
    final tokens = encodeWithOffsets(text, addSpecialTokens: addSpecialTokens);
    if (tokens.length <= maxTokens) return text;

    // Special tokens own no bytes, and the model appends them to whatever it
    // is given, so the whole set has to come off the budget up front. Counting
    // only the ones inside the first maxTokens would leave the trailing [SEP]
    // unaccounted for, and the result would re-encode one token over.
    final spans = [
      for (final t in tokens)
        if (t.end > t.start) t,
    ];
    final specialCount = tokens.length - spans.length;
    final keep = maxTokens - specialCount;
    if (keep < 1) {
      // Returning an empty string here would be a trap: it still encodes to
      // specialCount tokens, so the budget this call exists to enforce would
      // be blown by its own result. Say so instead.
      throw ArgumentError.value(
        maxTokens,
        'maxTokens',
        'leaves no room for text: the model adds $specialCount special '
            'token(s), so even an empty string encodes to $specialCount',
      );
    }

    var cut = 0;
    for (var i = 0; i < keep && i < spans.length; i++) {
      if (spans[i].end > cut) cut = spans[i].end;
    }
    if (cut == 0) return '';
    return utf8.decode(utf8.encode(text).sublist(0, cut));
  }

  /// Splits [text] into consecutive pieces that each encode to at most
  /// [maxTokens] tokens.
  ///
  /// This is what an embedding model's input limit actually asks for.
  /// Character-window chunking has to guess a safe size and still overshoots
  /// on dense text, where one token can be a single byte; here every piece is
  /// measured with the tokenizer that will see it.
  ///
  /// ```dart
  /// for (final chunk in tk.chunkByTokens(document, 256, overlapTokens: 32)) {
  ///   await embed(chunk);
  /// }
  /// ```
  ///
  /// [overlapTokens] repeats that many tokens of context at the start of each
  /// following piece, which keeps a sentence split across a boundary
  /// retrievable from either side. Pieces are cut on token boundaries, so
  /// concatenating them with no overlap reproduces [text].
  ///
  /// Each piece is re-encoded to confirm it fits, because tokenization is
  /// context-dependent: a WordPiece continuation such as `##ization` is one
  /// token inside `internationalization` but two when the same bytes lead a
  /// piece. The one case that cannot be made to fit is a budget so small that
  /// a single token of the input, standing alone, already exceeds it — there
  /// is nothing left to split. That takes a budget of about three with BERT;
  /// real embedding limits are nowhere near it.
  ///
  /// [addSpecialTokens] is passed through, so each piece leaves room for the
  /// markers the model adds. Returns an empty list for empty [text]. Throws
  /// [ArgumentError] if [maxTokens] is below 1, or if [overlapTokens] is
  /// negative, or if it is not smaller than the room a chunk actually has for
  /// text — `maxTokens` less the special tokens the model adds — because then
  /// chunking would never advance. With BERT's two, a budget of 8 leaves 6, so
  /// the overlap has to be 5 or less.
  List<String> chunkByTokens(
    String text,
    int maxTokens, {
    int overlapTokens = 0,
    bool addSpecialTokens = true,
  }) {
    if (maxTokens < 1) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be at least 1');
    }
    if (overlapTokens < 0) {
      throw ArgumentError.value(
        overlapTokens,
        'overlapTokens',
        'must not be negative',
      );
    }
    if (overlapTokens >= maxTokens) {
      throw ArgumentError.value(
        overlapTokens,
        'overlapTokens',
        'must be smaller than maxTokens ($maxTokens), or chunking never '
            'advances',
      );
    }
    if (text.isEmpty) return const [];

    final tokens = encodeWithOffsets(text, addSpecialTokens: addSpecialTokens);
    // Special tokens sit outside the text, so drop them before slicing: they
    // consume budget but own no bytes to cut on.
    final spans = [
      for (final t in tokens)
        if (t.end > t.start) t,
    ];
    if (spans.isEmpty) return const [];

    // Budget counts what the model counts, so the markers come off the top.
    final specialCount = tokens.length - spans.length;
    final perChunk = maxTokens - specialCount;
    if (perChunk < 1) {
      throw ArgumentError.value(
        maxTokens,
        'maxTokens',
        'leaves no room for text after $specialCount special token(s)',
      );
    }
    final step = perChunk - overlapTokens;
    // The constructor-time check compares overlapTokens against maxTokens, but
    // what a chunk actually has room for is perChunk, which is smaller by the
    // special tokens. An overlap between the two passes that check and lands
    // here with step <= 0: at 0 the cursor never advances and this loops
    // forever, below 0 it walks backwards into spans[-1].
    if (step < 1) {
      throw ArgumentError.value(
        overlapTokens,
        'overlapTokens',
        'must be smaller than the $perChunk token(s) each chunk has room for '
            '(maxTokens $maxTokens less $specialCount special token(s)), or '
            'chunking never advances',
      );
    }

    final bytes = utf8.encode(text);
    final chunks = <String>[];
    // Where the next piece begins. Following pieces start where the previous
    // one ended rather than at their first token, because the bytes in between
    // (the whitespace no token claims) belong to the text too and would
    // otherwise vanish. With an overlap the start deliberately moves back.
    var cursor = 0;
    var start = 0;
    while (start < spans.length) {
      var end = start + perChunk < spans.length
          ? start + perChunk
          : spans.length;
      final from = (overlapTokens > 0 && start > 0)
          ? spans[start].start
          : cursor;

      // Counting the spans is not enough: tokenization depends on context, so
      // a piece can cost more tokens on its own than it did inside the whole
      // text. A WordPiece continuation is the clear case — `##ization` is one
      // token inside `internationalization`, but the same bytes leading a
      // chunk re-encode as `i` + `##zation`. Since the budget this method
      // exists to enforce is checked against the piece the caller actually
      // sends, measure that piece and give back a span until it fits.
      String piece;
      while (true) {
        final to = end == spans.length ? bytes.length : spans[end - 1].end;
        piece = utf8.decode(bytes.sublist(from, to));
        // A single span is one token of the input and cannot be split further.
        if (end - start <= 1) break;
        if (encode(piece, addSpecialTokens: addSpecialTokens).length <=
            maxTokens) {
          break;
        }
        end--;
      }
      chunks.add(piece);
      cursor = end == spans.length ? bytes.length : spans[end - 1].end;
      if (end == spans.length) break;
      // Advance by what this piece actually consumed, not by the nominal step,
      // because shrinking above may have made it shorter. The floor of 1 keeps
      // an overlap wider than a shrunken piece from stalling the loop.
      final advance = (end - start) - overlapTokens;
      start += advance < 1 ? 1 : advance;
    }
    return chunks;
  }

  /// Frees the native tokenizer now.
  ///
  /// Optional: a finalizer releases it when this object is collected. Call
  /// [close] to return the native memory promptly when you are done.
  void close() {
    if (_closed) return;
    _closed = true;
    _finalizer.detach(this);
    tkFree(_handle);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Tokenizer has been closed');
  }
}

