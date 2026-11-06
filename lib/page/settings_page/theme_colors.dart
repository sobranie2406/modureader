import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/theme_preset.dart';
import 'package:anx_reader/widgets/common/color_picker_sheet.dart';
import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/theme_mode.dart';
import 'package:flutter/material.dart';

/// Explains which widgets each canvas colour paints.
///
/// The fine-tune rows carry a one-line hint; this popover spells out what
/// "cards and bars" or "selected background" actually covers, and which two
/// colours the reading page borrows.
Widget _canvasColourLegend(BuildContext context) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final separator = zh ? '：' : ': ';
  final style = Theme.of(context).textTheme.bodyMedium!;

  final entries = <(String, String)>[
    (
      ModuStrings.text(context, '背景', 'Background'),
      zh
          ? '页面底色：书架、设置和列表背后的颜色；开启「同时应用到阅读页」后也是书页底色。'
          : 'Page canvas behind the shelf, settings and lists; also the reader paper when the reader switch is on.'
    ),
    (
      ModuStrings.text(context, '卡片与导航栏', 'Cards and bars'),
      zh
          ? '卡片、顶栏、底部导航、抽屉、弹窗和气泡菜单的底色。'
          : 'Cards, app bars, bottom navigation, drawers, dialogs and popup menus.'
    ),
    (
      ModuStrings.text(context, '正文文字', 'Body text'),
      zh
          ? '标题、正文和阅读页里的书籍文字。'
          : 'Headings, body copy and the book text in the reader.'
    ),
    (
      ModuStrings.text(context, '次要文字', 'Muted text'),
      zh
          ? '说明、时间、副标题等需要弱化的文字。'
          : 'Hints, timestamps and subtitles that should recede.'
    ),
    (
      ModuStrings.text(context, '选中项底色', 'Selected background'),
      zh
          ? '底部／侧边导航的当前项、列表选中行、开关打开时的填充。'
          : 'The current tab, selected list rows and switch fills.'
    ),
    (
      ModuStrings.text(context, '选中项文字', 'Selected text'),
      zh
          ? '上述选中项上的文字与图标。'
          : 'Text and icons drawn on those selected items.'
    ),
  ];

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RichText(
            text: TextSpan(
              style: style,
              children: [
                TextSpan(
                  text: '${entry.$1}$separator',
                  style: style.copyWith(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: entry.$2),
              ],
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          ModuStrings.text(context, '阅读页只取「背景」和「正文文字」。',
              'The reader page only takes Background and Body text.'),
          style: style.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    ],
  );
}

/// Theme hub: light/dark mode, preset palettes and custom themes.
///
/// Every preset paints the page, cards and text with its own canvas; users can
/// fine-tune any preset for the current brightness and reset it back.
class ThemeColorsPage extends StatefulWidget {
  const ThemeColorsPage({super.key});

  @override
  State<ThemeColorsPage> createState() => _ThemeColorsPageState();
}

class _ThemeColorsPageState extends State<ThemeColorsPage> {
  Brightness get _brightness => Theme.of(context).brightness;

  Future<void> _select(ThemePreset preset) async {
    await Prefs().selectThemePreset(preset);
    if (mounted) setState(() {});
  }

  Future<void> _editCustom({ThemePreset? existing}) async {
    final saved = await showDialog<ThemePreset>(
      context: context,
      builder: (_) => _ThemePresetDialog(existing: existing),
    );
    if (saved == null) return;
    await Prefs().saveCustomThemePreset(saved);
    if (mounted) setState(() {});
  }

