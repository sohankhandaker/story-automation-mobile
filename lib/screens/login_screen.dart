import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _isRegister = false;
  bool _obscure = true;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authProvider.notifier);
    if (_isRegister) {
      await auth.register(
          _nameCtrl.text.trim(), _emailCtrl.text.trim(), _passCtrl.text);
    } else {
      await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    }
    // Navigation is handled by _AppRoot reacting to auth state change
  }

  void _toggleMode() {
    ref.read(authProvider.notifier).clearError();
    _formKey.currentState?.reset();
    _passCtrl.clear();
    _fadeCtrl.reset();
    setState(() => _isRegister = !_isRegister);
    _fadeCtrl.forward();
    // Move focus to first field of new mode
    final scope = FocusScope.of(context);
    Future.microtask(() => scope.requestFocus(_isRegister ? _nameFocus : _emailFocus));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: size.height),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroHeader(size: size),
              FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      Text(
                        _isRegister ? 'Create account' : 'Welcome back',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D1B2A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Gap(5),
                      Text(
                        _isRegister
                            ? 'Sign up to start automating your stories'
                            : 'Sign in to continue to Story Automation',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7A8D),
                          height: 1.4,
                        ),
                      ),
                      const Gap(28),

                      // Form
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isRegister) ...[
                              _Field(
                                controller: _nameCtrl,
                                focusNode: _nameFocus,
                                label: 'Full name',
                                icon: Icons.person_outline_rounded,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) => FocusScope.of(context)
                                    .requestFocus(_emailFocus),
                                validator: (v) =>
                                    v!.isEmpty ? 'Required' : null,
                              ),
                              const Gap(14),
                            ],
                            _Field(
                              controller: _emailCtrl,
                              focusNode: _emailFocus,
                              label: 'Email address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => FocusScope.of(context)
                                  .requestFocus(_passFocus),
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                            const Gap(14),
                            _Field(
                              controller: _passCtrl,
                              focusNode: _passFocus,
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) =>
                                  v!.length < 6 ? 'Min 6 characters' : null,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                  color: const Color(0xFF8896A5),
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),

                            // Error
                            if (state.error != null) ...[
                              const Gap(14),
                              _ErrorBanner(message: state.error!),
                            ],

                            const Gap(24),

                            // Submit button
                            _GradientButton(
                              loading: state.loading,
                              label:
                                  _isRegister ? 'Create Account' : 'Sign In',
                              onPressed: state.loading ? null : _submit,
                            ),
                          ],
                        ),
                      ),

                      const Gap(22),

                      // Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isRegister
                                ? 'Already have an account? '
                                : "Don't have an account? ",
                            style: const TextStyle(
                              color: Color(0xFF6B7A8D),
                              fontSize: 14,
                            ),
                          ),
                          InkWell(
                            onTap: _toggleMode,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 14),
                              child: Text(
                                _isRegister ? 'Sign In' : 'Register',
                                style: const TextStyle(
                                  color: kPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero header ────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final Size size;
  const _HeroHeader({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size.height * 0.40,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF04111F),
                  Color(0xFF0A3468),
                  Color(0xFF0D6FD8),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
          ),

          // Decorative rings
          Positioned(
            top: -60,
            right: -50,
            child: _ring(220, Colors.white, 0.05),
          ),
          Positioned(
            top: 20,
            right: 30,
            child: _ring(100, const Color(0xFF188BFF), 0.15),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _ring(240, const Color(0xFF188BFF), 0.08),
          ),
          Positioned(
            top: size.height * 0.14,
            right: 24,
            child: _glowDot(12, const Color(0xFF40A9FF), 0.6),
          ),
          Positioned(
            top: size.height * 0.06,
            left: size.width * 0.45,
            child: _glowDot(6, Colors.white, 0.3),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // SELISE logo
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: SvgPicture.asset(
                      'assets/images/selise_logo_white.svg',
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  const Gap(20),
                  const Text(
                    'Story Automation',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const Gap(6),
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Color(0xFF40A9FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Gap(8),
                      const Text(
                        'BRD · PRD · GitHub — AI does the rest',
                        style: TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 13.5,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

  Widget _glowDot(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity * 0.5),
            blurRadius: size * 2,
            spreadRadius: size * 0.5,
          ),
        ],
      ),
    );
  }
}

// ── Gradient submit button ─────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: onPressed != null
              ? const LinearGradient(
                  colors: [Color(0xFF188BFF), Color(0xFF0A6FE8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: onPressed == null ? kPrimary.withValues(alpha: 0.4) : null,
          boxShadow: onPressed != null
              ? [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: EdgeInsets.zero,
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: Color(0xFFEF4444)),
          const Gap(9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Text field ─────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onFieldSubmitted,
    this.validator,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autocorrect: !obscureText,
      enableSuggestions: !obscureText,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: Color(0xFF0D1B2A)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19, color: const Color(0xFF8896A5)),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
