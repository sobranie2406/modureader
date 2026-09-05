import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Microsoft Edge Read Aloud client using the current consumer protocol.
///
/// The time-bound Sec-MS-GEC value is required by the service. A stale fixed
/// token is rejected with HTTP 403, which is why the former implementation no
/// longer worked.
class EdgeTtsClient {
  EdgeTtsClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _chromiumFullVersion = '143.0.3650.75';
  static const _chromiumMajorVersion = '143';
  static const _secMsGecVersion = '1-$_chromiumFullVersion';
  static const _windowsEpochSeconds = 11644473600;
  static const _defaultVoice = 'zh-CN-XiaoxiaoNeural';
  static const _uuid = Uuid();

  final http.Client _httpClient;
  double _clockSkewSeconds = 0;

  static const Map<String, String> _baseHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/$_chromiumMajorVersion.0.0.0 Safari/537.36 '
        'Edg/$_chromiumMajorVersion.0.0.0',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Generates the five-minute, time-bound token expected by Edge Read Aloud.
  static String generateSecMsGec({
    DateTime? now,
    double clockSkewSeconds = 0,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    final unixSeconds = current.microsecondsSinceEpoch / 1000000;
    var windowsSeconds = unixSeconds + clockSkewSeconds + _windowsEpochSeconds;
    windowsSeconds -= windowsSeconds % 300;
    final windowsTicks = (windowsSeconds * 10000000).round();
    return sha256
        .convert(ascii.encode('$windowsTicks$_trustedClientToken'))
        .toString()
        .toUpperCase();
  }

  Future<List<TtsVoice>> getVoices() async {
    var response = await _requestVoiceList();
    if (response.statusCode == HttpStatus.forbidden &&
        _adjustClockFromResponse(response)) {
      response = await _requestVoiceList();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Edge TTS voice list failed (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException('Edge TTS returned an invalid voice list');
    }
    return decoded
        .whereType<Map>()
        .map((item) {
          final voice = Map<String, dynamic>.from(item);
          return TtsVoice(
            shortName: voice['ShortName']?.toString() ?? '',
            name: voice['LocalName']?.toString() ??
                voice['FriendlyName']?.toString() ??
                voice['ShortName']?.toString() ??
                '',
            locale: voice['Locale']?.toString() ?? '',
            gender: voice['Gender']?.toString() ?? '',
            rawData: voice,
          );
        })
        .where((voice) => voice.shortName.isNotEmpty)
        .toList();
  }

  Future<Uint8List> synthesize(
    String text, {
    String voice = _defaultVoice,
    double rate = 1,
    double pitch = 1,
  }) async {
    final chunks = _escapeAndSplitText(text);
    if (chunks.isEmpty) return Uint8List(0);

    final audio = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      audio.add(await _synthesizeChunk(
        chunk,
        voice: voice,
        rate: rate,
        pitch: pitch,
      ));
    }
    return audio.takeBytes();
  }

  Future<http.Response> _requestVoiceList() {
    return _httpClient.get(
      _voiceListUri(),
      headers: {
        ..._baseHeaders,
        'Accept': '*/*',
        'Sec-CH-UA':
            '"Not_A Brand";v="99", "Microsoft Edge";v="$_chromiumMajorVersion", '
                '"Chromium";v="$_chromiumMajorVersion"',
        'Sec-CH-UA-Mobile': '?0',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
        'Cookie': 'muid=${_muid()};',
      },
    ).timeout(const Duration(seconds: 15));
  }

  Uri _voiceListUri() => Uri.https(
        'speech.platform.bing.com',
        '/consumer/speech/synthesize/readaloud/voices/list',
        {
          'trustedclienttoken': _trustedClientToken,
          'Sec-MS-GEC': generateSecMsGec(
            clockSkewSeconds: _clockSkewSeconds,
          ),
          'Sec-MS-GEC-Version': _secMsGecVersion,
        },
      );

  Uri _webSocketUri() => Uri(
        scheme: 'wss',
        host: 'speech.platform.bing.com',
        port: 443,
        path: '/consumer/speech/synthesize/readaloud/edge/v1',
        queryParameters: {
          'TrustedClientToken': _trustedClientToken,
          'ConnectionId': _connectionId(),
          'Sec-MS-GEC': generateSecMsGec(
            clockSkewSeconds: _clockSkewSeconds,
          ),
          'Sec-MS-GEC-Version': _secMsGecVersion,
        },
      );

  bool _adjustClockFromResponse(http.Response response) {
    return _adjustClockFromDate(response.headers['date']);
  }

  bool _adjustClockFromDate(String? serverDate) {
    if (serverDate == null) return false;
    try {
      final serverTime = HttpDate.parse(serverDate).toUtc();
      _clockSkewSeconds =
          serverTime.difference(DateTime.now().toUtc()).inSeconds.toDouble();
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<Uint8List> _synthesizeChunk(
    String escapedText, {
    required String voice,
    required double rate,
    required double pitch,
  }) async {
    final socket = await _connectWebSocket();

    try {
      socket.add(_speechConfigMessage());
      socket.add(_ssmlMessage(
        escapedText,
        voice: voice,
        rate: rate,
        pitch: pitch,
      ));

      final audio = BytesBuilder(copy: false);
      var receivedAudio = false;
      await for (final event in socket.timeout(const Duration(seconds: 60))) {
        if (event is String) {
          if (_messagePath(event) == 'turn.end') break;
          continue;
        }
        if (event is! List<int>) continue;
        final payload = _audioPayload(event);
        if (payload != null && payload.isNotEmpty) {
          receivedAudio = true;
          audio.add(payload);
        }
      }
      if (!receivedAudio) {
        throw const WebSocketException('Edge TTS returned no audio');
      }
      return audio.takeBytes();
    } finally {
      try {
        await socket.close().timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Do not let a server that stopped responding block the playback queue.
      }
    }
  }

  Future<WebSocket> _connectWebSocket() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _openWebSocket();
      } on _EdgeWebSocketUpgradeException catch (error) {
        if (attempt == 0 &&
            error.statusCode == HttpStatus.forbidden &&
            _adjustClockFromDate(error.dateHeader)) {
          continue;
        }
        rethrow;
      }
    }
    throw const WebSocketException('Edge TTS WebSocket connection failed');
  }

