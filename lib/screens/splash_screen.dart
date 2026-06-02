// lib/screens/splash_screen.dart — refactored to use SeraTokens.
// Animation choreography is identical to your original; only colors are tokenised.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/sera_tokens.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleSlide;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _progressValue;
  late final Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));

    _logoOpacity = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.0, 0.3, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack)));
    _titleOpacity = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.28, 0.52, curve: Curves.easeOut));
    _titleSlide = Tween<double>(begin: 18.0, end: 0.0).animate(CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.28, 0.52, curve: Curves.easeOut)));
    _taglineOpacity = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.45, 0.68, curve: Curves.easeOut));
    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.25, 1.0, curve: Curves.easeInOut)));
    _glowOpacity = Tween<double>(begin: 0.0, end: 0.25).animate(CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.1, 0.5, curve: Curves.easeOut)));

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeraTokens.deepNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _glowOpacity,
            builder: (_, __) => CustomPaint(
              painter: _SplashBackgroundPainter(_glowOpacity.value),
            ),
          ),
          const _DecorativeRings(),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(scale: _logoScale.value, child: child),
                  ),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(SeraTokens.rLogo),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: SeraTokens.primary.withValues(alpha: 0.25),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(22),
                    child: SvgPicture.asset(
                      'assets/images/selise_logo_white.svg',
                      colorFilter:
                          const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Opacity(
                    opacity: _titleOpacity.value,
                    child: Transform.translate(
                        offset: Offset(0, _titleSlide.value), child: child),
                  ),
                  child: const Text(
                    'SERA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _taglineOpacity,
                  builder: (_, child) =>
                      Opacity(opacity: _taglineOpacity.value, child: child),
                  child: Text(
                    'Powered by SELISE Digital Platforms',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _progressValue,
                  builder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 2,
                        child: LinearProgressIndicator(
                          value: _progressValue.value,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              SeraTokens.primary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashBackgroundPainter extends CustomPainter {
  final double glowOpacity;
  _SplashBackgroundPainter(this.glowOpacity);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.8,
        colors: [
          SeraTokens.primary.withValues(alpha: glowOpacity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_SplashBackgroundPainter old) =>
      old.glowOpacity != glowOpacity;
}

class _DecorativeRings extends StatelessWidget {
  const _DecorativeRings();

  Widget _ring(double size, Color color, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: opacity), width: 1),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(top: -120, right: -80, child: _ring(280, Colors.white, 0.04)),
        Positioned(top: -60, right: -30, child: _ring(160, SeraTokens.primary, 0.07)),
        Positioned(bottom: -100, left: -80, child: _ring(260, SeraTokens.primary, 0.05)),
        Positioned(bottom: 60, right: 20, child: _ring(80, Colors.white, 0.04)),
      ],
    );
  }
}
