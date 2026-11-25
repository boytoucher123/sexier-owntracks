// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A sideways joystick for moving through history.
///
/// Push the knob left (earlier) or right (later): the further you push,
/// the faster you move. Let go and it springs back to the middle and stops.
/// Tapping either side of the knob steps one point.
///
/// Reports the push as -1 (full left) … 0 (centre) … 1 (full right).
class HistoryJoystick extends StatefulWidget {
  const HistoryJoystick({
    super.key,
    required this.color,
    required this.onChanged,
    required this.onStep,
  });

  final Color color;
  final ValueChanged<double> onChanged;

  /// -1 for one point earlier, 1 for one point later.
  final ValueChanged<int> onStep;

  static const double height = 60;
  static const double knob = 52;

  @override
  State<HistoryJoystick> createState() => _HistoryJoystickState();
}

class _HistoryJoystickState extends State<HistoryJoystick> {
  double _value = 0;
  bool _dragging = false;
  double _travel = 1;

  void _set(double v) {
    v = v.clamp(-1.0, 1.0);
    if (v == _value) return;
    setState(() => _value = v);
    widget.onChanged(v);
  }

  void _release() {
    setState(() => _dragging = false);
    _set(0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.color;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        _travel = (w - HistoryJoystick.knob) / 2 - 4;
        final push = _value.abs();
        return Semantics(
          label: 'History joystick',
          hint: 'Drag left for earlier, right for later',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              setState(() => _dragging = true);
              HapticFeedback.lightImpact();
            },
            onHorizontalDragUpdate: (d) => _set(_value + d.delta.dx / _travel),
            onHorizontalDragEnd: (_) => _release(),
            onHorizontalDragCancel: _release,
            onTapUp: (d) {
              HapticFeedback.selectionClick();
              widget.onStep(d.localPosition.dx < w / 2 ? -1 : 1);
            },
            child: SizedBox(
              height: HistoryJoystick.height,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Track, tinted on the side being pushed.
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: cs.onSurface.withOpacity(0.06),
                      gradient: push == 0
                          ? null
                          : LinearGradient(
                              begin: _value < 0
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              end: _value < 0
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              colors: [
                                cs.onSurface.withOpacity(0.06),
                                color.withOpacity(0.12 + 0.3 * push),
                              ],
                            ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    child: _Hint(
                      icon: Icons.fast_rewind_rounded,
                      text: 'Earlier',
                      active: _value < 0,
                      color: color,
                    ),
                  ),
                  Positioned(
                    right: 14,
                    child: _Hint(
                      icon: Icons.fast_forward_rounded,
                      text: 'Later',
                      active: _value > 0,
                      color: color,
                      iconAfter: true,
                    ),
                  ),
                  AnimatedSlide(
                    offset: Offset(_value * _travel / HistoryJoystick.knob, 0),
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: HistoryJoystick.knob,
                      height: HistoryJoystick.knob,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: push > 0 ? color : cs.surface,
                        border: Border.all(
                          color: color.withOpacity(0.35),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Icon(
                          Icons.unfold_more_rounded,
                          size: 26,
                          color: push > 0 ? Colors.white : color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.text,
    required this.active,
    required this.color,
    this.iconAfter = false,
  });

  final IconData icon;
  final String text;
  final bool active;
  final Color color;
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final c = active
        ? color
        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7);
    final i = Icon(icon, size: 18, color: c);
    final t = Text(
      text,
      style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: iconAfter
          ? [t, const SizedBox(width: 4), i]
          : [i, const SizedBox(width: 4), t],
    );
  }
}