  Future<WebSocket> _openWebSocket() async {
    final uri = _webSocketUri();
    final requestUri = uri.replace(scheme: 'https');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = _baseHeaders['User-Agent'];
    try {
      final request = await client
          .openUrl('GET', requestUri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.hostHeader, uri.host);
      request.headers.set(HttpHeaders.upgradeHeader, 'websocket');
      request.headers.set(HttpHeaders.connectionHeader, 'Upgrade');
      request.headers.set('Sec-WebSocket-Key', _webSocketKey());
      request.headers.set('Sec-WebSocket-Version', '13');
      request.headers.set(
        'Sec-WebSocket-Extensions',
        'permessage-deflate; client_max_window_bits',
      );
      request.headers.set('Pragma', 'no-cache');
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set(
        'Accept-Encoding',
        'gzip, deflate, br, zstd',
      );
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');
      request.headers.set(
        'Origin',
        'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      );
      request.headers.set('Cookie', 'muid=${_muid()};');

      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.switchingProtocols) {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 2), onTimeout: () => '');
        throw _EdgeWebSocketUpgradeException(
          statusCode: response.statusCode,
          dateHeader: response.headers.value(HttpHeaders.dateHeader),
          body: body,
        );
      }

      final detachedSocket =
          await response.detachSocket().timeout(const Duration(seconds: 15));
      return WebSocket.fromUpgradedSocket(
        detachedSocket,
        serverSide: false,
        compression: CompressionOptions.compressionDefault,
      );
    } finally {
      client.close(force: true);
    }
  }

  String _speechConfigMessage() => 'X-Timestamp:${_dateToString()}\r\n'
      'Content-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":{'
      '"sentenceBoundaryEnabled":"false",'
      '"wordBoundaryEnabled":"false"},'
      '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n';

  String _ssmlMessage(
    String escapedText, {
    required String voice,
    required double rate,
    required double pitch,
  }) {
    final requestId = _connectionId();
    final ratePercent = ((rate.clamp(0.1, 3.0) - 1) * 100).round();
    final pitchPercent = ((pitch.clamp(0.5, 2.0) - 1) * 100).round();
    final rateValue = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';
    final pitchValue = pitchPercent >= 0 ? '+$pitchPercent%' : '$pitchPercent%';
    final safeVoice = const HtmlEscape().convert(voice);
    final ssml =
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'><voice name='$safeVoice'><prosody "
        "pitch='$pitchValue' rate='$rateValue' volume='+0%'>"
        '$escapedText</prosody></voice></speak>';
    return 'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:${_dateToString()}Z\r\n'
        'Path:ssml\r\n\r\n'
        '$ssml';
  }

  static List<String> _escapeAndSplitText(String text) {
    const maxBytes = 4096;
    final chunks = <String>[];
    var current = StringBuffer();
    var currentBytes = 0;

    for (final rune in text.runes) {
      final safeRune = (rune <= 8 ||
              (rune >= 11 && rune <= 12) ||
              (rune >= 14 && rune <= 31))
          ? ' '
          : String.fromCharCode(rune);
      final escaped = const HtmlEscape().convert(safeRune);
      final escapedBytes = utf8.encode(escaped).length;
      if (currentBytes + escapedBytes > maxBytes && currentBytes > 0) {
        chunks.add(current.toString().trim());
        current = StringBuffer();
        currentBytes = 0;
      }
      current.write(escaped);
      currentBytes += escapedBytes;
    }
    if (currentBytes > 0) chunks.add(current.toString().trim());
    return chunks.where((chunk) => chunk.isNotEmpty).toList();
  }

  static Uint8List? _audioPayload(List<int> message) {
    if (message.length < 2) return null;
    final headerLength = (message[0] << 8) | message[1];
    final payloadStart = headerLength + 2;
    if (payloadStart > message.length) {
      throw const FormatException('Invalid Edge TTS audio frame');
    }
    final header = utf8.decode(
      message.sublist(2, min(payloadStart, message.length)),
      allowMalformed: true,
    );
    if (!header.toLowerCase().contains('path:audio')) return null;
    return Uint8List.fromList(message.sublist(payloadStart));
  }

  static String? _messagePath(String message) {
    final headerEnd = message.indexOf('\r\n\r\n');
    final headers = headerEnd < 0 ? message : message.substring(0, headerEnd);
    for (final line in headers.split('\r\n')) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      if (line.substring(0, separator).trim().toLowerCase() == 'path') {
        return line.substring(separator + 1).trim().toLowerCase();
      }
    }
    return null;
  }

  static String _dateToString() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${weekdays[now.weekday - 1]} ${months[now.month - 1]} '
        '${two(now.day)} ${now.year} ${two(now.hour)}:${two(now.minute)}:'
        '${two(now.second)} GMT+0000 (Coordinated Universal Time)';
  }

  static String _connectionId() => _uuid.v4().replaceAll('-', '').toLowerCase();

  static String _muid() => _uuid.v4().replaceAll('-', '').toUpperCase();

  static String _webSocketKey() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  void close() => _httpClient.close();
}

