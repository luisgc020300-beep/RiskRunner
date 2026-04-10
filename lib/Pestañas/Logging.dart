import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'Registrarse_screen.dart';

// =============================================================================
// PALETA — Pergamino de Guerra v2 (sincronizada con HTML)
// =============================================================================
const _kBg        = Color(0xFF0F0D08);
const _kBg2       = Color(0xFF161208);
const _kParch     = Color(0xFFF0E8D0);
const _kParchDark = Color(0xFFDDD0B0);
const _kInk       = Color(0xFF0F0D08);
const _kMuted     = Color(0xFF7A6040);
const _kBorder    = Color(0xFFA89060);
const _kAccent    = Color(0xFFE05A1A);
const _kAccent2   = Color(0xFFF07030);
const _kGold      = Color(0xFFD4960A);
const _kGoldDim   = Color(0xFFC8A030);
const _kError     = Color(0xFF7A1A0A);

// =============================================================================
// HELPERS TIPOGRÁFICOS
// — Bebas Neue : titulares hero y botones
// — DM Sans    : labels, inputs, body
// =============================================================================
TextStyle _bebas(double size, Color color, {double spacing = 1.0}) =>
    GoogleFonts.bebasNeue(fontSize: size, color: color, letterSpacing: spacing);

TextStyle _sans(double size, Color color,
    {FontWeight weight = FontWeight.w400,
    double spacing = 0,
    FontStyle style = FontStyle.normal}) =>
    GoogleFonts.dmSans(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: spacing,
      fontStyle: style,
    );

