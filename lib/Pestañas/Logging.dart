import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'Registrarse_screen.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kBg      = Color(0xFF060606);
const _kSurface = Color(0xFF0D0D0D);
const _kBorder  = Color(0xFF1A1A1A);
const _kRed     = Color(0xFFCC2222);
const _kRedDim  = Color(0xFF7A1414);
const _kWhite   = Color(0xFFEEEEEE);
const _kGrey    = Color(0xFF888888);
const _kDim     = Color(0xFF333333);

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
  bool _obscurePass = true;
  bool _loading     = false;
  String _error     = '';

  late AnimationController _masterCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _glitchCtrl;

  late Animation<double> _logoReveal;
  late Animation<double> _taglineReveal;
  late Animation<double> _dividerReveal;
  late Animation<double> _formReveal;
  late Animation<double> _footerReveal;
  late Animation<double> _scan;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _masterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _scanCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _glitchCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));

    _logoReveal    = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.00, 0.35, curve: Curves.easeOut));
    _taglineReveal = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.25, 0.55, curve: Curves.easeOut));
    _dividerReveal = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.40, 0.65, curve: Curves.easeOut));
    _formReveal    = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.55, 0.85, curve: Curves.easeOut));
    _footerReveal  = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.75, 1.00, curve: Curves.easeOut));
    _scan  = CurvedAnimation(parent: _scanCtrl,  curve: Curves.linear);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _masterCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _glitchCtrl.repeat(reverse: true);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _glitchCtrl.stop();
        });
      }
    });
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    _scanCtrl.dispose();
    _pulseCtrl.dispose();
    _glitchCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      setState(() => _error = 'CREDENCIALES INCOMPLETAS');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    HapticFeedback.mediumImpact();
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException {
      if (mounted) setState(() { _loading = false; _error = 'ACCESO DENEGADO — CREDENCIALES INVÁLIDAS'; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'ERROR DE CONEXIÓN'; });
    }
  }

  Future<void> _resetPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'INTRODUCE TU EMAIL PRIMERO');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (mounted) setState(() => _error = '');
      _showSnack('EMAIL DE RECUPERACIÓN ENVIADO');
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: _kRed.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: _kRed.withOpacity(0.1), blurRadius: 16)],
        ),
        child: Text(msg, style: GoogleFonts.rajdhani(
            color: _kWhite, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 2)),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [

        // Fondo táctico animado
        Positioned.fill(child: AnimatedBuilder(
          animation: Listenable.merge([_scanCtrl, _pulseCtrl]),
          builder: (_, __) => CustomPaint(
            painter: _TacticalBgPainter(scan: _scan.value, pulse: _pulse.value)),
        )),

        SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: size.height - MediaQuery.of(context).padding.top),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.10),
                    _buildLogo(),
                    SizedBox(height: size.height * 0.05),
                    _buildTagline(),
                    const SizedBox(height: 36),
                    _buildDivider(),
                    const SizedBox(height: 36),
                    _buildForm(),
                    const SizedBox(height: 40),
                    _buildFooter(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLogo() => AnimatedBuilder(
    animation: _logoReveal,
    builder: (_, __) => Opacity(
      opacity: _logoReveal.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 24 * (1 - _logoReveal.value)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icono con pulso
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: _kRed.withOpacity(0.08),
                border: Border.all(
                  color: _kRed.withOpacity(0.3 + 0.2 * _pulse.value), width: 1.5),
              ),
              child: Center(child: Text('⚔',
                style: TextStyle(fontSize: 22,
                  shadows: [Shadow(color: _kRed.withOpacity(0.6), blurRadius: 12)]))),
            ),
          ),
          const SizedBox(height: 20),
          // Logo con efecto glitch
          AnimatedBuilder(
            animation: _glitchCtrl,
            builder: (_, __) {
              final g = _glitchCtrl.value;
              return Stack(children: [
                if (g > 0.5)
                  Transform.translate(
                    offset: const Offset(3, 0),
                    child: _logoText(_kRed.withOpacity(0.3)),
                  ),
                _logoText(_kWhite),
              ]);
            },
          ),
        ]),
      ),
    ),
  );

  Widget _logoText(Color bodyColor) => RichText(
    text: TextSpan(
      style: GoogleFonts.rajdhani(
          fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: -1, height: 0.95),
      children: [
        const TextSpan(text: 'RISK\n', style: TextStyle(color: _kRed)),
        TextSpan(text: 'RUNNER', style: TextStyle(color: bodyColor)),
      ],
    ),
  );

  Widget _buildTagline() => AnimatedBuilder(
    animation: _taglineReveal,
    builder: (_, __) => Opacity(
      opacity: _taglineReveal.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - _taglineReveal.value)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 20, height: 1.5, color: _kRed),
            const SizedBox(width: 10),
            Text('CONQUISTA TU TERRITORIO', style: GoogleFonts.rajdhani(
              color: _kGrey, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 3)),
          ]),
          const SizedBox(height: 8),
          Text('Corre. Invade. Domina.', style: GoogleFonts.rajdhani(
            color: _kWhite.withOpacity(0.45), fontSize: 14,
            fontWeight: FontWeight.w500, letterSpacing: 0.5)),
        ]),
      ),
    ),
  );

  Widget _buildDivider() => AnimatedBuilder(
    animation: _dividerReveal,
    builder: (_, __) => Opacity(
      opacity: _dividerReveal.value.clamp(0.0, 1.0),
      child: Row(children: [
        Expanded(child: Container(height: 1,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [
            Colors.transparent, _kBorder, _kRed.withOpacity(0.4)]))),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: _kBorder), color: _kSurface),
          child: Text('ACCESO', style: GoogleFonts.rajdhani(
            color: _kDim, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 3)),
        ),
        Expanded(child: Container(height: 1,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [
            _kRed.withOpacity(0.4), _kBorder, Colors.transparent])))),
      ]),
    ),
  );

  Widget _buildForm() => AnimatedBuilder(
    animation: _formReveal,
    builder: (_, __) => Opacity(
      opacity: _formReveal.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - _formReveal.value)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Error banner
          if (_error.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kRed.withOpacity(0.06),
                border: Border(left: BorderSide(color: _kRed, width: 2)),
              ),
              child: Text(_error, style: GoogleFonts.rajdhani(
                color: _kRed, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            const SizedBox(height: 20),
          ],

          _fieldLabel('EMAIL / IDENTIFICADOR'),
          const SizedBox(height: 8),
          _buildField(
            controller: _emailCtrl,
            hint: 'tu@email.com',
            keyboardType: TextInputType.emailAddress,
            icon: Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 16),

          _fieldLabel('CONTRASEÑA'),
          const SizedBox(height: 8),
          _buildField(
            controller: _passCtrl,
            hint: '••••••••',
            obscure: _obscurePass,
            icon: Icons.lock_outline_rounded,
            suffix: GestureDetector(
              onTap: () => setState(() => _obscurePass = !_obscurePass),
              child: Icon(
                _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: _kDim, size: 16),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _resetPassword,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text('¿Olvidaste tu contraseña?', style: GoogleFonts.rajdhani(
                  color: _kGrey, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          ),

          const SizedBox(height: 28),
          _buildLoginButton(),
        ]),
      ),
    ),
  );

  Widget _fieldLabel(String text) => Row(children: [
    Container(width: 2, height: 10, color: _kRed),
    const SizedBox(width: 8),
    Text(text, style: GoogleFonts.rajdhani(
      color: _kGrey, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
  ]);

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: GoogleFonts.rajdhani(color: _kWhite, fontSize: 15, fontWeight: FontWeight.w500),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.rajdhani(color: _kDim, fontSize: 14),
      prefixIcon: Icon(icon, color: _kDim, size: 16),
      suffixIcon: suffix,
      filled: true, fillColor: _kSurface,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _kRed.withOpacity(0.6), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    onSubmitted: (_) => _login(),
  );

  Widget _buildLoginButton() => GestureDetector(
    onTap: _loading ? null : _login,
    child: AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: _kRed,
          boxShadow: [BoxShadow(
            color: _kRed.withOpacity(0.15 + 0.1 * _pulse.value),
            blurRadius: 24, offset: const Offset(0, 6))],
        ),
        child: _loading
            ? const Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.login_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 10),
                Text('CONQUISTAR', style: GoogleFonts.rajdhani(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w900, letterSpacing: 3)),
              ]),
      ),
    ),
  );

  Widget _buildFooter() => AnimatedBuilder(
    animation: _footerReveal,
    builder: (_, __) => Opacity(
      opacity: _footerReveal.value.clamp(0.0, 1.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('¿Sin territorio aún?', style: GoogleFonts.rajdhani(
          color: _kGrey, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RegisterScreen())),
          child: Text('RECLUTAR', style: GoogleFonts.rajdhani(
            color: _kRed, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      ]),
    ),
  );
}

// =============================================================================
// PAINTER: fondo táctico con grid de puntos + scan line + glow
// =============================================================================
class _TacticalBgPainter extends CustomPainter {
  final double scan, pulse;
  const _TacticalBgPainter({required this.scan, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid de puntos
    final dot = Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.025);
    const spacing = 28.0;
    for (double x = spacing / 2; x < size.width; x += spacing)
      for (double y = spacing / 2; y < size.height; y += spacing)
        canvas.drawCircle(Offset(x, y), 0.7, dot);

    // Líneas horizontales
    final line = Paint()
      ..color = const Color(0xFFCC2222).withOpacity(0.03)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 56)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);

    // Scan line
    final scanY = size.height * scan;
    canvas.drawRect(
      Rect.fromLTWH(0, scanY - 60, size.width, 60),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent,
          const Color(0xFFCC2222).withOpacity(0.04), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, scanY - 60, size.width, 60)),
    );

    // Glow esquina superior izquierda
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = RadialGradient(
        center: const Alignment(-0.9, -0.85), radius: 0.8,
        colors: [
          const Color(0xFFCC2222).withOpacity(0.06 + 0.02 * pulse),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_TacticalBgPainter old) =>
      old.scan != scan || old.pulse != pulse;
}