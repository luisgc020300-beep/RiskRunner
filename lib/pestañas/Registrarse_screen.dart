import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// PALETA — Pergamino de Guerra v2
// =============================================================================
const _kBg        = Color(0xFFE8E8ED);
const _kParch     = Color(0xFF1C1C1E);
const _kParchDark = Color(0xFF3C3C43);
const _kInk       = Color(0xFF1C1C1E);
const _kMuted     = Color(0xFF8E8E93);
const _kBorder    = Color(0xFFC6C6C8);
const _kAccent    = Color(0xFFE02020);
const _kAccent2   = Color(0xFF636366);
const _kGold      = Color(0xFFFFD60A);
const _kGoldDim   = Color(0xFFAEAEB2);
const _kSafe      = Color(0xFF4CAF50);
const _kError     = Color(0xFF7A1A0A);

// =============================================================================
// HELPERS TIPOGRÁFICOS
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
// HERO PAINTER — cuadrícula táctica + arcos + scanlines CRT + vignette + pulso
// =============================================================================
class _HeroPainter extends CustomPainter {
  final double pulse;
  const _HeroPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // Fondo
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H),
        Paint()..color = _kBg);

    // Cuadrícula táctica
    final gridPaint = Paint()
      ..color = _kGold.withValues(alpha: 0.07)
      ..strokeWidth = 0.5;
    for (double x = 0; x < W; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, H), gridPaint);
    }
    for (double y = 0; y < H; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(W, y), gridPaint);
    }

    // Scanlines CRT
    final scanPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (double y = 0; y < H; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(W, y), scanPaint);
    }

    // Arco exterior
    canvas.drawCircle(
      Offset(W + 80, -80), 300,
      Paint()
        ..color = _kGold.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40,
    );

    // Arco interior dorado
    canvas.drawCircle(
      Offset(W - 10, 10), 110,
      Paint()
        ..color = _kGold.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Arco inferior izquierdo
    canvas.drawCircle(
      Offset(-60, H + 120), 260,
      Paint()
        ..color = _kAccent.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Meridianos
    canvas.drawLine(Offset(0, H * 0.5), Offset(W, H * 0.5),
        Paint()..color = _kGold.withValues(alpha: 0.05)..strokeWidth = 0.5);
    canvas.drawLine(Offset(W * 0.5, 0), Offset(W * 0.5, H),
        Paint()..color = _kGold.withValues(alpha: 0.05)..strokeWidth = 0.5);

    // Heat line inferior animada
    final heatPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          _kAccent.withValues(alpha: 0.3 + 0.2 * pulse),
          _kGoldDim.withValues(alpha: 0.3 + 0.2 * pulse),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, H - 2, W, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, H - 1), Offset(W, H - 1), heatPaint);

    // Vignette radial
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF000000).withValues(alpha: 0.55),
        ],
        stops: const [0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, W, H));
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), vignette);
  }

  @override
  bool shouldRepaint(_HeroPainter o) => o.pulse != pulse;
}