class _EdgeWebSocketUpgradeException implements Exception {
  const _EdgeWebSocketUpgradeException({
    required this.statusCode,
    this.dateHeader,
    this.body,
  });

  final int statusCode;
  final String? dateHeader;
  final String? body;

  @override
  String toString() => 'Edge TTS WebSocket upgrade failed ($statusCode)'
      '${body == null || body!.isEmpty ? '' : ': $body'}';
}

class EdgeTtsProvider extends TtsServiceProvider {
  static final EdgeTtsProvider _instance = EdgeTtsProvider._();

  factory EdgeTtsProvider() => _instance;

  EdgeTtsProvider._();

  final EdgeTtsClient _client = EdgeTtsClient();

  @override
  TtsService get service => TtsService.edge;

  @override
  String getLabel(BuildContext context) => 'Edge TTS';

  @override
  List<ConfigItem> getConfigItems(BuildContext context) => [
        ConfigItem(
          key: 'description',
          label: 'Edge TTS',
          type: ConfigItemType.tip,
          defaultValue: '免 API 密钥，使用 Microsoft Edge 在线朗读语音。',
        ),
      ];

  @override
  Map<String, dynamic> getConfig() => const {
        'description': '免 API 密钥，使用 Microsoft Edge 在线朗读语音。',
      };

  @override
  void saveConfig(Map<String, dynamic> config) {}

  @override
  Future<Uint8List> speak(
    String text,
    String? voice,
    double rate,
    double pitch,
  ) {
    return _client.synthesize(
      text,
      voice: resolveVoice(voice),
      rate: rate,
      pitch: pitch,
    );
  }

  @override
  Future<List<TtsVoice>> getVoices() => _client.getVoices();

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map) {
      return TtsVoice.fromMap(Map<String, dynamic>.from(voiceData));
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    final selected = Prefs().getTtsVoiceModel(serviceId);
    return selected.isEmpty ? EdgeTtsClient._defaultVoice : selected;
  }
}
