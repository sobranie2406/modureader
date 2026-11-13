import 'package:modu_reader/service/registry/host_registry.dart';
import 'package:modu_reader/service/translate/ai.dart';
import 'package:modu_reader/service/translate/deepl.dart';
import 'package:modu_reader/service/translate/google_api.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/translate/microsoft_api.dart';
import 'package:modu_reader/service/translate/microsoft_free.dart';
import 'package:modu_reader/service/translate/official_api.dart';
import 'package:modu_reader/service/translate/web_view.dart';
import 'package:modu_reader/utils/env_var.dart';

/// One translation provider.
///
/// [id] is the persisted token (the enum `name`), so it can never be renamed:
/// it is written to 'translateService' and 'fullTextTranslateService', and used
/// as the suffix of the per-provider config key.
class TranslateProviderEntry implements RegistryEntry {
  const TranslateProviderEntry({
    required this.id,
    required this.builder,
    this.aliases = const [],
    this.supportsFullText = true,
    this.isWebView = false,
    this.readAnyPicker = false,
    this.owner = const RegistryOwner.builtIn(),
  });

  @override
  final String id;

  @override
  final List<String> aliases;

  @override
  final RegistryOwner owner;

  @override
  RegistryDomain get domain => RegistryDomain.translate;

  final TranslateServiceProvider Function() builder;

  /// False for page-based providers: they cannot translate a whole book.
  final bool supportsFullText;

  final bool isWebView;

  /// Shown in the compact reader/selection picker rather than only in settings.
  final bool readAnyPicker;

  /// Extra gate for entries that depend on a build flag (AI translation).
  bool get isAvailable => !(id == 'ai') || EnvVar.enableAIFeature;
}

/// The built-in translation table.
class TranslateRegistry {
  TranslateRegistry(Iterable<TranslateProviderEntry> entries) {
    for (final entry in entries) {
      registry.register(entry);
    }
  }

  static final TranslateRegistry instance = TranslateRegistry(_builtIn);

  static TranslateRegistry _current = instance;

  static TranslateRegistry get current => _current;

  static void useForTesting(TranslateRegistry? value) => _current = value ?? instance;

  final HostRegistry<TranslateProviderEntry> registry =
      HostRegistry<TranslateProviderEntry>(RegistryDomain.translate);

  /// Old token → current id. Only 'microsoft' was ever renamed; every other
  /// historical value still exists as an id.
  static const Set<String> retiredAliases = {'microsoft'};

  TranslateService? resolveService(String token) {
    final entry = registry.resolve(token);
    if (entry == null) return null;
    for (final service in TranslateService.values) {
      if (service.name == entry.id) return service;
    }
    return null;
  }

  TranslateServiceProvider providerFor(String id) {
    final entry = registry.resolve(id);
    if (entry == null) {
      throw StateError('Unknown translation provider: $id');
    }
    return entry.builder();
  }

  /// Providers offered in settings, in registration order, minus unavailable.
  List<TranslateService> get activeValues => _services(
        registry.all.where((entry) => entry.owner is BuiltInOwner),
      );

  /// The compact picker order is user-visible and was fixed before P2, so it is
  /// listed explicitly instead of following registration order.
  static const List<String> readAnyOrder = [
    'microsoftFree',
    'baiduApi',
    'microsoftApi',
    'ai',
    'deepl',
  ];

  List<TranslateService> get readAnyValues => _inOrder(readAnyOrder);

  /// Web providers keep their historical order too.
  static const List<String> webOrder = [
    'googleWeb',
    'bingWeb',
    'baiduWeb',
    'youdaoWeb',
  ];

  List<TranslateService> get webValues => _inOrder(webOrder);

  List<TranslateService> get selectionValues => [...readAnyValues, ...webValues];

  /// Ids in the fixed order used by settings export, so an older build can
  /// still read a backup written by a newer one.
  List<String> get exportOrder => [
        for (final entry in registry.all)
          if (entry.owner is BuiltInOwner && entry.id != 'ai') entry.id,
      ];

  List<TranslateService> _inOrder(List<String> ids) => [
        for (final id in ids)
          if (registry.resolve(id) case final entry? when entry.isAvailable)
            TranslateService.values.firstWhere((service) => service.name == entry.id),
      ];

  List<TranslateService> _services(Iterable<TranslateProviderEntry> entries) => [
        for (final entry in entries)
          if (entry.isAvailable)
            TranslateService.values.firstWhere((service) => service.name == entry.id),
      ];

  static final List<TranslateProviderEntry> _builtIn = [
    TranslateProviderEntry(
      id: 'microsoftFree',
      readAnyPicker: true,
      builder: MicrosoftFreeTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'bingWeb',
      isWebView: true,
      supportsFullText: false,
      builder: BingWebTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'googleWeb',
      isWebView: true,
      supportsFullText: false,
      builder: GoogleWebTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'microsoftApi',
      aliases: ['microsoft'],
      readAnyPicker: true,
      builder: MicrosoftApiTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'googleApi',
      builder: GoogleApiTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'deepl',
      readAnyPicker: true,
      builder: DeepLTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'ai',
      readAnyPicker: true,
      builder: AiTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'baiduApi',
      readAnyPicker: true,
      builder: _baiduApi,
    ),
    TranslateProviderEntry(
      id: 'baiduWeb',
      isWebView: true,
      supportsFullText: false,
      builder: BaiduWebTranslateProvider.new,
    ),
    TranslateProviderEntry(
      id: 'youdaoWeb',
      isWebView: true,
      supportsFullText: false,
      builder: YoudaoWebTranslateProvider.new,
    ),
  ];

  static TranslateServiceProvider _baiduApi() =>
      OfficialApiTranslateProvider(TranslateService.baiduApi);
}