import 'package:flutter/material.dart';

/// Default accent seed used when no theme colour was ever chosen.
const int defaultThemeSeed = 0xFF197D74;

/// Surface colours a preset paints behind the widgets.
///
/// Material derives components from the accent, but the page canvas, cards and
/// body text keep their own values so a preset can change the whole interface,
/// not just button fills.
@immutable
class ThemeCanvas {
  const ThemeCanvas({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.navSelectedBg,
    required this.navSelectedFg,
    required this.navUnselected,
  });

  /// Page canvas behind lists, shelves and dialogs' scrim.
  final Color background;

  /// Cards, app bars, navigation bars, sheets and popup menus.
  final Color surface;
  final Color text;
  final Color muted;
  final Color navSelectedBg;
  final Color navSelectedFg;
  final Color navUnselected;

  /// Tint the canvas from the accent: a very light wash in light mode and a
  /// deep tinted charcoal in dark mode, so presets stay coherent without a
  /// hand-tuned value for every colour.
  static ThemeCanvas derived(Color seed, Brightness brightness) {
    final hsl = HSLColor.fromColor(seed);
    final hue = hsl.hue;
    final saturation = hsl.saturation;

    Color at(double s, double lightness) => HSLColor.fromAHSL(
          1,
          hue,
          s.clamp(0.0, 1.0),
          lightness.clamp(0.0, 1.0),
        ).toColor();

    if (brightness == Brightness.dark) {
      final wash = (saturation * 1.4 + 0.16).clamp(0.18, 0.45);
      return ThemeCanvas(
        background: at(wash, 0.105),
        surface: at(wash * 0.9, 0.16),
        text: at(0.06, 0.92),
        muted: at(0.10, 0.68),
        navSelectedBg: at(wash * 0.8, 0.25),
        navSelectedFg: at((saturation + 0.25).clamp(0.30, 0.70), 0.85),
        navUnselected: at(0.05, 0.78),
      );
    }
    final wash = (saturation * 0.9 + 0.10).clamp(0.12, 0.55);
    return ThemeCanvas(
      background: at(wash, 0.925),
      surface: at(wash * 0.55, 0.985),
      text: at(0.18, 0.14),
      muted: at(0.10, 0.40),
      navSelectedBg: at((wash + 0.18).clamp(0.0, 0.8), 0.88),
      navSelectedFg: at((saturation + 0.20).clamp(0.30, 0.70), 0.32),
      navUnselected: at(0.06, 0.28),
    );
  }

  ThemeCanvas copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? muted,
    Color? navSelectedBg,
    Color? navSelectedFg,
    Color? navUnselected,
  }) {
    return ThemeCanvas(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      navSelectedBg: navSelectedBg ?? this.navSelectedBg,
      navSelectedFg: navSelectedFg ?? this.navSelectedFg,
      navUnselected: navUnselected ?? this.navUnselected,
    );
  }

  /// Persisted as plain ARGB ints; only user edits use this.
  Map<String, dynamic> toMap() => {
        'background': background.toARGB32(),
        'surface': surface.toARGB32(),
        'text': text.toARGB32(),
        'muted': muted.toARGB32(),
        'navSelectedBg': navSelectedBg.toARGB32(),
        'navSelectedFg': navSelectedFg.toARGB32(),
        'navUnselected': navUnselected.toARGB32(),
      };

  static ThemeCanvas? fromMap(Object? value) {
    if (value is! Map) return null;
    for (final key in [
      'background',
      'surface',
      'text',
      'muted',
      'navSelectedBg',
      'navSelectedFg',
      'navUnselected'
    ]) {
      final raw = value[key];
      if (raw is! int || raw < 0 || raw > 0xFFFFFFFF) return null;
    }
    Color read(String key) {
      final raw = value[key];
      return raw is int ? Color(raw) : const Color(0xFF000000);
    }

    return ThemeCanvas(
      background: read('background'),
      surface: read('surface'),
      text: read('text'),
      muted: read('muted'),
      navSelectedBg: read('navSelectedBg'),
      navSelectedFg: read('navSelectedFg'),
      navUnselected: read('navUnselected'),
    );
  }
}