// =============================================================================
// PAINTER — cuadrícula táctica + arcos cartográficos + grain + punto pulsante
// =============================================================================
class _HeroPainter extends CustomPainter {
  final double pulse;
  const _HeroPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // Fondo
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W, H),
      Paint()..color = _kBg,
    );

    // Cuadrícula táctica
    final gridPaint = Paint()
      ..color = _kGold.withOpacity(0.07)
      ..strokeWidth = 0.5;
    for (double x = 0; x < W; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, H), gridPaint);
    }
    for (double y = 0; y < H; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(W, y), gridPaint);
    }

    // Arco cartográfico exterior
    canvas.drawCircle(
      Offset(W + 80, -80),
      300,
      Paint()
        ..color = _kGold.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40,
    );

    // Arco interior dorado
    canvas.drawCircle(
      Offset(W - 10, 10),
      110,
      Paint()
        ..color = _kGold.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Arco inferior izquierdo (naranja sutil)
    canvas.drawCircle(
      Offset(-60, H + 120),
      260,
      Paint()
        ..color = _kAccent.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Meridianos centrales
    canvas.drawLine(Offset(0, H * 0.5), Offset(W, H * 0.5),
        Paint()..color = _kGold.withOpacity(0.05)..strokeWidth = 0.5);
    canvas.drawLine(Offset(W * 0.5, 0), Offset(W * 0.5, H),
        Paint()..color = _kGold.withOpacity(0.05)..strokeWidth = 0.5);

    // Grain
    final rng = math.Random(42);
    final grainPaint = Paint()..color = _kGold.withOpacity(0.018);
    for (int i = 0; i < 300; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * W, rng.nextDouble() * H),
        rng.nextDouble() * 0.7,
        grainPaint,
      );
    }

    // Heat line inferior
    final heatPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          _kAccent.withOpacity(0.5),
          _kGoldDim.withOpacity(0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, H - 2, W, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, H - 1), Offset(W, H - 1), heatPaint);

    // Punto pulsante con anillo
    const px = 24.0;
    const py = 50.0;
    canvas.drawCircle(
      Offset(px, py),
      4 + 18 * pulse,
      Paint()..color = _kAccent.withOpacity(0.15 * (1 - pulse)),
    );
    canvas.drawCircle(
      Offset(px, py),
      4 + 19 * pulse,
      Paint()
        ..color = _kAccent.withOpacity(0.30 * (1 - pulse))
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(Offset(px, py), 4, Paint()..color = _kAccent);
    // Segundo anillo pulsante con delay
    final pulse2 = (pulse + 0.4) % 1.0;
    canvas.drawCircle(
      Offset(px, py),
      4 + 18 * pulse2,
      Paint()..color = _kAccent.withOpacity(0.10 * (1 - pulse2)),
    );
  }

  @override
  bool shouldRepaint(_HeroPainter o) => o.pulse != pulse;
}

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

  bool _obscurePass   = true;
  bool _loading       = false;
  bool _googleLoading = false;
  String _error       = '';
  bool _emailActive   = false;
  bool _passActive    = false;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _entryCtrl;
  late Animation<double>   _entryFade;
  late Animation<Offset>   _entrySlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    _entryFade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
            begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryCtrl.forward();

    _emailFocus.addListener(
        () => setState(() => _emailActive = _emailFocus.hasFocus));
    _passFocus.addListener(
        () => setState(() => _passActive = _passFocus.hasFocus));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      setState(() => _error = 'CREDENCIALES INCOMPLETAS');
      return;
    }
    final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(_emailCtrl.text.trim())) {
      setState(() => _error = 'EMAIL NO VÁLIDO');
      return;
    }
    setState(() {
      _loading = true;
      _error   = '';
    });
    HapticFeedback.heavyImpact();
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException {
      if (mounted)
        setState(() {
          _loading = false;
          _error   = 'ACCESO DENEGADO — CREDENCIALES INVÁLIDAS';
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error   = 'ERROR DE CONEXIÓN';
        });
    }
  }

  Future<void> _signInWithGoogle() async {
    _showSnack('GOOGLE SIGN-IN AÚN NO CONFIGURADO');
  }

  Future<void> _resetPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'INTRODUCE TU EMAIL PRIMERO');
      return;
    }
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (mounted) setState(() => _error = '');
      _showSnack('INSTRUCCIONES DE RECUPERACIÓN ENVIADAS');
    } catch (_) {
      if (mounted) setState(() => _error = 'ERROR AL ENVIAR EL EMAIL');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: _kBg,
          border: Border.all(color: _kGold.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(msg, style: _bebas(13, _kGold, spacing: 2.0)),
      ),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final heroH   = (screenH * 0.46).clamp(260.0, 380.0);

    return Scaffold(
      backgroundColor: _kParch,
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [

              // ── HERO ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroH,
                  child: Stack(
                    children: [
                      // Fondo animado
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => CustomPaint(
                            painter: _HeroPainter(pulse: _pulse.value),
                          ),
                        ),
                      ),

                      // Sello circular
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 14,
                        right: 18,
                        child: _buildStamp(),
                      ),

                      // Status line
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 56,
                        left: 44,
                        child: Text(
                          'FRENTE ACTIVO  ·  48K TROPAS',
                          style: _sans(8.5, Colors.white.withOpacity(0.22),
                              weight: FontWeight.w400, spacing: 1.8),
                        ),
                      ),

                      // Coordenadas — esquina inferior derecha
                      Positioned(
                        bottom: 44,
                        right: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("40°25'N",
                                style: _sans(7, _kParch.withOpacity(0.15),
                                    spacing: 1.0)),
                            Text("3°41'W",
                                style: _sans(7, _kParch.withOpacity(0.15),
                                    spacing: 1.0)),
                          ],
                        ),
                      ),

                      // Territory bar — EN VIVO
                      Positioned(
                        bottom: 38,
                        left: 24,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulse,
                              builder: (_, __) => Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _kAccent.withOpacity(
                                      0.4 + 0.6 * _pulse.value),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('EN VIVO',
                                style: _sans(7.5, _kParch.withOpacity(0.2),
                                    weight: FontWeight.w500, spacing: 1.5)),
                          ],
                        ),
                      ),

                      // Contenido hero
                      Positioned(
                        left: 28,
                        right: 28,
                        bottom: 36,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('RISKRUNNER',
                                style: _sans(9.5, Colors.white.withOpacity(0.18),
                                    weight: FontWeight.w600, spacing: 5.0)),
                            const SizedBox(height: 10),
                            RichText(
                              text: TextSpan(
                                style: _bebas(50, _kParch, spacing: 1.5),
                                children: [
                                  const TextSpan(text: 'Corre.\nConquista.\n'),
                                  TextSpan(
                                    text: 'Domina.',
                                    style: _bebas(50, _kAccent2, spacing: 1.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Traza perímetros. Roba territorio.\nCompite en tu ciudad.',
                              style: _sans(11, _kParch.withOpacity(0.28),
                                  weight: FontWeight.w300,
                                  style: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),

                      // Corte diagonal
                      Positioned(
                        bottom: -1,
                        left: 0,
                        right: 0,
                        child: ClipPath(
                          clipper: _DiagonalClipper(),
                          child: Container(height: 40, color: _kParch),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── FORMULARIO ────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 48),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFormIntro(),
                      const SizedBox(height: 22),
                      _buildForm(),
                      const SizedBox(height: 20),
                      _buildMainButton(),
                      const SizedBox(height: 14),
                      _buildOrDivider(),
                      const SizedBox(height: 14),
                      _buildGoogleButton(),
                      _buildFooter(),
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

  // ── SELLO ─────────────────────────────────────────────────────────────────
  Widget _buildStamp() => Transform.rotate(
    angle: -0.2,
    child: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _kAccent.withOpacity(0.45), width: 1.5),
      ),
      child: Center(
        child: Text(
          'ZONA\nACTIVA\n▲',
          textAlign: TextAlign.center,
          style: _sans(6, _kAccent.withOpacity(0.65),
              weight: FontWeight.w600, spacing: 0.8),
        ),
      ),
    ),
  );

  // ── INTRO FORMULARIO ──────────────────────────────────────────────────────
  Widget _buildFormIntro() => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 3,
          margin: const EdgeInsets.only(right: 12),
          color: _kAccent,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bienvenido de vuelta.',
                style: _sans(18, _kInk, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('Tu territorio te espera.',
                style: _sans(11.5, _kMuted,
                    weight: FontWeight.w300, style: FontStyle.italic)),
          ],
        ),
      ],
    ),
  );

  // ── FORM ──────────────────────────────────────────────────────────────────
  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_error.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _kError.withOpacity(0.08),
            border: Border(left: BorderSide(color: _kError, width: 2.5)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: _kError, size: 13),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error,
                  style: _sans(10, _kError,
                      weight: FontWeight.w600, spacing: 1.5)),
            ),
          ]),
        ),
      ],

      _buildFieldLabel('Email'),
      const SizedBox(height: 6),
      _buildInput(
        ctrl:   _emailCtrl,
        focus:  _emailFocus,
        active: _emailActive,
        hint:   'tu@email.com',
        type:   TextInputType.emailAddress,
      ),
      const SizedBox(height: 14),

      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildFieldLabel('Contraseña'),
          GestureDetector(
            onTap: _resetPassword,
            child: Text('¿Olvidaste tus credenciales?',
                style: _sans(10.5, _kMuted)),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _buildInput(
        ctrl:    _passCtrl,
        focus:   _passFocus,
        active:  _passActive,
        hint:    '••••••••',
        obscure: _obscurePass,
        suffix: GestureDetector(
          onTap: () => setState(() => _obscurePass = !_obscurePass),
          child: Icon(
            _obscurePass
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: _obscurePass ? _kMuted.withOpacity(0.5) : _kInk,
            size: 18,
          ),
        ),
      ),
    ],
  );

  Widget _buildFieldLabel(String text) => Text(
    text.toUpperCase(),
    style: _sans(9, _kMuted, weight: FontWeight.w500, spacing: 2.2),
  );

  Widget _buildInput({
    required TextEditingController ctrl,
    required FocusNode focus,
    required bool active,
    required String hint,
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
  }) =>
      TextField(
        controller:  ctrl,
        focusNode:   focus,
        obscureText: obscure,
        keyboardType: type,
        style: _sans(15, _kInk),
        decoration: InputDecoration(
          hintText:  hint,
          hintStyle: _sans(15, _kBorder),
          filled:    true,
          fillColor: active ? _kParch : _kParchDark,
          suffixIcon: suffix != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14), child: suffix)
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: _kBorder, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: _kInk, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        onSubmitted: (_) => _login(),
      );

  // ── BOTÓN PRINCIPAL ───────────────────────────────────────────────────────
  Widget _buildMainButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: (_loading || _googleLoading) ? null : _login,
      style: ElevatedButton.styleFrom(
        backgroundColor:         _kInk,
        disabledBackgroundColor: _kInk.withOpacity(0.4),
        foregroundColor:         _kParch,
        elevation:               0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.only(left: 20, right: 8),
      ),
      child: _loading
          ? SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: _kParch, strokeWidth: 1.8))
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ACCEDER AL MANDO',
                    style: _bebas(16, _kParch, spacing: 3.0)),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kAccent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 15),
                ),
              ],
            ),
    ),
  );

  // ── DIVIDER ───────────────────────────────────────────────────────────────
  Widget _buildOrDivider() => Row(children: [
    Expanded(
        child: Divider(color: _kBorder.withOpacity(0.5), thickness: 1)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text('o', style: _sans(10, _kMuted, spacing: 1.5)),
    ),
    Expanded(
        child: Divider(color: _kBorder.withOpacity(0.5), thickness: 1)),
  ]);

  // ── BOTÓN GOOGLE ──────────────────────────────────────────────────────────
  Widget _buildGoogleButton() => SizedBox(
    width: double.infinity,
    height: 46,
    child: OutlinedButton(
      onPressed: (_loading || _googleLoading) ? null : _signInWithGoogle,
      style: OutlinedButton.styleFrom(
        side:            BorderSide(color: _kBorder, width: 1.5),
        foregroundColor: _kInk,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: _googleLoading
          ? SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  color: _kAccent, strokeWidth: 1.5))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoogleIcon(),
                const SizedBox(width: 10),
                Text('Continuar con Google',
                    style: _sans(13, _kInk, weight: FontWeight.w400)),
              ],
            ),
    ),
  );

  // ── FOOTER ────────────────────────────────────────────────────────────────
  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Center(
      child: RichText(
        text: TextSpan(
          style: _sans(12, _kMuted, weight: FontWeight.w300),
          children: [
            const TextSpan(text: '¿Sin credenciales? '),
            WidgetSpan(
              child: GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterScreen())),
                child: Text(
                  'Alistarse gratis',
                  style: _sans(12, _kAccent, weight: FontWeight.w500).copyWith(
                    decoration:      TextDecoration.underline,
                    decorationColor: _kAccent.withOpacity(0.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// =============================================================================
// DIAGONAL CLIPPER
// =============================================================================
class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

// =============================================================================
// GOOGLE ICON
// =============================================================================
class _GoogleIcon extends StatelessWidget {
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
          ..cubicTo(17.66 * s, 15.63 * s, 16.88 * s, 16.79 * s, 15.71 * s,
              17.57 * s)
          ..lineTo(15.71 * s, 20.34 * s)
          ..lineTo(19.28 * s, 20.34 * s)
          ..cubicTo(21.36 * s, 18.42 * s, 22.56 * s, 15.60 * s, 22.56 * s,
              12.25 * s)
          ..close(),
        p1);

    canvas.drawPath(
        Path()
          ..moveTo(12 * s, 23 * s)
          ..cubicTo(14.97 * s, 23 * s, 17.46 * s, 22.02 * s, 19.28 * s,
              20.34 * s)
          ..lineTo(15.71 * s, 17.57 * s)
          ..cubicTo(14.73 * s, 18.23 * s, 13.48 * s, 18.63 * s, 12 * s,
              18.63 * s)
          ..cubicTo(9.14 * s, 18.63 * s, 6.71 * s, 16.70 * s, 5.84 * s,
              14.10 * s)
          ..lineTo(2.18 * s, 14.10 * s)
          ..lineTo(2.18 * s, 16.94 * s)
          ..cubicTo(3.99 * s, 20.53 * s, 7.70 * s, 23 * s, 12 * s, 23 * s)
          ..close(),
        p2);

    canvas.drawPath(
        Path()
          ..moveTo(5.84 * s, 14.09 * s)
          ..cubicTo(5.62 * s, 13.43 * s, 5.49 * s, 12.73 * s, 5.49 * s,
              12 * s)
          ..cubicTo(5.49 * s, 11.27 * s, 5.62 * s, 10.57 * s, 5.84 * s,
              9.91 * s)
          ..lineTo(5.84 * s, 7.07 * s)
          ..lineTo(2.18 * s, 7.07 * s)
          ..cubicTo(1.43 * s, 8.55 * s, 1 * s, 10.22 * s, 1 * s, 12 * s)
          ..cubicTo(1 * s, 13.78 * s, 1.43 * s, 15.45 * s, 2.18 * s,
              16.93 * s)
          ..lineTo(5.84 * s, 14.09 * s)
          ..close(),
        p3);

    canvas.drawPath(
        Path()
          ..moveTo(12 * s, 5.38 * s)
          ..cubicTo(13.62 * s, 5.38 * s, 15.06 * s, 5.94 * s, 16.21 * s,
              7.02 * s)
          ..lineTo(19.36 * s, 3.87 * s)
          ..cubicTo(17.45 * s, 2.09 * s, 14.97 * s, 1 * s, 12 * s, 1 * s)
          ..cubicTo(7.70 * s, 1 * s, 3.99 * s, 3.47 * s, 2.18 * s, 7.07 * s)
          ..lineTo(5.84 * s, 9.91 * s)
          ..cubicTo(6.71 * s, 7.31 * s, 9.14 * s, 5.38 * s, 12 * s, 5.38 * s)
          ..close(),
        p4);
  }

  @override
  bool shouldRepaint(_) => false;
}