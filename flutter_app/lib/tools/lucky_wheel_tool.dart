import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tool_registry.dart';

/// Lucky wheel window (LuckyWheelTool.svelte): editable options, an animated
/// spin and a draw history. The original's multi-level decision trees are a
/// follow-up; this port covers the single wheel flow.
class LuckyWheelTool extends StatefulWidget {
  const LuckyWheelTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<LuckyWheelTool> createState() => _LuckyWheelToolState();
}

class _LuckyWheelToolState extends State<LuckyWheelTool>
    with SingleTickerProviderStateMixin {
  static const _palette = [
    Color(0xFF2DD4BF),
    Color(0xFF60A5FA),
    Color(0xFFFB923C),
    Color(0xFF4ADE80),
    Color(0xFFF472B6),
    Color(0xFFA78BFA),
    Color(0xFFF87171),
    Color(0xFFFACC15),
  ];

  final TextEditingController _optionsController = TextEditingController(
    text: '奶茶\n咖啡\n果汁\n汽水\n白开水',
  );
  final List<String> _history = [];
  final math.Random _random = math.Random();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  double _startAngle = 0;
  double _endAngle = 0;
  String? _result;

  List<String> get _options => _optionsController.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(24)
      .toList();

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishSpin();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  double get _currentAngle =>
      _startAngle + (_endAngle - _startAngle) * _curve.value;

  void _spin() {
    final options = _options;
    if (options.length < 2 || _controller.isAnimating) return;
    final winnerIndex = _random.nextInt(options.length);
    final sector = 2 * math.pi / options.length;
    // Rotate so the winner's sector center lands under the top pointer
    // (which sits at -pi/2), after at least four extra full turns.
    final winnerCenter = winnerIndex * sector + sector / 2;
    final base = -math.pi / 2 - winnerCenter;
    final current = _currentAngle;
    final minTurns = 4 + _random.nextInt(3);
    var end = base;
    while (end > current - 2 * math.pi * minTurns) {
      end -= 2 * math.pi;
    }
    _startAngle = current;
    _endAngle = end;
    _result = null;
    _controller.forward(from: 0);
    setState(() {});
  }

  void _finishSpin() {
    final options = _options;
    if (options.isEmpty) return;
    final sector = 2 * math.pi / options.length;
    // The pointer sits at -pi/2 (top). Work out which sector is under it.
    final normalized =
        (-math.pi / 2 - _currentAngle) % (2 * math.pi);
    final index =
        (normalized / sector).floor().clamp(0, options.length - 1).toInt();
    final winner = options[index];
    setState(() {
      _result = winner;
      _history.insert(0, winner);
      if (_history.length > 12) _history.removeLast();
    });
    widget.appState.addActivity(
      source: 'SYSTEM',
      title: '幸运大转盘',
      value: '抽中：$winner',
      accent: ToolAccent.purple,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _WheelPainter(
                          options: options,
                          angle: _currentAngle,
                          palette: _palette,
                          textColor: theme.colorScheme.onSurface,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.casino),
                  label: Text(_controller.isAnimating ? '旋转中…' : '开始抽取'),
                  onPressed:
                      options.length < 2 || _controller.isAnimating
                          ? null
                          : _spin,
                ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('结果：$_result',
                        style: theme.textTheme.titleMedium),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选项（每行一个，至少两个）',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: _optionsController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('抽取历史', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                SizedBox(
                  height: 120,
                  child: _history.isEmpty
                      ? Text('暂无记录', style: theme.textTheme.bodySmall)
                      : ListView.builder(
                          itemCount: _history.length,
                          itemBuilder: (context, index) => Text(
                            '${index + 1}. ${_history[index]}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.options,
    required this.angle,
    required this.palette,
    required this.textColor,
  });

  final List<String> options;
  final double angle;
  final List<Color> palette;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;
    if (radius <= 0) return;

    if (options.length < 2) {
      final paint = Paint()..color = palette.first.withOpacity(0.2);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final sector = 2 * math.pi / options.length;
    for (var i = 0; i < options.length; i++) {
      final paint = Paint()..color = palette[i % palette.length];
      final start = angle + i * sector;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sector,
        true,
        paint,
      );

      final labelAngle = start + sector / 2;
      final label = options[i].length > 6
          ? '${options[i].substring(0, 6)}…'
          : options[i];
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelOffset = Offset(
        center.dx + math.cos(labelAngle) * radius * 0.62 - painter.width / 2,
        center.dy + math.sin(labelAngle) * radius * 0.62 - painter.height / 2,
      );
      painter.paint(canvas, labelOffset);
    }

    // Hub and top pointer.
    canvas.drawCircle(center, radius * 0.12,
        Paint()..color = Colors.white.withOpacity(0.9));
    final pointer = Path()
      ..moveTo(center.dx, center.dy - radius - 2)
      ..lineTo(center.dx - 10, center.dy - radius + 18)
      ..lineTo(center.dx + 10, center.dy - radius + 18)
      ..close();
    canvas.drawPath(pointer, Paint()..color = textColor);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.options.join('\n') != options.join('\n');
}
