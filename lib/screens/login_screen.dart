// lib/screens/login_screen.dart — refactored to use SeraTokens / gradients.
// Behaviour is identical to your original; colors & gradients are tokenised.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../theme/sera_tokens.dart';

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
  final _confirmPassCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  final _confirmPassFocus = FocusNode();
  bool _isRegister = false;
  bool _obscure = true;
  bool _confirmObscure = true;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    for (final ctrl in [_nameCtrl, _emailCtrl, _passCtrl, _confirmPassCtrl]) {
      ctrl.addListener(_clearApiError);
    }
  }

  void _clearApiError() {
    if (ref.read(authProvider).error != null) {
      ref.read(authProvider.notifier).clearError();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _confirmPassFocus.dispose();
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
  }

  void _toggleMode() {
    ref.read(authProvider.notifier).clearError();
    _formKey.currentState?.reset();
    _passCtrl.clear();
    _confirmPassCtrl.clear();
    _fadeCtrl.reset();
    setState(() {
      _isRegister = !_isRegister;
      _obscure = true;
      _confirmObscure = true;
    });
    _fadeCtrl.forward();
    final scope = FocusScope.of(context);
    Future.microtask(
        () => scope.requestFocus(_isRegister ? _nameFocus : _emailFocus));
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
                      Text(
                        _isRegister ? 'Create account' : 'Welcome back',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: SeraTokens.fg1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isRegister
                            ? 'Sign up to start automating your stories'
                            : 'Sign in to continue to SERA',
                        style: const TextStyle(
                            fontSize: 14, color: SeraTokens.fg3, height: 1.4),
                      ),
                      const SizedBox(height: 28),
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
                                validator: (v) => v!.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 14),
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
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Required';
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(v)) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              controller: _passCtrl,
                              focusNode: _passFocus,
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscure,
                              helperText:
                                  _isRegister ? 'At least 6 characters' : null,
                              textInputAction: _isRegister
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onFieldSubmitted: (_) => _isRegister
                                  ? FocusScope.of(context)
                                      .requestFocus(_confirmPassFocus)
                                  : _submit(),
                              validator: (v) =>
                                  v!.length < 6 ? 'Min 6 characters' : null,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                  color: SeraTokens.muted,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            if (_isRegister) ...[
                              const SizedBox(height: 14),
                              _Field(
                                controller: _confirmPassCtrl,
                                focusNode: _confirmPassFocus,
                                label: 'Confirm password',
                                icon: Icons.lock_outline_rounded,
                                obscureText: _confirmObscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Required';
                                  if (v != _passCtrl.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _confirmObscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: SeraTokens.muted,
                                  ),
                                  onPressed: () => setState(() =>
                                      _confirmObscure = !_confirmObscure),
                                ),
                              ),
                            ],
                            if (state.error != null) ...[
                              const SizedBox(height: 14),
                              _ErrorBanner(message: state.error!),
                            ],
                            const SizedBox(height: 24),
                            _GradientButton(
                              loading: state.loading,
                              label:
                                  _isRegister ? 'Create Account' : 'Sign In',
                              onPressed: state.loading ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isRegister
                                ? 'Already have an account? '
                                : "Don't have an account? ",
                            style: const TextStyle(
                                color: SeraTokens.fg3, fontSize: 14),
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
                                  color: SeraTokens.primary,
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

// ── Hero header ───────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final Size size;
  const _HeroHeader({required this.size});

  Widget _ring(double s, Color color, double opacity) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: opacity), width: 1),
        ),
      );

  Widget _glowDot(double s, Color color, double opacity) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: opacity * 0.5),
              blurRadius: s * 2,
              spreadRadius: s * 0.5,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size.height * 0.40,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: SeraTokens.heroGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(SeraTokens.rHero),
                bottomRight: Radius.circular(SeraTokens.rHero),
              ),
            ),
          ),
          Positioned(top: -60, right: -50, child: _ring(220, Colors.white, 0.05)),
          Positioned(top: 20, right: 30, child: _ring(100, SeraTokens.primary, 0.15)),
          Positioned(bottom: -80, left: -60, child: _ring(240, SeraTokens.primary, 0.08)),
          Positioned(
              top: size.height * 0.14,
              right: 24,
              child: _glowDot(12, SeraTokens.accent, 0.6)),
          Positioned(
              top: size.height * 0.06,
              left: size.width * 0.45,
              child: _glowDot(6, Colors.white, 0.3)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(SeraTokens.rLg),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: SvgPicture.asset(
                      'assets/images/selise_logo_white.svg',
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'SERA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                            color: SeraTokens.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'BRD · PRD · GitHub — AI does the rest',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
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
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          gradient: onPressed != null ? SeraTokens.buttonGradient : null,
          color: onPressed == null
              ? SeraTokens.primary.withValues(alpha: 0.4)
              : null,
          boxShadow: onPressed != null ? SeraTokens.buttonGlow : null,
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SeraTokens.rLg)),
            padding: EdgeInsets.zero,
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
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
        color: SeraTokens.errorBg,
        borderRadius: BorderRadius.circular(SeraTokens.rMd),
        border: Border.all(color: SeraTokens.errorBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: SeraTokens.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: SeraTokens.errorText, fontSize: 13, height: 1.3),
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
  final String? helperText;

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
    this.helperText,
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
      style: const TextStyle(fontSize: 15, color: SeraTokens.fg1),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19, color: SeraTokens.muted),
        suffixIcon: suffixIcon,
        helperText: helperText,
        helperStyle: const TextStyle(fontSize: 12, color: SeraTokens.muted),
      ),
    );
  }
}
