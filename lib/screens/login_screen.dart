import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../theme/sera_tokens.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;

  Future<void> _loginWithGitHub() async {
    setState(() => _loading = true);
    final platform = kIsWeb ? 'web' : 'mobile';
    final uri = Uri.parse('${AppConstants.baseUrl}/api/auth/github?platform=$platform');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authProvider).error;

    return Scaffold(
      backgroundColor: SeraTokens.deepNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient orb
          Positioned(
            top: -100, left: -100,
            child: Container(
              width: 400, height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  SeraTokens.primary.withValues(alpha: 0.15),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -80, right: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  SeraTokens.accent.withValues(alpha: 0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(SeraTokens.rLogo),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: SeraTokens.primary.withValues(alpha: 0.30),
                        blurRadius: 40, spreadRadius: 4),
                    ],
                  ),
                  padding: const EdgeInsets.all(22),
                  child: SvgPicture.asset(
                    'assets/images/selise_logo_white.svg',
                    colorFilter: const ColorFilter.mode(
                        Colors.white, BlendMode.srcIn),
                  ),
                ),

                const Gap(28),

                // Title
                const Text(
                  'SERA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const Gap(8),
                Text(
                  'SELISE Elicitation & Requirement Agent',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),

                const Spacer(flex: 2),

                // Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(SeraTokens.r2xl),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Sign in to continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const Gap(8),
                        Text(
                          'Use your GitHub account to access SERA.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const Gap(28),

                        // GitHub button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _loginWithGitHub,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1A1A1A),
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(SeraTokens.rLg),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      _GitHubIcon(size: 22),
                                      const Gap(12),
                                      const Text(
                                        'Continue with GitHub',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        if (error != null) ...[
                          const Gap(16),
                          Text(
                            error,
                            style: const TextStyle(
                                color: Color(0xFFFF6B6B), fontSize: 12.5),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Footer
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'Powered by SELISE Digital Platforms',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 11.5,
                      letterSpacing: 0.3,
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

// ── GitHub icon (SVG path) ────────────────────────────────────────────────────

class _GitHubIcon extends StatelessWidget {
  final double size;
  const _GitHubIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: CustomPaint(painter: _GitHubPainter()),
    );
  }
}

class _GitHubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.addOval(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2));
    canvas.drawPath(path, paint..color = const Color(0xFF1A1A1A));

    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    // Simple GitHub mark approximation using a circle + cutout
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.30, iconPaint);
    // Inner cutout
    canvas.drawCircle(center, size.width * 0.18,
        Paint()..color = const Color(0xFF1A1A1A));
    // Bottom tail
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(center.dx + size.width * 0.08,
              center.dy + size.height * 0.22),
          width: size.width * 0.14,
          height: size.height * 0.20),
      iconPaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
