import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../tools/actions.dart';

/// Color picker window (ColorPickerTool.svelte): RGB sliders, HEX input and
/// HEX / RGB / HSL representations with copy actions.
class ColorTool extends StatefulWidget {
  const ColorTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<ColorTool> createState() => _ColorToolState();
}

class _ColorToolState extends State<ColorTool> {
  int _red = 45;
  int _green = 212;
  int _blue = 191;
  final TextEditingController _hexController =
      TextEditingController(text: '#2DD4BF');

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => Color.fromARGB(255, _red, _green, _blue);

  String get _hex =>
      '#${_red.toRadixString(16).padLeft(2, '0')}${_green.toRadixString(16).padLeft(2, '0')}${_blue.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  String get _rgb => 'rgb($_red, $_green, $_blue)';

  String get _hsl {
    final hsl = HSLColor.fromColor(_color);
    final h = hsl.hue.round();
    final s = (hsl.saturation * 100).round();
    final l = (hsl.lightness * 100).round();
    return 'hsl($h, $s%, $l%)';
  }

  void _applyHex(String value) {
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((char) => '$char$char').join();
    }
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return;
    final parsed = int.parse(hex, radix: 16);
    setState(() {
      _red = (parsed >> 16) & 0xff;
      _green = (parsed >> 8) & 0xff;
      _blue = parsed & 0xff;
    });
  }

  Widget _channelSlider(String label, int value, ValueChanged<int> onChanged,
      Color activeColor) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: activeColor,
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }

  Widget _valueRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        title: Text(label, style: theme.textTheme.labelLarge),
        subtitle: SelectableText(value, style: theme.textTheme.bodyMedium),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () async {
            await copyText(value);
            widget.appState.addActivity(
                source: 'TEXT', title: '取色器', value: '$value 已复制');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
                const SizedBox(height: 16),
                _channelSlider('R', _red, (value) {
                  setState(() => _red = value);
                  _hexController.text = _hex;
                }, Colors.redAccent),
                _channelSlider('G', _green, (value) {
                  setState(() => _green = value);
                  _hexController.text = _hex;
                }, Colors.greenAccent),
                _channelSlider('B', _blue, (value) {
                  setState(() => _blue = value);
                  _hexController.text = _hex;
                }, Colors.blueAccent),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: ListView(
              children: [
                TextField(
                  controller: _hexController,
                  decoration: const InputDecoration(
                    labelText: 'HEX',
                    hintText: '#2DD4BF',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: _applyHex,
                  onChanged: (value) {
                    if (RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value.trim())) {
                      _applyHex(value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _valueRow(context, 'HEX', _hex),
                _valueRow(context, 'RGB', _rgb),
                _valueRow(context, 'HSL', _hsl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