/// A named accent colour plus an optional canvas.
///
/// Material derives the component scheme from the seed; [lightCanvas] and
/// [darkCanvas] are only needed when the preset should paint the page itself
/// (paper, deep night, high-contrast white, …). Custom presets keep just a name
/// and an accent, so their canvas is derived.
@immutable
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.colorValue,
    this.builtIn = false,
    this.lightCanvas,
    this.darkCanvas,
  });

  final String id;

  /// Simplified Chinese label; custom presets also keep their single user name.
  final String name;
  final String nameEn;
  final int colorValue;
  final bool builtIn;
  final ThemeCanvas? lightCanvas;
  final ThemeCanvas? darkCanvas;

  Color get color => Color(colorValue);

  String label(Locale locale) =>
      locale.languageCode == 'zh' || nameEn.trim().isEmpty ? name : nameEn;

  ThemeCanvas canvasFor(Brightness brightness) {
    final explicit = brightness == Brightness.dark ? darkCanvas : lightCanvas;
    return explicit ?? ThemeCanvas.derived(color, brightness);
  }

  ThemePreset copyWith({String? name, String? nameEn, int? colorValue}) {
    return ThemePreset(
      id: id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      colorValue: colorValue ?? this.colorValue,
      builtIn: builtIn,
      lightCanvas: lightCanvas,
      darkCanvas: darkCanvas,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'nameEn': nameEn,
        'color': colorValue,
      };

  static ThemePreset? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final color = value['color'];
    final colorValue = color is int ? color : defaultThemeSeed;
    final nameEn = value['nameEn'];
    return ThemePreset(
      id: id,
      name: name.trim(),
      nameEn: nameEn is String ? nameEn.trim() : '',
      colorValue: colorValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemePreset &&
          other.id == id &&
          other.name == name &&
          other.nameEn == nameEn &&
          other.colorValue == colorValue &&
          other.builtIn == builtIn;

  @override
  int get hashCode => Object.hash(id, name, nameEn, colorValue, builtIn);
}

/// Ordered presets: reading scenarios first, then palette-style colours.
const List<ThemePreset> builtInThemePresets = [
  // Scenes — these carry their own canvas so the page itself changes.
  ThemePreset(
    id: 'day',
    name: '白天 · 晴空',
    nameEn: 'Daylight sky',
    colorValue: 0xFF2E86AB,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFE6F7FE),
      surface: Color(0xFFF4FBFE),
      text: Color(0xFF0E2730),
      muted: Color(0xFF40606B),
      navSelectedBg: Color(0xFFC9EDF8),
      navSelectedFg: Color(0xFF0F526B),
      navUnselected: Color(0xFF2A4048),
    ),
  ),
  ThemePreset(
    id: 'dusk',
    name: '傍晚 · 暖橙',
    nameEn: 'Warm dusk',
    colorValue: 0xFFB4633A,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFFFE8C9),
      surface: Color(0xFFFFF4E8),
      text: Color(0xFF3A1E08),
      muted: Color(0xFF7A5233),
      navSelectedBg: Color(0xFFFBD3B2),
      navSelectedFg: Color(0xFF7A3708),
      navUnselected: Color(0xFF4E3826),
    ),
    darkCanvas: ThemeCanvas(
      background: Color(0xFF2A1508),
      surface: Color(0xFF36200F),
      text: Color(0xFFF2E3D5),
      muted: Color(0xFFB99C82),
      navSelectedBg: Color(0xFF46301F),
      navSelectedFg: Color(0xFFF1BE93),
      navUnselected: Color(0xFFD8C3B0),
    ),
  ),
  ThemePreset(
    id: 'night',
    name: '深夜 · 藏蓝',
    nameEn: 'Deep night',
    colorValue: 0xFF3B4A6B,
    builtIn: true,
    darkCanvas: ThemeCanvas(
      background: Color(0xFF0B1020),
      surface: Color(0xFF151C30),
      text: Color(0xFFDDE4F5),
      muted: Color(0xFF93A0C0),
      navSelectedBg: Color(0xFF243052),
      navSelectedFg: Color(0xFFB9C9F7),
      navUnselected: Color(0xFFB4BDD6),
    ),
  ),
  ThemePreset(
    id: 'glare',
    name: '强光 · 高对比',
    nameEn: 'Bright light',
    colorValue: 0xFF8A6200,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF000000),
      muted: Color(0xFF3D3D3D),
      navSelectedBg: Color(0xFFFFE39A),
      navSelectedFg: Color(0xFF3A2800),
      navUnselected: Color(0xFF1A1A1A),
    ),
  ),
  // Palettes
  ThemePreset(
    id: 'modu',
    name: '默读青',
    nameEn: 'Modu teal',
    colorValue: defaultThemeSeed,
    builtIn: true,
  ),
  ThemePreset(
    id: 'ink',
    name: '水墨书香',
    nameEn: 'Ink and paper',
    colorValue: 0xFF6B5B4E,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFF3E9D6),
      surface: Color(0xFFFBF5E9),
      text: Color(0xFF332A1E),
      muted: Color(0xFF6B5943),
      navSelectedBg: Color(0xFFE7D6B8),
      navSelectedFg: Color(0xFF4F3B1F),
      navUnselected: Color(0xFF4A4038),
    ),
    darkCanvas: ThemeCanvas(
      background: Color(0xFF15120D),
      surface: Color(0xFF221C14),
      text: Color(0xFFEDE4D3),
      muted: Color(0xFFB5A48A),
      navSelectedBg: Color(0xFF3B3023),
      navSelectedFg: Color(0xFFE6D3AE),
      navUnselected: Color(0xFFD3C8B6),
    ),
  ),
  ThemePreset(
    id: 'purple',
    name: '魅力紫',
    nameEn: 'Charming purple',
    colorValue: 0xFF6D73AA,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFEBE6FB),
      surface: Color(0xFFF7F4FF),
      text: Color(0xFF1B1633),
      muted: Color(0xFF5A5280),
      navSelectedBg: Color(0xFFD9D1F7),
      navSelectedFg: Color(0xFF433A85),
      navUnselected: Color(0xFF3A374A),
    ),
    darkCanvas: ThemeCanvas(
      background: Color(0xFF141221),
      surface: Color(0xFF1D1A2E),
      text: Color(0xFFE6E2F5),
      muted: Color(0xFFA7A1C2),
      navSelectedBg: Color(0xFF2E2950),
      navSelectedFg: Color(0xFFCFC7F7),
      navUnselected: Color(0xFFC6C1D8),
    ),
  ),
  ThemePreset(
    id: 'green',
    name: '清新护眼',
    nameEn: 'Fresh green',
    colorValue: 0xFF5E9C6B,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFE2F4E5),
      surface: Color(0xFFF3FBF5),
      text: Color(0xFF12281A),
      muted: Color(0xFF44604C),
      navSelectedBg: Color(0xFFC9EBD0),
      navSelectedFg: Color(0xFF1B5A2C),
      navUnselected: Color(0xFF32453A),
    ),
  ),
  ThemePreset(
    id: 'ocean',
    name: '蓝色海洋',
    nameEn: 'Ocean blue',
    colorValue: 0xFF2F6FB2,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFDBE8F8),
      surface: Color(0xFFF0F6FD),
      text: Color(0xFF0C2033),
      muted: Color(0xFF3C5871),
      navSelectedBg: Color(0xFFC2DCEE),
      navSelectedFg: Color(0xFF10456E),
      navUnselected: Color(0xFF2D3D4A),
    ),
  ),
  ThemePreset(
    id: 'sunset',
    name: '落日余晖',
    nameEn: 'Sunset glow',
    colorValue: 0xFFC4693B,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFFFD9CB),
      surface: Color(0xFFFFF5EE),
      text: Color(0xFF38180A),
      muted: Color(0xFF7A4A30),
      navSelectedBg: Color(0xFFFBD2B8),
      navSelectedFg: Color(0xFF7E3309),
      navUnselected: Color(0xFF4C3427),
    ),
  ),
  ThemePreset(
    id: 'pink',
    name: '粉色少女',
    nameEn: 'Soft pink',
    colorValue: 0xFFCB8A9E,
    builtIn: true,
    lightCanvas: ThemeCanvas(
      background: Color(0xFFFFE4EC),
      surface: Color(0xFFFFF4F7),
      text: Color(0xFF35141F),
      muted: Color(0xFF7A4A57),
      navSelectedBg: Color(0xFFFACBDA),
      navSelectedFg: Color(0xFF863549),
      navUnselected: Color(0xFF4E3A40),
    ),
  ),
];

/// Scene presets come first and are labelled as such in settings.
const int builtInScenePresetCount = 4;

ThemePreset? builtInThemePresetById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final preset in builtInThemePresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Resolve the preset that matches a stored seed colour, for legacy installs
/// that only ever saved [themeColor].
ThemePreset? builtInThemePresetForColor(int colorValue) {
  for (final preset in builtInThemePresets) {
    if (preset.colorValue == colorValue) return preset;
  }
  return null;
}
