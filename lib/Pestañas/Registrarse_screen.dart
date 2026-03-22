import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// PALETA — idéntica a Logging.dart
// =============================================================================
const _kBg      = Color(0xFF060606);
const _kSurface = Color(0xFF0D0D0D);
const _kBorder  = Color(0xFF1A1A1A);
const _kRed     = Color(0xFFCC2222);
const _kWhite   = Color(0xFFEEEEEE);
const _kGrey    = Color(0xFF888888);
const _kDim     = Color(0xFF333333);
const _kSafe    = Color(0xFF4CAF50);

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

  final _nicknameCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _passCtrl      = TextEditingController();
  final _confirmCtrl   = TextEditingController();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  String _error        = '';

  late AnimationController _masterCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;

  late Animation<double> _headerReveal;
  late Animation<double> _formReveal;
  late Animation<double> _footerReveal;
  late Animation<double> _pulse;
  late Animation<double> _scan;

  // Validación en tiempo real
  bool get _nickOk    => _nicknameCtrl.text.trim().length >= 3;
  bool get _emailOk   => _emailCtrl.text.contains('@') && _emailCtrl.text.contains('.');
  bool get _passOk    => _passCtrl.text.length >= 6;
  bool get _confirmOk => _passCtrl.text == _confirmCtrl.text && _confirmCtrl.text.isNotEmpty;
  bool get _formOk    => _nickOk && _emailOk && _passOk && _confirmOk;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _masterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _scanCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();

    _headerReveal = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.00, 0.45, curve: Curves.easeOut));
    _formReveal   = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.30, 0.80, curve: Curves.easeOut));
    _footerReveal = CurvedAnimation(parent: _masterCtrl, curve: const Interval(0.65, 1.00, curve: Curves.easeOut));
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _scan  = CurvedAnimation(parent: _scanCtrl,  curve: Curves.linear);

    // Escuchar cambios para validación visual
    _nicknameCtrl.addListener(() => setState(() {}));
    _emailCtrl.addListener(()    => setState(() {}));
    _passCtrl.addListener(()     => setState(() {}));
    _confirmCtrl.addListener(()  => setState(() {}));

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _masterCtrl.forward();
    });
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _nicknameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() { _error = ''; });

    if (_nicknameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty ||
        _passCtrl.text.isEmpty) {
      setState(() => _error = 'RELLENA TODOS LOS CAMPOS');
      return;
    }
    if (_nicknameCtrl.text.trim().length < 3) {
      setState(() => _error = 'CALLSIGN MÍNIMO 3 CARACTERES');
      return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'LAS CONTRASEÑAS NO COINCIDEN');
      return;
    }
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'CONTRASEÑA MÍNIMO 6 CARACTERES');
      return;
    }

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('players')
          .doc(credential.user!.uid)
          .set({
        'nickname':         _nicknameCtrl.text.trim(),
        'email':            _emailCtrl.text.trim(),
        'victorias':        0,
        'nivel':            1,
        'monedas':          100,
        'fecha_registro':   FieldValue.serverTimestamp(),
        'proteccion_hasta': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 7))),
        'liga':             'bronce',
        'puntos_liga':      0,
      });

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String msg = 'ERROR EN EL REGISTRO';
      if (e.code == 'email-already-in-use') msg = 'ESTE EMAIL YA ESTÁ REGISTRADO';
      if (e.code == 'invalid-email')        msg = 'FORMATO DE EMAIL INVÁLIDO';
      if (e.code == 'weak-password')        msg = 'CONTRASEÑA DEMASIADO DÉBIL';
      if (mounted) setState(() { _loading = false; _error = msg; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'ERROR INESPERADO'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [

        // Fondo táctico
        Positioned.fill(child: AnimatedBuilder(
          animation: Listenable.merge([_scanCtrl, _pulseCtrl]),
          builder: (_, __) => CustomPaint(
            painter: _RegBgPainter(scan: _scan.value, pulse: _pulse.value)),
        )),

        SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _buildHeader(),
                const SizedBox(height: 32),
                _buildForm(),
                const SizedBox(height: 32),
                _buildFooter(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Header
  Widget _buildHeader() => AnimatedBuilder(
    animation: _headerReveal,
    builder: (_, __) => Opacity(
      opacity: _headerReveal.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - _headerReveal.value)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Botón volver
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  border: Border.all(color: _kBorder), color: _kSurface),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _kGrey, size: 13),
            ),
          ),
          const SizedBox(height: 28),

          // Título
          Row(children: [
            Container(
              width: 4, height: 40,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_kRed, Color(0xFF7A1414)]),
              ),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NUEVO', style: GoogleFonts.rajdhani(
                color: _kGrey, fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 4)),
              Text('RECLUTA', style: GoogleFonts.rajdhani(
                color: _kWhite, fontSize: 32,
                fontWeight: FontWeight.w900, letterSpacing: 2, height: 0.9)),
            ]),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text('DATOS DE COMBATE', style: GoogleFonts.rajdhani(
              color: _kDim, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 3)),
          ),
        ]),
      ),
    ),
  );

  // ── Formulario
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
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: _kRed, size: 13),
                const SizedBox(width: 8),
                Expanded(child: Text(_error, style: GoogleFonts.rajdhani(
                  color: _kRed, fontSize: 10,
                  fontWeight: FontWeight.w900, letterSpacing: 1.5))),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // Nickname
          _fieldLabel('CALLSIGN / NICKNAME', _nickOk && _nicknameCtrl.text.isNotEmpty),
          const SizedBox(height: 8),
          _buildField(
            controller: _nicknameCtrl,
            hint: 'Tu nombre de guerra',
            icon: Icons.terminal_rounded,
            isValid: _nickOk && _nicknameCtrl.text.isNotEmpty,
            maxLength: 20,
          ),
          const SizedBox(height: 6),
          Text('Mínimo 3 caracteres · Visible para otros jugadores',
            style: GoogleFonts.rajdhani(
              color: _kDim, fontSize: 10, fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),

          // Email
          _fieldLabel('EMAIL', _emailOk && _emailCtrl.text.isNotEmpty),
          const SizedBox(height: 8),
          _buildField(
            controller: _emailCtrl,
            hint: 'tu@email.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            isValid: _emailOk && _emailCtrl.text.isNotEmpty,
          ),
          const SizedBox(height: 20),

          // Contraseña
          _fieldLabel('CONTRASEÑA', _passOk && _passCtrl.text.isNotEmpty),
          const SizedBox(height: 8),
          _buildField(
            controller: _passCtrl,
            hint: 'Mínimo 6 caracteres',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePass,
            isValid: _passOk && _passCtrl.text.isNotEmpty,
            suffix: GestureDetector(
              onTap: () => setState(() => _obscurePass = !_obscurePass),
              child: Icon(
                _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: _kDim, size: 16),
            ),
          ),
          const SizedBox(height: 20),

          // Confirmar contraseña
          _fieldLabel('CONFIRMAR CONTRASEÑA', _confirmOk && _confirmCtrl.text.isNotEmpty),
          const SizedBox(height: 8),
          _buildField(
            controller: _confirmCtrl,
            hint: 'Repite la contraseña',
            icon: Icons.lock_reset_outlined,
            obscure: _obscureConfirm,
            isValid: _confirmOk && _confirmCtrl.text.isNotEmpty,
            suffix: GestureDetector(
              onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
              child: Icon(
                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: _kDim, size: 16),
            ),
          ),

          const SizedBox(height: 32),

          // Beneficios del registro
          _buildBeneficios(),

          const SizedBox(height: 28),

          // Botón
          _buildRegisterButton(),
        ]),
      ),
    ),
  );

  Widget _fieldLabel(String text, bool valid) => Row(children: [
    Container(width: 2, height: 10,
        color: valid ? _kSafe : _kRed),
    const SizedBox(width: 8),
    Text(text, style: GoogleFonts.rajdhani(
      color: valid ? _kSafe : _kGrey,
      fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
    if (valid) ...[
      const SizedBox(width: 6),
      const Icon(Icons.check_rounded, color: _kSafe, size: 10),
    ],
  ]);

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isValid = false,
    TextInputType? keyboardType,
    Widget? suffix,
    int? maxLength,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    maxLength: maxLength,
    style: GoogleFonts.rajdhani(color: _kWhite, fontSize: 15, fontWeight: FontWeight.w500),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.rajdhani(color: _kDim, fontSize: 14),
      counterText: '',
      prefixIcon: Icon(icon,
          color: isValid ? _kSafe.withOpacity(0.6) : _kDim, size: 16),
      suffixIcon: suffix,
      filled: true, fillColor: _kSurface,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: isValid ? _kSafe.withOpacity(0.3) : _kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: isValid ? _kSafe.withOpacity(0.6) : _kRed.withOpacity(0.6),
            width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  Widget _buildBeneficios() {
    final items = [
      ('🛡️', '30 días de escudo', 'Tu territorio no puede ser robado al inicio'),
      ('🪙', '100 monedas', 'Para empezar la conquista'),
      ('⚔️', 'Acceso inmediato', 'Empieza a conquistar desde el minuto uno'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder))),
            child: Row(children: [
              Container(width: 2, height: 10, color: _kRed),
              const SizedBox(width: 8),
              Text('PRIVILEGIOS DE FUNDADOR', style: GoogleFonts.rajdhani(
                color: _kGrey, fontSize: 8,
                fontWeight: FontWeight.w900, letterSpacing: 2.5)),
            ]),
          ),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Text(item.$1, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$2, style: GoogleFonts.rajdhani(
                    color: _kWhite, fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(item.$3, style: GoogleFonts.rajdhani(
                    color: _kDim, fontSize: 10, fontWeight: FontWeight.w500)),
                ],
              )),
              const Icon(Icons.check_circle_outline_rounded,
                  color: _kSafe, size: 14),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _buildRegisterButton() => GestureDetector(
    onTap: _loading ? null : _register,
    child: AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: _formOk ? _kRed : _kDim,
          boxShadow: _formOk ? [BoxShadow(
            color: _kRed.withOpacity(0.15 + 0.1 * _pulse.value),
            blurRadius: 24, offset: const Offset(0, 6))
          ] : [],
        ),
        child: _loading
            ? const Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.shield_rounded,
                    color: _formOk ? Colors.white : _kGrey, size: 16),
                const SizedBox(width: 10),
                Text('UNIRSE A LA BATALLA', style: GoogleFonts.rajdhani(
                  color: _formOk ? Colors.white : _kGrey,
                  fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3)),
              ]),
      ),
    ),
  );

  // ── Footer
  Widget _buildFooter() => AnimatedBuilder(
    animation: _footerReveal,
    builder: (_, __) => Opacity(
      opacity: _footerReveal.value.clamp(0.0, 1.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('¿Ya tienes cuenta?', style: GoogleFonts.rajdhani(
          color: _kGrey, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Text('ACCEDER', style: GoogleFonts.rajdhani(
            color: _kRed, fontSize: 13,
            fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      ]),
    ),
  );
}

// =============================================================================
// PAINTER: fondo registro
// =============================================================================
class _RegBgPainter extends CustomPainter {
  final double scan, pulse;
  const _RegBgPainter({required this.scan, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.02);
    const spacing = 28.0;
    for (double x = spacing / 2; x < size.width; x += spacing)
      for (double y = spacing / 2; y < size.height; y += spacing)
        canvas.drawCircle(Offset(x, y), 0.7, dot);

    final scanY = size.height * scan;
    canvas.drawRect(
      Rect.fromLTWH(0, scanY - 40, size.width, 40),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent,
          const Color(0xFFCC2222).withOpacity(0.03), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, scanY - 40, size.width, 40)),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = RadialGradient(
        center: const Alignment(0.9, 0.85), radius: 0.9,
        colors: [
          const Color(0xFFCC2222).withOpacity(0.04 + 0.02 * pulse),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_RegBgPainter old) =>
      old.scan != scan || old.pulse != pulse;
}