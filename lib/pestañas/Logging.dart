import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'Home_screen.dart';
import 'Registrarse_screen.dart';

// =============================================================================
// PALETA — iOS Dark (consistente con RegisterScreen)
// =============================================================================
const _kBg     = Color(0xFF1C1C1E);
const _kSurf   = Color(0xFF2C2C2E);
const _kSurf2  = Color(0xFF3A3A3C);
const _kInk    = Color(0xFFFFFFFF);
const _kSub    = Color(0xFFAEAEB2);
const _kMuted  = Color(0xFF8E8E93);
const _kBorder = Color(0xFF48484A);
const _kRed    = Color(0xFFFF453A);

TextStyle _t(double size, Color color,
    {FontWeight weight = FontWeight.w400, double spacing = 0}) =>
    GoogleFonts.dmSans(
      fontSize:      size,
      color:         color,
      fontWeight:    weight,
      letterSpacing: spacing,
    );

// =============================================================================
// LOGIN SCREEN
// =============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus  = FocusNode();

  bool _obscurePass = true;
  bool _loading     = false;
  String _error     = '';
  bool _emailActive = false;
  bool _passActive  = false;

  late AnimationController _entryCtrl;
  late Animation<double>   _entryFade;
  late Animation<Offset>   _entrySlide;
  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Entrada de pantalla
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    _entryFade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
            begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryCtrl.forward();

    // Shake en error
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -7.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: 7.0),   weight: 2),
      TweenSequenceItem(tween: Tween(begin: 7.0, end: 0.0),    weight: 1),
    ]).animate(_shakeCtrl);

    _emailFocus.addListener(
        () => setState(() => _emailActive = _emailFocus.hasFocus));
    _passFocus.addListener(
        () => setState(() => _passActive = _passFocus.hasFocus));

    _emailCtrl.addListener(_clearError);
    _passCtrl.addListener(_clearError);
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _shakeCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      _setError('CREDENCIALES INCOMPLETAS');
      return;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _setError('EMAIL NO VÁLIDO');
      return;
    }
    setState(() {
      _loading = true;
      _error   = '';
    });
    HapticFeedback.heavyImpact();
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: pass);
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException {
      if (mounted) {
        _setError('ACCESO DENEGADO — CREDENCIALES INVÁLIDAS',
            stopLoading: true);
      }
    } catch (_) {
      if (mounted) _setError('ERROR DE CONEXIÓN', stopLoading: true);
    }
  }

  void _setError(String msg, {bool stopLoading = false}) {
    setState(() {
      if (stopLoading) _loading = false;
      _error = msg;
    });
    _shakeCtrl.forward(from: 0);
    HapticFeedback.mediumImpact();
  }

  Future<void> _signInWithGoogle() async {
    _showSnack('Google Sign-In próximamente');
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _setError('INTRODUCE TU EMAIL PRIMERO');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _error = '');
      _showSnack('Instrucciones de recuperación enviadas');
    } catch (_) {
      if (mounted) _setError('ERROR AL ENVIAR EL EMAIL');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:        const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation:       0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color:        _kSurf,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: _kBorder),
        ),
        child: Text(msg, style: _t(13, _kSub, weight: FontWeight.w500)),
      ),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: FadeTransition(
          opacity: _entryFade,
          child: SlideTransition(
            position: _entrySlide,
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(top)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
                  sliver: SliverToBoxAdapter(child: _buildBody()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double topPad) => Padding(
    padding: EdgeInsets.fromLTRB(20, topPad + 60, 20, 48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RISKRUNNER',
            style: _t(10, _kMuted, weight: FontWeight.w600, spacing: 3)),
        const SizedBox(height: 10),
        Text('Bienvenido.',
            style: _t(30, _kInk, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Tu territorio te espera.',
            style: _t(15, _kMuted)),
      ],
    ),
  );

  // ── BODY ──────────────────────────────────────────────────────────────────
  Widget _buildBody() => AutofillGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner de error
        if (_error.isNotEmpty) ...[
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0), child: child),
            child: _buildErrorBanner(),
          ),
          const SizedBox(height: 20),
        ],

        // ── Email
        _buildFieldLabel('Email'),
        const SizedBox(height: 6),
        _buildInput(
          ctrl:            _emailCtrl,
          focus:           _emailFocus,
          active:          _emailActive,
          hint:            'tu@email.com',
          type:            TextInputType.emailAddress,
          autofillHint:    AutofillHints.email,
          textInputAction: TextInputAction.next,
          onSubmitted:     (_) =>
              FocusScope.of(context).requestFocus(_passFocus),
        ),
        const SizedBox(height: 20),

        // ── Contraseña
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildFieldLabel('Contraseña'),
            GestureDetector(
              onTap: _resetPassword,
              child: Text('¿Olvidaste la contraseña?',
                  style: _t(12, _kSub)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildInput(
          ctrl:            _passCtrl,
          focus:           _passFocus,
          active:          _passActive,
          hint:            '••••••••',
          obscure:         _obscurePass,
          autofillHint:    AutofillHints.password,
          textInputAction: TextInputAction.done,
          onSubmitted:     (_) => _login(),
          suffix: GestureDetector(
            onTap: () => setState(() => _obscurePass = !_obscurePass),
            child: Icon(
              _obscurePass
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _kMuted, size: 18,
            ),
          ),
        ),

        const SizedBox(height: 28),
        _buildLoginButton(),
        const SizedBox(height: 16),
        _buildOrDivider(),
        const SizedBox(height: 16),
        _buildGoogleButton(),
        _buildFooter(),
      ],
    ),
  );

  // ── ERROR BANNER ──────────────────────────────────────────────────────────
  Widget _buildErrorBanner() => Container(
    width:   double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color:        _kRed.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border:       Border.all(color: _kRed.withValues(alpha: 0.30)),
    ),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: _kRed, size: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Text(_error,
            style: _t(12, _kRed, weight: FontWeight.w600, spacing: 0.3)),
      ),
    ]),
  );

  // ── LABEL ─────────────────────────────────────────────────────────────────
  Widget _buildFieldLabel(String label) =>
      Text(label, style: _t(13, _kSub, weight: FontWeight.w500));

  // ── INPUT ─────────────────────────────────────────────────────────────────
  Widget _buildInput({
    required TextEditingController ctrl,
    required FocusNode focus,
    required bool active,
    required String hint,
    TextInputType? type,
    bool obscure = false,
    String? autofillHint,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Widget? suffix,
  }) =>
      TextField(
        controller:      ctrl,
        focusNode:       focus,
        obscureText:     obscure,
        keyboardType:    type,
        textInputAction: textInputAction,
        autofillHints:   autofillHint != null ? [autofillHint] : null,
        onSubmitted:     onSubmitted,
        style:           _t(16, _kInk),
        cursorColor:     _kInk,
        decoration: InputDecoration(
          hintText:    hint,
          hintStyle:   _t(16, _kMuted),
          filled:      true,
          fillColor:   active ? _kSurf2 : _kSurf,
          suffixIcon: suffix != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: suffix)
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: _kInk.withValues(alpha: 0.55), width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );

  // ── BOTÓN LOGIN ───────────────────────────────────────────────────────────
  Widget _buildLoginButton() => GestureDetector(
    onTap: _loading ? null : () {
      HapticFeedback.mediumImpact();
      _login();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width:  double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color:        _loading ? _kSurf2 : _kInk,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: _loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: _kMuted, strokeWidth: 2))
            : Text('Acceder',
                style: _t(16, _kBg, weight: FontWeight.w600)),
      ),
    ),
  );

  // ── DIVIDER ───────────────────────────────────────────────────────────────
  Widget _buildOrDivider() => Row(children: [
    const Expanded(child: Divider(color: _kBorder, thickness: 0.5)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text('o', style: _t(12, _kMuted)),
    ),
    const Expanded(child: Divider(color: _kBorder, thickness: 0.5)),
  ]);

  // ── BOTÓN GOOGLE ──────────────────────────────────────────────────────────
  Widget _buildGoogleButton() => GestureDetector(
    onTap: _loading ? null : _signInWithGoogle,
    child: Container(
      width:  double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color:        _kSurf,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _GoogleIcon(),
          const SizedBox(width: 10),
          Text('Continuar con Google',
              style: _t(14, _kSub, weight: FontWeight.w500)),
        ],
      ),
    ),
  );

  // ── FOOTER ────────────────────────────────────────────────────────────────
  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Center(
      child: RichText(
        text: TextSpan(
          style: _t(13, _kMuted),
          children: [
            const TextSpan(text: '¿Sin cuenta? '),
            WidgetSpan(
              child: GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterScreen())),
                child: Text('Registrarse gratis',
                    style: _t(13, _kSub, weight: FontWeight.w600).copyWith(
                      decoration:      TextDecoration.underline,
                      decorationColor: _kBorder,
                    )),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// =============================================================================
// GOOGLE ICON
// =============================================================================
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(16, 16), painter: _GoogleIconPainter());
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s  = size.width / 24;
    final p1 = Paint()..color = const Color(0xFF4285F4);
    final p2 = Paint()..color = const Color(0xFF34A853);
    final p3 = Paint()..color = const Color(0xFFFBBC05);
    final p4 = Paint()..color = const Color(0xFFEA4335);

    canvas.drawPath(
        Path()
          ..moveTo(22.56 * s, 12.25 * s)
          ..lineTo(22.36 * s, 10 * s)
          ..lineTo(12 * s, 10 * s)
          ..lineTo(12 * s, 14.26 * s)
          ..lineTo(17.92 * s, 14.26 * s)
          ..cubicTo(17.66 * s, 15.63 * s, 16.88 * s, 16.79 * s,
              15.71 * s, 17.57 * s)
          ..lineTo(15.71 * s, 20.34 * s)
          ..lineTo(19.28 * s, 20.34 * s)
          ..cubicTo(21.36 * s, 18.42 * s, 22.56 * s, 15.60 * s,
              22.56 * s, 12.25 * s)
          ..close(),
        p1);

    canvas.drawPath(
        Path()
          ..moveTo(12 * s, 23 * s)
          ..cubicTo(14.97 * s, 23 * s, 17.46 * s, 22.02 * s,
              19.28 * s, 20.34 * s)
          ..lineTo(15.71 * s, 17.57 * s)
          ..cubicTo(14.73 * s, 18.23 * s, 13.48 * s, 18.63 * s,
              12 * s, 18.63 * s)
          ..cubicTo(9.14 * s, 18.63 * s, 6.71 * s, 16.70 * s,
              5.84 * s, 14.10 * s)
          ..lineTo(2.18 * s, 14.10 * s)
          ..lineTo(2.18 * s, 16.94 * s)
          ..cubicTo(3.99 * s, 20.53 * s, 7.70 * s, 23 * s, 12 * s,
              23 * s)
          ..close(),
        p2);

    canvas.drawPath(
        Path()
          ..moveTo(5.84 * s, 14.09 * s)
          ..cubicTo(5.62 * s, 13.43 * s, 5.49 * s, 12.73 * s,
              5.49 * s, 12 * s)
          ..cubicTo(5.49 * s, 11.27 * s, 5.62 * s, 10.57 * s,
              5.84 * s, 9.91 * s)
          ..lineTo(5.84 * s, 7.07 * s)
          ..lineTo(2.18 * s, 7.07 * s)
          ..cubicTo(1.43 * s, 8.55 * s, 1 * s, 10.22 * s, 1 * s,
              12 * s)
          ..cubicTo(1 * s, 13.78 * s, 1.43 * s, 15.45 * s, 2.18 * s,
              16.93 * s)
          ..lineTo(5.84 * s, 14.09 * s)
          ..close(),
        p3);

    canvas.drawPath(
        Path()
          ..moveTo(12 * s, 5.38 * s)
          ..cubicTo(13.62 * s, 5.38 * s, 15.06 * s, 5.94 * s,
              16.21 * s, 7.02 * s)
          ..lineTo(19.36 * s, 3.87 * s)
          ..cubicTo(17.45 * s, 2.09 * s, 14.97 * s, 1 * s, 12 * s,
              1 * s)
          ..cubicTo(7.70 * s, 1 * s, 3.99 * s, 3.47 * s, 2.18 * s,
              7.07 * s)
          ..lineTo(5.84 * s, 9.91 * s)
          ..cubicTo(6.71 * s, 7.31 * s, 9.14 * s, 5.38 * s, 12 * s,
              5.38 * s)
          ..close(),
        p4);
  }

  @override
  bool shouldRepaint(_) => false;
}
