import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// PALETA — iOS Dark
// =============================================================================
const _kBg     = Color(0xFF1C1C1E);
const _kSurf   = Color(0xFF2C2C2E);
const _kSurf2  = Color(0xFF3A3A3C);
const _kInk    = Color(0xFFFFFFFF);
const _kSub    = Color(0xFFAEAEB2);
const _kMuted  = Color(0xFF8E8E93);
const _kBorder = Color(0xFF48484A);
const _kGreen  = Color(0xFF30D158);
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
      statusBarColor:            Colors.transparent,
      statusBarIconBrightness:   Brightness.light,
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
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
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
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double topPad) => AnimatedBuilder(
    animation: _headerReveal,
    builder: (_, __) => Opacity(
      opacity: _headerReveal.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - _headerReveal.value)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Botón volver
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color:        _kSurf,
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: _kBorder),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _kMuted, size: 14),
                ),
              ),
              const SizedBox(height: 28),
              Text('RISKRUNNER',
                  style: _t(10, _kMuted, weight: FontWeight.w600, spacing: 3)),
              const SizedBox(height: 10),
              Text('Crear cuenta',
                  style: _t(30, _kInk, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Empieza a conquistar tu ciudad.',
                  style: _t(15, _kMuted)),
            ],
          ),
        ),
      ),
    ),
  );

  // ── BODY (formulario) ─────────────────────────────────────────────────────
  Widget _buildBody() => AnimatedBuilder(
    animation: _formReveal,
    builder: (_, __) => Opacity(
      opacity: _formReveal.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - _formReveal.value)),
        child: AutofillGroup(
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
                onSubmitted:     (_) =>
                    FocusScope.of(context).requestFocus(_emailFocus),
              ),
              _buildHint(
                  'Mín. 3 caracteres · Visible para otros jugadores · Único'),
              const SizedBox(height: 20),

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
                onSubmitted:     (_) =>
                    FocusScope.of(context).requestFocus(_passFocus),
              ),
              const SizedBox(height: 20),

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
                onSubmitted:     (_) =>
                    FocusScope.of(context).requestFocus(_confirmFocus),
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
              const SizedBox(height: 20),

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
                  onTap: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  child: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _kMuted, size: 18,
                  ),
                ),
              ),

              const SizedBox(height: 32),
              _buildPerks(),
              const SizedBox(height: 28),
              _buildRegisterButton(),

              AnimatedBuilder(
                animation: _footerReveal,
                builder: (_, __) => Opacity(
                    opacity: _footerReveal.value.clamp(0.0, 1.0),
                    child: _buildFooter()),
              ),
            ],
          ),
        ),
      ),
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

  // ── LABEL + HINT ──────────────────────────────────────────────────────────
  Widget _buildFieldLabel(String label, [bool valid = false]) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label,
          style: _t(13, valid ? _kGreen : _kSub, weight: FontWeight.w500)),
      if (valid) ...[
        const SizedBox(width: 5),
        const Icon(Icons.check_circle_rounded, color: _kGreen, size: 13),
      ],
    ],
  );

  Widget _buildHint(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: _t(11, _kMuted)),
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
        style:           _t(16, _kInk),
        cursorColor:     _kInk,
        decoration: InputDecoration(
          hintText:    hint,
          hintStyle:   _t(16, _kMuted),
          counterText: '',
          filled:      true,
          fillColor:   _kSurf,
          suffixIcon: suffix != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: suffix)
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: valid
                  ? _kGreen.withValues(alpha: 0.55)
                  : _kBorder,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color:  valid ? _kGreen : _kInk.withValues(alpha: 0.60),
              width: 1.5,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );

  // ── PERKS ─────────────────────────────────────────────────────────────────
  Widget _buildPerks() {
    final perks = [
      (Icons.shield_outlined,         const Color(0xFF0A84FF), '7 días de escudo',   'Tu territorio no puede ser robado al inicio'),
      (Icons.toll_outlined,           const Color(0xFFFFD60A), '100 monedas',        'Para empezar la conquista'),
      (Icons.location_on_outlined,    const Color(0xFF30D158), 'Acceso inmediato',   'Empieza a conquistar desde el minuto uno'),
    ];

    return Container(
      decoration: BoxDecoration(
        color:        _kSurf,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              const Icon(Icons.card_giftcard_outlined,
                  color: _kMuted, size: 14),
              const SizedBox(width: 8),
              Text('INCLUIDO AL REGISTRARTE',
                  style: _t(10, _kMuted,
                      weight: FontWeight.w600, spacing: 1.5)),
            ]),
          ),
          Container(height: 0.5, color: _kBorder),

          // Ítems
          ...perks.asMap().entries.map((e) {
            final i    = e.key;
            final p    = e.value;
            final last = i == perks.length - 1;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color:        p.$2.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(p.$1, color: p.$2, size: 17),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.$3,
                          style: _t(14, _kInk, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(p.$4, style: _t(12, _kMuted)),
                    ],
                  )),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_rounded,
                      color: _kGreen, size: 16),
                ]),
              ),
              if (!last) Container(height: 0.5, color: _kBorder),
            ]);
          }),
        ],
      ),
    );
  }

  // ── BOTÓN REGISTRARSE ─────────────────────────────────────────────────────
  Widget _buildRegisterButton() => GestureDetector(
    onTap: (_loading || !_formOk) ? null : () {
      HapticFeedback.mediumImpact();
      _register();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width:  double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: _formOk
            ? _kInk
            : _kSurf2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: _loading
            ? SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  color:       _formOk ? _kBg : _kMuted,
                  strokeWidth: 2,
                ))
            : Text(
                'Crear cuenta',
                style: _t(16,
                    _formOk ? _kBg : _kMuted,
                    weight: FontWeight.w600),
              ),
      ),
    ),
  );

  // ── FOOTER ────────────────────────────────────────────────────────────────
  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Center(
      child: RichText(
        text: TextSpan(
          style: _t(13, _kMuted),
          children: [
            const TextSpan(text: '¿Ya tienes cuenta? '),
            WidgetSpan(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text('Acceder',
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
