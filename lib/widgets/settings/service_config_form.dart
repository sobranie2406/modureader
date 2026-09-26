import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Generic service configuration form widget.
/// Renders form fields based on ConfigItem definitions.
class ServiceConfigForm extends StatefulWidget {
  final List<ConfigItem> configItems;
  final Map<String, dynamic> initialConfig;
  final Function(Map<String, dynamic>) onConfigChanged;

  const ServiceConfigForm({
    super.key,
    required this.configItems,
    required this.initialConfig,
    required this.onConfigChanged,
  });

  @override
  State<ServiceConfigForm> createState() => _ServiceConfigFormState();
}

class _ServiceConfigFormState extends State<ServiceConfigForm> {
  late Map<String, dynamic> _currentConfig;
  // Track password visibility for each password field
  final Map<String, bool> _passwordVisibility = {};
  final Map<String, TextEditingController> _controllers = {};

  bool _isText(ConfigItem item) =>
      item.type == ConfigItemType.text ||
      item.type == ConfigItemType.password ||
      item.type == ConfigItemType.number;

  String _text(ConfigItem item, Map<String, dynamic> config) =>
      (config[item.key] ?? item.defaultValue)?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _currentConfig = Map.from(widget.initialConfig);
    for (final item in widget.configItems.where(_isText)) {
      _controllers[item.key] =
          TextEditingController(text: _text(item, _currentConfig));
    }
  }

  @override
  void didUpdateWidget(ServiceConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final items = widget.configItems.where(_isText).toList();
    for (final key in _controllers.keys.toList()) {
      if (!items.any((item) => item.key == key)) {
        _controllers.remove(key)!.dispose();
      }
    }
    for (final item in items) {
      final text = _text(item, widget.initialConfig);
      final controller = _controllers[item.key];
      if (controller == null) {
        _controllers[item.key] = TextEditingController(text: text);
        continue;
      }
      final oldItem =
          oldWidget.configItems.where((old) => old.key == item.key).firstOrNull;
      // Parent draft echoes must not clear IME composition or move selection.
      // Compare model values, not normalized text: a numeric draft may be empty
      // or contain leading zeros while its parsed value is still unchanged.
      if (_text(oldItem ?? item, _currentConfig) != text &&
          controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    _currentConfig = Map.from(widget.initialConfig);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateConfig(String key, dynamic value) {
    setState(() {
      _currentConfig[key] = value;
    });
    widget.onConfigChanged(Map<String, dynamic>.from(_currentConfig));
  }

  void _togglePasswordVisibility(String key) {
    setState(() {
      _passwordVisibility[key] = !(_passwordVisibility[key] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.configItems.map((item) {
        return Padding(
          key: ValueKey(item.key),
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _buildConfigItem(item),
        );
      }).toList(),
    );
  }

  Widget _buildConfigItem(ConfigItem item) {
    switch (item.type) {
      case ConfigItemType.text:
        return TextField(
          decoration: InputDecoration(
            labelText: item.label,
            helperText: item.description,
            border: const OutlineInputBorder(),
          ),
          controller: _controllers[item.key],
          onChanged: (value) => _updateConfig(item.key, value),
        );

      case ConfigItemType.password:
        final isVisible = _passwordVisibility[item.key] ?? false;
        return TextField(
          obscureText: !isVisible,
          decoration: InputDecoration(
            labelText: item.label,
            helperText: item.description,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => _togglePasswordVisibility(item.key),
            ),
          ),
          controller: _controllers[item.key],
          onChanged: (value) => _updateConfig(item.key, value),
        );

      case ConfigItemType.number:
        return TextField(
          decoration: InputDecoration(
            labelText: item.label,
            helperText: item.description,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          controller: _controllers[item.key],
          onChanged: (value) =>
              _updateConfig(item.key, int.tryParse(value) ?? 0),
        );

      case ConfigItemType.range:
        final double min = item.min ?? 0.0;
        final double max = item.max ?? 100.0;
        final double step = item.step ?? 1.0;
        final double currentValue =
            (_currentConfig[item.key] ?? item.defaultValue ?? min).toDouble();
        final String unit = item.unit ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    '${currentValue.round()}$unit',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (item.description != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  item.description!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            Slider(
              value: currentValue.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / step).round(),
              label: '${currentValue.round()}$unit',
              onChanged: (value) {
                _updateConfig(item.key, value.round());
              },
            ),
          ],
        );

      case ConfigItemType.toggle:
        return SwitchListTile(
          title: Text(item.label),
          subtitle: item.description != null ? Text(item.description!) : null,
          value: _currentConfig[item.key] ?? item.defaultValue ?? false,
          onChanged: (value) => _updateConfig(item.key, value),
        );

      case ConfigItemType.select:
        if (item.options == null || item.options!.isEmpty) {
          return const Text('No options');
        }

        final String currentValue = _currentConfig[item.key]?.toString() ??
            item.defaultValue?.toString() ??
            item.options!.first['value']?.toString() ??
            '';

        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: item.label,
            helperText: item.description,
            border: const OutlineInputBorder(),
          ),
          value: currentValue,
          items: item.options!.map((option) {
            return DropdownMenuItem<String>(
              value: option['value'].toString(),
              child: Text(option['label'].toString()),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _updateConfig(item.key, value);
            }
          },
        );

      case ConfigItemType.radio:
        if (item.options == null || item.options!.isEmpty) {
          return const Text('No options');
        }

        final currentValue = _currentConfig[item.key] ?? item.defaultValue;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (item.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(item.description!),
              ),
            ...item.options!.map((option) {
              return RadioListTile<dynamic>(
                title: Text(option['label'].toString()),
                value: option['value'],
                groupValue: currentValue,
                onChanged: (value) => _updateConfig(item.key, value),
              );
            }),
          ],
        );

      case ConfigItemType.checkbox:
        return CheckboxListTile(
          title: Text(item.label),
          subtitle: item.description != null ? Text(item.description!) : null,
          value: _currentConfig[item.key] ?? item.defaultValue ?? false,
          onChanged: (value) {
            if (value != null) {
              _updateConfig(item.key, value);
            }
          },
        );

      case ConfigItemType.tip:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.defaultValue?.toString() ?? '',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (item.link != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28.0, top: 4.0),
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(item.link!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      L10n.of(context).settingsNarrateClickForHelp,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        decoration: TextDecoration.underline,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }
}