  Future<void> _editCanvas(ThemePreset preset) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PresetColorDialog(
        preset: preset,
        brightness: _brightness,
      ),
    );
    if (saved != true) return;
    if (mounted) setState(() {});
  }

  Future<void> _resetCanvas(ThemePreset preset) async {
    await Prefs().resetPresetCanvasOverride(preset.id);
    if (mounted) setState(() {});
  }

  Future<void> _deleteCustom(ThemePreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ModuStrings.text(dialogContext, '删除主题？', 'Delete theme?')),
        content: Text(ModuStrings.text(
            dialogContext,
            '将删除「${preset.name}」。当前使用的是它时会恢复默认颜色。',
            'Removes "${preset.name}". If it is active, the default colour is restored.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(ModuStrings.text(dialogContext, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ModuStrings.text(dialogContext, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final wasActive = Prefs().themePresetId == preset.id;
    await Prefs().deleteCustomThemePreset(preset.id);
    if (wasActive) await Prefs().resetThemeColor();
    if (mounted) setState(() {});
  }

  Future<void> _restoreDefault() async {
    if (!await confirmColorReset(
      context,
      ModuStrings.text(context, '恢复默认主题颜色？其他外观设置不会改变。',
          'Restore the default theme colour? Other appearance settings will not change.'),
    )) {
      return;
    }
    await Prefs().resetThemeColor();
    if (mounted) setState(() {});
  }

  Future<void> _resetAllPresets() async {
    if (!await confirmColorReset(
      context,
      ModuStrings.text(context, '把所有预设的自定义颜色恢复成出厂值？你自定义的主题不会删除。',
          'Reset every preset colour to the factory values? Your custom themes are kept.'),
    )) {
      return;
    }
    await Prefs().resetAllPresetOverrides();
    if (mounted) setState(() {});
  }

  Widget _presetRow(ThemePreset preset, bool selected) {
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.color,
      brightness: _brightness,
    );
    final canvas = Prefs().canvasForPreset(preset, _brightness);
    return InkWell(
      key: ValueKey('theme-preset-${preset.id}'),
      onTap: () => _select(preset),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
        child: Row(
          children: [
            _Swatch(color: scheme.primary),
            const SizedBox(width: 6),
            _Swatch(color: canvas.background),
            const SizedBox(width: 6),
            _Swatch(color: canvas.text),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                preset.label(Localizations.localeOf(context)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (Prefs().presetHasOverride(preset.id))
              Tooltip(
                message: ModuStrings.text(context, '已微调', 'Edited'),
                child: Icon(Icons.tune,
                    size: 16, color: Theme.of(context).colorScheme.primary),
              ),
            const SizedBox(width: 8),
            if (selected)
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
            else
              const Icon(Icons.circle_outlined, size: 20),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _presetMenu(ThemePreset preset, {required bool custom}) {
    final overridden = Prefs().presetHasOverride(preset.id);
    return PopupMenuButton<String>(
      key: ValueKey('theme-preset-menu-${preset.id}'),
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'colors':
            _editCanvas(preset);
          case 'edit':
            _editCustom(existing: preset);
          case 'reset':
            _resetCanvas(preset);
          case 'delete':
            _deleteCustom(preset);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'colors',
          child: Text(ModuStrings.text(
              context, '微调颜色（当前模式）', 'Fine-tune colours (this mode)')),
        ),
        if (custom)
          PopupMenuItem(
            value: 'edit',
            child: Text(ModuStrings.text(context, '名称与主色', 'Name and accent')),
          ),
        if (overridden)
          PopupMenuItem(
            value: 'reset',
            child: Text(ModuStrings.text(
                context, '重置为预设值', 'Reset to factory colours')),
          ),
        if (custom)
          PopupMenuItem(
            value: 'delete',
            child: Text(ModuStrings.text(context, '删除主题', 'Delete theme')),
          ),
      ],
    );
  }

  AbstractSettingsTile _presetTile(ThemePreset preset, bool selected) =>
      CustomSettingsTile(
        child: Row(
          children: [
            Expanded(child: _presetRow(preset, selected)),
            _presetMenu(preset, custom: false),
          ],
        ),
      );

  AbstractSettingsTile _customTile(ThemePreset preset, bool selected) =>
      CustomSettingsTile(
        child: Row(
          children: [
            Expanded(child: _presetRow(preset, selected)),
            _presetMenu(preset, custom: true),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ModuStrings.text(context, '主题颜色', 'Theme colour')),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: Prefs(),
            builder: (context, _) {
              final active = Prefs().activeThemePreset;
              final custom = Prefs().customThemePresets;
              final scenes =
                  builtInThemePresets.take(builtInScenePresetCount).toList();
              final palettes =
                  builtInThemePresets.skip(builtInScenePresetCount).toList();
              return settingsSections(sections: [
                SettingsSection(
                  title:
                      Text(ModuStrings.text(context, '明暗模式', 'Light or dark')),
                  tiles: [
                    const CustomSettingsTile(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: ChangeThemeMode(),
                      ),
                    ),
                    SettingsTile.switchTile(
                      key: const ValueKey('theme-applies-to-reader'),
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(ModuStrings.text(
                          context, '同时应用到阅读页', 'Also apply to the reader')),
                      description: Text(ModuStrings.text(
                          context,
                          '切换主题时把阅读页的背景和正文颜色也换成这套配色；阅读页仍可在阅读设置里单独调整。',
                          'Switching themes also recolours the reading page background and text. The reading page can still be adjusted separately.')),
                      initialValue: Prefs().themeAppliesToReader,
                      enabled: !Prefs().eInkMode,
                      onToggle: (value) async {
                        await Prefs().setThemeAppliesToReader(value);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                SettingsSection(
                  title:
                      Text(ModuStrings.text(context, '阅读场景', 'Reading scene')),
                  tiles: [
                    for (final preset in scenes)
                      _presetTile(preset, active?.id == preset.id),
                  ],
                ),
                SettingsSection(
                  title: SettingHelp(
                    key: const ValueKey('theme-canvas-help'),
                    title:
                        Text(ModuStrings.text(context, '色彩风格', 'Colour style')),
                    description: _canvasColourLegend(context),
                  ),
                  tiles: [
                    for (final preset in palettes)
                      _presetTile(preset, active?.id == preset.id),
                  ],
                ),
                SettingsSection(
                  title: Text(ModuStrings.text(context, '我的主题', 'My themes')),
                  tiles: [
                    for (final preset in custom)
                      _customTile(preset, active?.id == preset.id),
                    CustomSettingsTile(
                      child: ListTile(
                        key: const ValueKey('theme-preset-new'),
                        leading: const Icon(Icons.add),
                        title: Text(ModuStrings.text(
                            context, '新建自定义主题', 'New custom theme')),
                        subtitle: Text(ModuStrings.text(
                            context,
                            '保存名称与颜色，之后可一键切换或继续修改。',
                            'Save a name and colour to switch back or edit later.')),
                        onTap: () => _editCustom(),
                      ),
                    ),
                  ],
                ),
                SettingsSection(
                  tiles: [
                    SettingsTile.navigation(
                      key: const ValueKey('theme-preset-reset-all'),
                      leading: const Icon(Icons.palette_outlined),
                      title: Text(ModuStrings.text(
                          context, '重置所有预设颜色', 'Reset all preset colours')),
                      onPressed: (_) => _resetAllPresets(),
                    ),
                    SettingsTile.navigation(
                      key: const ValueKey('theme-preset-restore'),
                      leading: const Icon(Icons.restore),
                      title: Text(ModuStrings.text(
                          context, '恢复默认主题颜色', 'Restore default theme colour')),
                      onPressed: (_) => _restoreDefault(),
                    ),
                  ],
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Per-preset canvas editor for the brightness currently in use.
class _PresetColorDialog extends StatefulWidget {
  const _PresetColorDialog({required this.preset, required this.brightness});

  final ThemePreset preset;
  final Brightness brightness;

  @override
  State<_PresetColorDialog> createState() => _PresetColorDialogState();
}

class _PresetColorDialogState extends State<_PresetColorDialog> {
  late ThemeCanvas _canvas =
      Prefs().canvasForPreset(widget.preset, widget.brightness);

  Future<void> _pick(
      String label,
      ThemeCanvas Function(ThemeCanvas canvas, Color color) apply,
      Color current) async {
    final color = await showRgbColorPicker(
      context: context,
      initialColor: current,
      allowAlpha: false,
    );
    if (color == null || !mounted) return;
    setState(() => _canvas = apply(_canvas, color));
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.brightness == Brightness.dark
        ? ModuStrings.text(context, '深色', 'dark')
        : ModuStrings.text(context, '浅色', 'light');
    final rows =
        <(String, String, Color, ThemeCanvas Function(ThemeCanvas, Color))>[
      (
        ModuStrings.text(context, '背景', 'Background'),
        ModuStrings.text(context, '页面与书页的底色', 'Page and paper canvas'),
        _canvas.background,
        (c, v) => c.copyWith(background: v)
      ),
      (
        ModuStrings.text(context, '卡片与导航栏', 'Cards and bars'),
        ModuStrings.text(
            context, '卡片、顶栏、导航、弹层', 'Cards, bars, navigation, popups'),
        _canvas.surface,
        (c, v) => c.copyWith(surface: v)
      ),
      (
        ModuStrings.text(context, '正文文字', 'Body text'),
        ModuStrings.text(
            context, '标题、正文与书籍文字', 'Headings, body and book text'),
        _canvas.text,
        (c, v) => c.copyWith(text: v)
      ),
      (
        ModuStrings.text(context, '次要文字', 'Muted text'),
        ModuStrings.text(
            context, '说明、时间、副标题', 'Hints, timestamps, subtitles'),
        _canvas.muted,
        (c, v) => c.copyWith(muted: v)
      ),
      (
        ModuStrings.text(context, '选中项底色', 'Selected background'),
        ModuStrings.text(
            context, '当前导航项、选中行、开关', 'Current tab, selected rows, switches'),
        _canvas.navSelectedBg,
        (c, v) => c.copyWith(navSelectedBg: v)
      ),
      (
        ModuStrings.text(context, '选中项文字', 'Selected text'),
        ModuStrings.text(
            context, '选中项上的文字与图标', 'Text and icons on them'),
        _canvas.navSelectedFg,
        (c, v) => c.copyWith(navSelectedFg: v)
      ),
    ];
    return AlertDialog(
      title: SettingHelp(
        key: const ValueKey('theme-canvas-help-dialog'),
        title: Text('${widget.preset.name} · $mode'),
        description: _canvasColourLegend(context),
      ),
      content: SizedBox(
        width: 360,
        // A plain Column keeps the dialog measurable: a shrink-wrapped
        // viewport cannot answer the intrinsic queries AlertDialog makes.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.$1),
                subtitle: Text(row.$2),
                trailing: CircleAvatar(radius: 12, backgroundColor: row.$3),
                onTap: () => _pick(row.$1, row.$4, row.$3),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('theme-preset-colors-reset'),
          onPressed: () => setState(
              () => _canvas = widget.preset.canvasFor(widget.brightness)),
          child: Text(ModuStrings.text(context, '恢复预设值', 'Factory values')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(ModuStrings.text(context, '取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('theme-preset-colors-save'),
          onPressed: () async {
            await Prefs().savePresetCanvasOverride(
                widget.preset, widget.brightness, _canvas);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: Text(ModuStrings.text(context, '保存', 'Save')),
        ),
      ],
      scrollable: true,
    );
  }
}

/// Name + colour editor. Owns its controller so the text field survives the
/// dialog's exit animation (disposing right after pop throws).
class _ThemePresetDialog extends StatefulWidget {
  const _ThemePresetDialog({this.existing});

  final ThemePreset? existing;

  @override
  State<_ThemePresetDialog> createState() => _ThemePresetDialogState();
}

class _ThemePresetDialogState extends State<_ThemePresetDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.existing?.name ?? '');
  late Color _picked =
      widget.existing?.color ?? Theme.of(context).colorScheme.primary;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final color = await showRgbColorPicker(
      context: context,
      initialColor: _picked,
      allowAlpha: false,
    );
    if (color != null && mounted) setState(() => _picked = color);
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop<ThemePreset>(
      context,
      ThemePreset(
        id: widget.existing?.id ??
            'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        nameEn: '',
        colorValue: _picked.toARGB32(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? ModuStrings.text(context, '新建自定义主题', 'New custom theme')
          : ModuStrings.text(context, '编辑自定义主题', 'Edit custom theme')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('theme-preset-name'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: ModuStrings.text(context, '主题名称', 'Theme name'),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('theme-preset-color'),
            onPressed: _pickColor,
            icon: CircleAvatar(radius: 10, backgroundColor: _picked),
            label: Text(ModuStrings.text(context, '选择主色', 'Choose accent')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ModuStrings.text(context, '取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('theme-preset-save'),
          onPressed: _controller.text.trim().isEmpty ? null : _save,
          child: Text(ModuStrings.text(context, '保存', 'Save')),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
      );
}
