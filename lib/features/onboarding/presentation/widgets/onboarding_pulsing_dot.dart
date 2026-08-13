import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';

/// A small accent dot with a glow that breathes on a loop.
///
/// Marks the imminent item in a preview — the next session on the trainer's
/// day, the current streak on the athlete's week. The handoff asks for a soft
/// ~1.8s ease-in-out pulse, explicitly "subtle, not attention-grabbing", so
/// only the ring moves: the dot itself never changes size, which is what
/// keeps it from reading as a notification badge.
///
/// The dot stops when the platform asks for reduced motion. A looping animation
/// is exactly the kind users disable that setting for, and this one carries no
/// information the still frame does not already show.
///
/// ⚠️ Testing: a slide containing this can never be driven with
/// `pumpAndSettle()` — that call waits for every animation to stop, and this one
/// never does. Use `pump(Duration)`, or wrap the subject in a MediaQuery with
/// `disableAnimations: true`.
class OnboardingPulsingDot extends StatefulWidget {
  const OnboardingPulsingDot({super.key, this.size = 8});

  final double size;

  @override
  State<OnboardingPulsingDot> createState() => _OnboardingPulsingDotState();
}

class _OnboardingPulsingDotState extends State<OnboardingPulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  late final Animation<double> _glow = CurvedAnimation(
    parent: _controller,
    // easeInOut in both directions, so the brightest and dimmest points hold
    // for a beat instead of snapping.
    curve: Curves.easeInOut,
    reverseCurve: Curves.easeInOut,
  );

  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWithMotionPreference();
  }

  void _syncWithMotionPreference() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_running) {
        _controller
          ..stop()
          ..value = 0;
        _running = false;
      }
      return;
    }
    if (!_running) {
      _controller.repeat(reverse: true);
      _running = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: palette.accent,
            shape: BoxShape.circle,
            boxShadow: [
              // A ring that expands outward and fades, exactly the shape the
              // handoff specifies: spread 0 → 5 while alpha .55 → 0. Blur stays
              // at zero — a blurred halo reads as a glow, not as a pulse.
              BoxShadow(
                color: palette.accent.withValues(
                  alpha: 0.55 * (1 - _glow.value),
                ),
                spreadRadius: 5 * _glow.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