// =============================================================================
// REGISTER SCREEN
// =============================================================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  // Controladores
  final _nicknameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  // FocusNodes para flujo de teclado
  final _nickFocus    = FocusNode();
  final _emailFocus   = FocusNode();
  final _passFocus    = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  String _error        = '';

  late AnimationController _masterCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _shakeCtrl;

  late Animation<double> _headerReveal;
  late Animation<double> _formReveal;
  late Animation<double> _footerReveal;
  late Animation<double> _pulse;
  late Animation<double> _shakeAnim;

  // Validación en tiempo real
  bool get _nickOk    => _nicknameCtrl.text.trim().length >= 3;
  bool get _emailOk   => RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
      .hasMatch(_emailCtrl.text.trim());
  bool get _passOk    => _passCtrl.text.length >= 6;
  bool get _confirmOk =>
      _passCtrl.text == _confirmCtrl.text && _confirmCtrl.text.isNotEmpty;
  bool get _formOk    => _nickOk && _emailOk && _passOk && _confirmOk;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Animación de entrada escalonada
    _masterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);

    _headerReveal = CurvedAnimation(
        parent: _masterCtrl,
        curve: const Interval(0.00, 0.45, curve: Curves.easeOut));
    _formReveal = CurvedAnimation(
        parent: _masterCtrl,
        curve: const Interval(0.30, 0.80, curve: Curves.easeOut));
    _footerReveal = CurvedAnimation(
        parent: _masterCtrl,
        curve: const Interval(0.65, 1.00, curve: Curves.easeOut));
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

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

    // Limpiar error al escribir en cualquier campo
    for (final ctrl in [_nicknameCtrl, _emailCtrl, _passCtrl, _confirmCtrl]) {
      ctrl.addListener(_clearError);
      ctrl.addListener(() => setState(() {}));
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _masterCtrl.forward();
    });
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _nicknameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nickFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────
  Future<void> _register() async {
    final nick  = _nicknameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;

    if (nick.isEmpty || email.isEmpty || pass.isEmpty) {
      _setError('RELLENA TODOS LOS CAMPOS');
      return;
    }
    if (nick.length < 3) {
      _setError('CALLSIGN MÍNIMO 3 CARACTERES');
      return;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _setError('FORMATO DE EMAIL INVÁLIDO');
      return;
    }
    if (pass.length < 6) {
      _setError('CONTRASEÑA MÍNIMO 6 CARACTERES');
      return;
    }
    if (pass != _confirmCtrl.text) {
      _setError('LAS CONTRASEÑAS NO COINCIDEN');
      return;
    }

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      // Verificar nickname único
      final existing = await FirebaseFirestore.instance
          .collection('players')
          .where('nickname', isEqualTo: nick)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        if (mounted) _setError('ESE CALLSIGN YA ESTÁ EN USO', stopLoading: true);
        return;
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);

      await Future.wait([
        // Actualizar displayName en Firebase Auth
        credential.user!.updateDisplayName(nick),
        // Crear documento del jugador
        FirebaseFirestore.instance
            .collection('players')
            .doc(credential.user!.uid)
            .set({
          'nickname':         nick,
          'email':            email,
          'victorias':        0,
          'nivel':            1,
          'monedas':          100,
          'fecha_registro':   FieldValue.serverTimestamp(),
          'proteccion_hasta': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 7))),
          'liga':             'bronce',
          'puntos_liga':      0,
        }),
      ]);

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'ERROR EN EL REGISTRO';
      if (e.code == 'email-already-in-use') msg = 'ESTE EMAIL YA ESTÁ REGISTRADO';
      if (e.code == 'invalid-email')        msg = 'FORMATO DE EMAIL INVÁLIDO';
      if (e.code == 'weak-password')        msg = 'CONTRASEÑA DEMASIADO DÉBIL';
      _setError(msg, stopLoading: true);
    } catch (_) {
      if (mounted) _setError('ERROR INESPERADO', stopLoading: true);
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

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final heroH   = (screenH * 0.30).clamp(220.0, 320.0);

    return Scaffold(
      backgroundColor: _kParch,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [

            // ── HERO ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: _headerReveal,
                builder: (_, __) => Opacity(
                  opacity: _headerReveal.value.clamp(0.0, 1.0),
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

                        // Botón volver
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 12,
                          left: 24,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(4)),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.12)),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
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
                                  style: _sans(9.5,
                                      Colors.white.withValues(alpha: 0.18),
                                      weight: FontWeight.w600,
                                      spacing: 5.0)),
                              const SizedBox(height: 6),
                              RichText(
                                text: TextSpan(
                                  style: _bebas(34, _kParch, spacing: 1.5),
                                  children: [
                                    const TextSpan(text: 'Únete al\n'),
                                    TextSpan(
                                      text: 'conflicto.',
                                      style: _bebas(34, _kAccent2,
                                          spacing: 1.5),
                                    ),
                                  ],
                                ),
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
                            clipper: const _DiagonalClipper(),
                            child: Container(height: 32, color: _kParch),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── FORMULARIO ────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 48),
              sliver: SliverToBoxAdapter(
                child: AnimatedBuilder(
                  animation: _formReveal,
                  builder: (_, __) => Opacity(
                    opacity: _formReveal.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - _formReveal.value)),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFormIntro(),
                            const SizedBox(height: 20),

                            // Banner de error con shake
                            if (_error.isNotEmpty) ...[
                              AnimatedBuilder(
                                animation: _shakeAnim,
                                builder: (_, child) => Transform.translate(
                                  offset: Offset(_shakeAnim.value, 0),
                                  child: child,
                                ),
                                child: _buildErrorBanner(),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // ── Callsign
                            _buildFieldLabel('Callsign',
                                _nickOk && _nicknameCtrl.text.isNotEmpty),
                            const SizedBox(height: 6),
                            _buildInput(
                              ctrl:            _nicknameCtrl,
                              focus:           _nickFocus,
                              hint:            'Tu nombre de corredor',
                              valid:           _nickOk && _nicknameCtrl.text.isNotEmpty,
                              maxLength:       20,
                              autofillHint:    AutofillHints.username,
                              textInputAction: TextInputAction.next,
                              onSubmitted:     (_) => FocusScope.of(context)
                                  .requestFocus(_emailFocus),
                            ),
                            _buildHint(
                                'Mín. 3 caracteres · Visible para otros jugadores · Único'),
                            const SizedBox(height: 14),

                            // ── Email
                            _buildFieldLabel('Email',
                                _emailOk && _emailCtrl.text.isNotEmpty),
                            const SizedBox(height: 6),
                            _buildInput(
                              ctrl:            _emailCtrl,
                              focus:           _emailFocus,
                              hint:            'tu@email.com',
                              type:            TextInputType.emailAddress,
                              valid:           _emailOk && _emailCtrl.text.isNotEmpty,
                              autofillHint:    AutofillHints.email,
                              textInputAction: TextInputAction.next,
                              onSubmitted:     (_) => FocusScope.of(context)
                                  .requestFocus(_passFocus),
                            ),
                            const SizedBox(height: 14),

                            // ── Contraseña
                            _buildFieldLabel('Contraseña',
                                _passOk && _passCtrl.text.isNotEmpty),
                            const SizedBox(height: 6),
                            _buildInput(
                              ctrl:            _passCtrl,
                              focus:           _passFocus,
                              hint:            'Mínimo 6 caracteres',
                              obscure:         _obscurePass,
                              valid:           _passOk && _passCtrl.text.isNotEmpty,
                              autofillHint:    AutofillHints.newPassword,
                              textInputAction: TextInputAction.next,
                              onSubmitted:     (_) => FocusScope.of(context)
                                  .requestFocus(_confirmFocus),
                              suffix: GestureDetector(
                                onTap: () =>
                                    setState(() => _obscurePass = !_obscurePass),
                                child: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: _kMuted,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Confirmar contraseña
                            _buildFieldLabel('Confirmar contraseña',
                                _confirmOk && _confirmCtrl.text.isNotEmpty),
                            const SizedBox(height: 6),
                            _buildInput(
                              ctrl:            _confirmCtrl,
                              focus:           _confirmFocus,
                              hint:            'Repite la contraseña',
                              obscure:         _obscureConfirm,
                              valid:           _confirmOk && _confirmCtrl.text.isNotEmpty,
                              autofillHint:    AutofillHints.newPassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted:     (_) => _register(),
                              suffix: GestureDetector(
                                onTap: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                                child: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: _kMuted,
                                  size: 18,
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),
                            _buildPrivilegios(),
                            const SizedBox(height: 24),
                            _buildRegisterButton(),

                            AnimatedBuilder(
                              animation: _footerReveal,
                              builder: (_, __) => Opacity(
                                opacity: _footerReveal.value.clamp(0.0, 1.0),
                                child: _buildFooter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
        border: Border.all(
            color: _kAccent.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Center(
        child: Text(
          'RECLU\nTAS\n▲',
          textAlign: TextAlign.center,
          style: _sans(6, _kAccent.withValues(alpha: 0.65),
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
            Text('Crea tu cuenta.',
                style: _sans(18, _kInk, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('Empieza a conquistar desde el minuto uno.',
                style: _sans(11.5, _kMuted,
                    weight: FontWeight.w300, style: FontStyle.italic)),
          ],
        ),
      ],
    ),
  );

  // ── ERROR BANNER ──────────────────────────────────────────────────────────
  Widget _buildErrorBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: const BoxDecoration(
      color: Color(0x14500000),
      border: Border(left: BorderSide(color: _kError, width: 2.5)),
    ),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: _kError, size: 13),
      const SizedBox(width: 8),
      Expanded(
          child: Text(_error,
              style:
                  _sans(10, _kError, weight: FontWeight.w600, spacing: 1.5))),
    ]),
  );

  // ── FIELD LABEL ───────────────────────────────────────────────────────────
  Widget _buildFieldLabel(String text, [bool valid = false]) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        text.toUpperCase(),
        style: _sans(9, valid ? _kSafe : _kMuted,
            weight: FontWeight.w500, spacing: 2.2),
      ),
      if (valid) ...[
        const SizedBox(width: 6),
        const Icon(Icons.check_rounded, color: _kSafe, size: 11),
      ],
    ],
  );

  Widget _buildHint(String text) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Text(text, style: _sans(10, _kMuted, weight: FontWeight.w300)),
  );

  // ── INPUT ─────────────────────────────────────────────────────────────────
  Widget _buildInput({
    required TextEditingController ctrl,
    required FocusNode focus,
    required String hint,
    bool obscure = false,
    bool valid = false,
    TextInputType? type,
    Widget? suffix,
    int? maxLength,
    String? autofillHint,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) =>
      TextField(
        controller:      ctrl,
        focusNode:       focus,
        obscureText:     obscure,
        keyboardType:    type,
        maxLength:       maxLength,
        textInputAction: textInputAction,
        autofillHints:   autofillHint != null ? [autofillHint] : null,
        onSubmitted:     onSubmitted,
        style:       _sans(15, Colors.white),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText:    hint,
          hintStyle:   _sans(15, _kMuted),
          counterText: '',
          filled:      true,
          fillColor:   _kParchDark,
          suffixIcon: suffix != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14), child: suffix)
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(
              color: valid ? _kSafe.withValues(alpha: 0.5) : _kBorder,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(
              color: valid ? _kSafe.withValues(alpha: 0.8) : _kAccent,
              width: 1.5,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );

  // ── PRIVILEGIOS DE FUNDADOR ───────────────────────────────────────────────
  Widget _buildPrivilegios() {
    final items = [
      (
        Icons.shield_outlined,
        const Color(0xFF6C9FD4),
        '7 días de escudo',
        'Tu territorio no puede ser robado al inicio',
      ),
      (
        Icons.monetization_on_outlined,
        _kGold,
        '100 monedas',
        'Para empezar la conquista',
      ),
      (
        Icons.flash_on_outlined,
        _kAccent,
        'Acceso inmediato',
        'Empieza a conquistar desde el minuto uno',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kParch,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        border: Border.all(color: _kBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: _kBorder)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 3, color: _kGold),
                  const SizedBox(width: 10),
                  Text('PRIVILEGIOS DE FUNDADOR',
                      style: _sans(9, _kMuted,
                          weight: FontWeight.w600, spacing: 2.2)),
                ],
              ),
            ),
          ),

          // Items
          ...items.asMap().entries.map((entry) {
            final i      = entry.key;
            final item   = entry.value;
            final isLast = i == items.length - 1;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: isLast
                  ? null
                  : const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: _kBorder, width: 0.8))),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: item.$2.withValues(alpha: 0.1),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(4)),
                      border: Border.all(
                          color: item.$2.withValues(alpha: 0.25), width: 1),
                    ),
                    child: Icon(item.$1, color: item.$2, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$3,
                            style: _sans(12.5, _kInk,
                                weight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(item.$4,
                            style: _sans(10.5, _kMuted,
                                weight: FontWeight.w300)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_outline_rounded,
                      color: _kSafe, size: 16),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── BOTÓN REGISTRARSE ─────────────────────────────────────────────────────
  Widget _buildRegisterButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: _loading ? null : _register,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            _formOk ? _kInk : _kInk.withValues(alpha: 0.35),
        disabledBackgroundColor: _kInk.withValues(alpha: 0.35),
        foregroundColor: _kParch,
        elevation: 0,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4))),
        padding: const EdgeInsets.only(left: 20, right: 8),
      ),
      child: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: _kParch, strokeWidth: 1.8))
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'UNIRSE AL CONFLICTO',
                  style: _bebas(
                    16,
                    _formOk
                        ? _kParch
                        : _kParch.withValues(alpha: 0.4),
                    spacing: 3.0,
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _formOk
                        ? _kAccent
                        : _kAccent.withValues(alpha: 0.3),
                    borderRadius:
                        const BorderRadius.all(Radius.circular(3)),
                  ),
                  child: Icon(
                    Icons.arrow_forward,
                    color: _formOk
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    size: 15,
                  ),
                ),
              ],
            ),
    ),
  );

  // ── FOOTER ────────────────────────────────────────────────────────────────
  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Center(
      child: RichText(
        text: TextSpan(
          style: _sans(12, _kMuted, weight: FontWeight.w300),
          children: [
            const TextSpan(text: '¿Ya tienes cuenta? '),
            WidgetSpan(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text(
                  'Acceder',
                  style:
                      _sans(12, _kAccent, weight: FontWeight.w500).copyWith(
                    decoration:      TextDecoration.underline,
                    decorationColor: _kAccent.withValues(alpha: 0.35),
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
  const _DiagonalClipper();

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
