import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

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
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _logoOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );
    _titleOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.28, 0.52, curve: Curves.easeOut),
    );
    _titleSlide = Tween<double>(begin: 18.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.28, 0.52, curve: Curves.easeOut),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.45, 0.68, curve: Curves.easeOut),
    );
    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.25, 1.0, curve: Curves.easeInOut),
      ),
    );
    _glowOpacity = Tween<double>(begin: 0.0, end: 0.25).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.1, 0.5, curve: Curves.easeOut),
      ),
    );

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
      backgroundColor: const Color(0xFF050F1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Deep radial glow background
          AnimatedBuilder(
            animation: _glowOpacity,
            builder: (_, __) => CustomPaint(
              painter: _SplashBackgroundPainter(_glowOpacity.value),
            ),
          ),

          // Decorative rings
          const _DecorativeRings(),

          // Main content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // Logo container
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: child,
                    ),
                  ),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF188BFF).withValues(alpha: 0.25),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(22),
                    child: SvgPicture.asset(
                      'assets/images/selise_logo_white.svg',
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),

                const Gap(28),

                // App name
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Opacity(
                    opacity: _titleOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _titleSlide.value),
                      child: child,
                    ),
                  ),
                  child: const Text(
                    'Story Automation',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),

                const Gap(8),

                // Tagline
                AnimatedBuilder(
                  animation: _taglineOpacity,
                  builder: (_, child) => Opacity(
                    opacity: _taglineOpacity.value,
                    child: child,
                  ),
                  child: const Text(
                    'Powered by SELISE Digital Platforms',
                    style: TextStyle(
                      color: Color(0x66FFFFFF),
                      fontSize: 12.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // Progress bar
                AnimatedBuilder(
                  animation: _progressValue,
                  builder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              value: _progressValue.value,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.08),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                Color(0xFF188BFF),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Gap(36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────────────────

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
          Color.fromRGBO(24, 139, 255, glowOpacity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_SplashBackgroundPainter old) =>
      old.glowOpacity != glowOpacity;
}

// ── Decorative rings ───────────────────────────────────────────────────────────

class _DecorativeRings extends StatelessWidget {
  const _DecorativeRings();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: _ring(280, Colors.white, 0.04),
        ),
        Positioned(
          top: -60,
          right: -30,
          child: _ring(160, const Color(0xFF188BFF), 0.07),
        ),
        Positioned(
          bottom: -100,
          left: -80,
          child: _ring(260, const Color(0xFF188BFF), 0.05),
        ),
        Positioned(
          bottom: 60,
          right: 20,
          child: _ring(80, Colors.white, 0.04),
        ),
      ],
    );
  }

  Widget _ring(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1,
        ),
      ),
    );
  }
}

