// lib/Pestañas/paywall_screen.dart
//
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — Paywall Premium v2
//  Planes: Explorador (2,99€/mes) · Comandante (4,99€/mes) · Anual (39,99€/año)
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import '../services/subscription_service.dart';

// =============================================================================
// PALETA
// =============================================================================
class _C {
  static const bg0     = Color(0xFFE8E8ED);
  static const bg1     = Color(0xFFFFFFFF);
  static const bg2     = Color(0xFFE5E5EA);
  static const parch   = Color(0xFF1C1C1E);
  static const bronze  = Color(0xFF636366);
  static const gold    = Color(0xFFFFD60A);
  static const silver  = Color(0xFFB0BEC5);
  static const border  = Color(0x1FC6C6C8);
  static const t1      = Color(0xFF1C1C1E);
  static const t2      = Color(0xFF3C3C43);
  static const t3      = Color(0xFF636366);
  static const dim     = Color(0xFFAEAEB2);
}

// =============================================================================
// MODELO DE PLAN LOCAL (fallback cuando RevenueCat no está configurado)
// =============================================================================
class _PlanLocal {
  final String id;
  final String titulo;
  final String emoji;
  final String precio;
  final String periodo;
  final String? precioPorMes;
  final String? ahorro;
  final bool esRecomendado;
  final Color accentColor;

  const _PlanLocal({
    required this.id,
    required this.titulo,
    required this.emoji,
    required this.precio,
    required this.periodo,
    this.precioPorMes,
    this.ahorro,
    this.esRecomendado = false,
    required this.accentColor,
  });
}

const _planesLocales = [
  _PlanLocal(
    id: 'monthly_explorer',
    titulo: 'EXPLORADOR',
    emoji: '',
    precio: '2,99€',
    periodo: '/mes',
    esRecomendado: false,
    accentColor: _C.silver,
  ),
  _PlanLocal(
    id: 'monthly_commander',
    titulo: 'COMANDANTE',
    emoji: '',
    precio: '4,99€',
    periodo: '/mes',
    esRecomendado: false,
    accentColor: _C.bronze,
  ),
  _PlanLocal(
    id: 'annual',
    titulo: 'ANUAL',
    emoji: '',
    precio: '39,99€',
    periodo: '/año',
    precioPorMes: '3,33€/mes',
    ahorro: '33% ahorro',
    esRecomendado: true,
    accentColor: _C.gold,
  ),
];

// =============================================================================
// FEATURES POR PLAN
// =============================================================================

// Cada feature: (emoji, nombre, libre, explorador, comandante)
const _features = [
  ('', 'Tracking GPS y conquista',          true,  true,  true),
  ('', 'Desafíos PvP y clanes',             true,  true,  true),
  ('', 'Monedas x2 por carrera',            false, true,  true),
  ('', 'Badge Premium en perfil',           false, true,  true),
  ('', 'Colores neón de ropa',              false, true,  true),
  ('', 'Avatar premium (Afro, Mohicano)',   false, true,  true),
  ('', 'Escudo +7 días al suscribirte',    false, true,  true),
  ('', 'Estilos de mapa exclusivos',       false, false, true),
  ('', 'Radar de operativos (500m)',        false, false, true),
  ('', 'Estadísticas avanzadas',           false, false, true),
  ('', '+2 retos premium diarios',         false, false, true),
  ('', 'Historial completo (200 carreras)',false, false, true),
];

// =============================================================================
// ENTRY POINT
// =============================================================================

class PaywallScreen extends StatefulWidget {
  final String? featureOrigen;

  const PaywallScreen({super.key, this.featureOrigen});

  static Future<bool> mostrar(BuildContext context,
      {String? featureOrigen}) async {
    final result = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: PaywallScreen(featureOrigen: featureOrigen),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen>
    with TickerProviderStateMixin {

  // ── Animaciones ─────────────────────────────────────────────────────────
  late AnimationController _entradaCtrl;
  late AnimationController _crownCtrl;
  late AnimationController _glowCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<double>   _slideAnim;
  late Animation<double>   _crownScale;
  late Animation<double>   _glow;

  // ── Estado ──────────────────────────────────────────────────────────────
  rc.Offerings? _offerings;
  rc.Package?   _selectedPackage;

  // Plan local seleccionado cuando RevenueCat no está disponible
  String _selectedLocalId = 'annual';

  bool _loading    = true;
  bool _purchasing = false;
  String? _errorMsg;

  // Tab de comparativa
  int _tabComparativa = 0; // 0 = features, 1 = comparativa

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _cargarOfferings();
  }

  void _initAnimations() {
    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 60.0, end: 0.0).animate(
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic));

    _crownCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _crownScale = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _crownCtrl, curve: Curves.easeInOut));

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _entradaCtrl.forward();
  }

  Future<void> _cargarOfferings() async {
    final offerings = await SubscriptionService.obtenerOfferings();
    if (!mounted) return;
    setState(() {
      _offerings = offerings;
      _loading   = false;
      if (offerings?.current != null) {
        final packages = offerings!.current!.availablePackages;
        // Seleccionar anual por defecto
        for (final p in packages) {
          if (p.packageType == rc.PackageType.annual) {
            _selectedPackage = p;
            break;
          }
        }
        _selectedPackage ??= packages.isNotEmpty ? packages.first : null;
      }
    });
  }

  // ── Comprar ──────────────────────────────────────────────────────────────

  Future<void> _comprar() async {
    if (_purchasing) return;
    HapticFeedback.mediumImpact();

    // Si RevenueCat está disponible, usar el package seleccionado
    if (_selectedPackage != null) {
      setState(() { _purchasing = true; _errorMsg = null; });
      final result = await SubscriptionService.comprar(_selectedPackage!);
      if (!mounted) return;
      setState(() => _purchasing = false);

      if (result.success) {
        HapticFeedback.heavyImpact();
        await _mostrarExito();
        if (mounted) Navigator.of(context).pop(true);
      } else if (!result.cancelled) {
        setState(() =>
            _errorMsg = 'Error al procesar el pago. Inténtalo de nuevo.');
      }
      return;
    }

    // Fallback: mostrar aviso de configuración pendiente
    setState(() {
      _errorMsg =
          'Los pagos estarán disponibles próximamente. '
          'Contacta con soporte si tienes una suscripción activa.';
    });
  }

  Future<void> _restaurar() async {
    setState(() { _purchasing = true; _errorMsg = null; });
    final status = await SubscriptionService.restaurarCompras();
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (status.isPremium) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() => _errorMsg = 'No se encontraron compras anteriores.');
    }
  }

  Future<void> _mostrarExito() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: _C.bg1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _C.gold, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('¡BIENVENIDO AL MANDO!',
              style: TextStyle(color: _C.gold, fontSize: 18,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text(
              'Has recibido 500  y 7 días de escudo extra como regalo de bienvenida.\n\nTus features premium ya están activas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _C.t2, fontSize: 13, height: 1.6)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.bronze,
                  foregroundColor: _C.bg0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('¡A CONQUISTAR!',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, letterSpacing: 2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _entradaCtrl.dispose();
    _crownCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  // BUILD PRINCIPAL
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg0,
      body: AnimatedBuilder(
        animation: _entradaCtrl,
        builder: (_, child) => Opacity(
          opacity: _fadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value),
            child: child,
          ),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _BgPainter())),
          SafeArea(
            child: Column(children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [
                    const SizedBox(height: 8),
                    _buildHero(),
                    const SizedBox(height: 24),
                    if (widget.featureOrigen != null) _buildFeatureOrigen(),
                    _buildTabSelector(),
                    const SizedBox(height: 16),
                    _tabComparativa == 0
                        ? _buildFeaturesList()
                        : _buildComparativaTable(),
                    const SizedBox(height: 28),
                    if (_loading) _buildLoadingPlans() else _buildPlanes(),
                    const SizedBox(height: 16),
                    if (_errorMsg != null) _buildError(),
                    _buildCTAButton(),
                    const SizedBox(height: 12),
                    _buildFooter(),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _C.t3),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            onPressed: _purchasing ? null : _restaurar,
            child: const Text('Restaurar compras',
              style: TextStyle(color: _C.t3, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Column(children: [
      AnimatedBuilder(
        animation: _crownCtrl,
        builder: (_, __) => Transform.scale(
          scale: _crownScale.value,
          child: AnimatedBuilder(
            animation: _glowCtrl,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: _C.gold.withOpacity(_glow.value * 0.5),
                  blurRadius: 40, spreadRadius: 10,
                )],
              ),
              child: child,
            ),
            child: const Text('', style: TextStyle(fontSize: 64)),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text('RUNNER RISK', style: TextStyle(
        color: _C.parch, fontSize: 12,
        fontWeight: FontWeight.w400, letterSpacing: 6,
      )),
      const SizedBox(height: 4),
      const Text('PREMIUM', style: TextStyle(
        color: _C.gold, fontSize: 30,
        fontWeight: FontWeight.w900, letterSpacing: 3,
      )),
      const SizedBox(height: 8),
      const Text(
        'Domina el mapa. Manda en las ligas.\nSin límites, sin rivales a tu altura.',
        style: TextStyle(color: _C.t2, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center,
      ),
    ]);
  }

  // ── Feature origen ───────────────────────────────────────────────────────

  Widget _buildFeatureOrigen() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _C.bronze.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.bronze.withOpacity(0.35)),
      ),
      child: Row(children: [
        const Text('', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(child: Text(
          '${widget.featureOrigen} es exclusivo de Premium',
          style: const TextStyle(color: _C.parch, fontSize: 13,
              fontWeight: FontWeight.w600),
        )),
      ]),
    );
  }

  // ── Tab selector ─────────────────────────────────────────────────────────

  Widget _buildTabSelector() {
    return Container(
      decoration: BoxDecoration(
        color: _C.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Row(children: [
        _tabBtn('Qué incluye', 0),
        _tabBtn('Comparar planes', 1),
      ]),
    );
  }

  Widget _tabBtn(String label, int idx) {
    final sel = _tabComparativa == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _tabComparativa = idx);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? _C.bronze.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: sel
                ? Border.all(color: _C.bronze.withOpacity(0.5))
                : null,
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: sel ? _C.bronze : _C.t3,
              fontSize: 12,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: 0.5,
            )),
        ),
      ),
    );
  }

  // ── Lista de features ────────────────────────────────────────────────────

  Widget _buildFeaturesList() {
    // Features del plan seleccionado localmente
    final planIdx = _selectedLocalId == 'monthly_explorer'
        ? 0
        : _selectedLocalId == 'monthly_commander'
            ? 1
            : 2; // anual = comandante completo

    return Container(
      decoration: BoxDecoration(
        color: _C.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        children: _features.asMap().entries.map((e) {
          final isLast = e.key == _features.length - 1;
          final (emoji, titulo, libre, explorer, commander) = e.value;

          // Determinar si está incluido en el plan actual
          final incluida = planIdx == 0
              ? explorer
              : commander; // anual y comandante tienen todo

          final inFree = libre;

          return _featureRow(
            emoji: emoji,
            titulo: titulo,
            incluida: incluida,
            inFree: inFree,
            showDivider: !isLast,
          );
        }).toList(),
      ),
    );
  }

  Widget _featureRow({
    required String emoji,
    required String titulo,
    required bool incluida,
    required bool inFree,
    required bool showDivider,
  }) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(titulo, style: TextStyle(
            color: incluida ? _C.t1 : _C.dim,
            fontSize: 13,
            fontWeight: incluida ? FontWeight.w600 : FontWeight.w400,
          ))),
          if (inFree)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('GRATIS',
                style: TextStyle(color: Colors.greenAccent,
                    fontSize: 8, fontWeight: FontWeight.w800)),
            )
          else if (incluida)
            const Icon(Icons.check_circle_rounded, color: _C.gold, size: 18)
          else
            const Icon(Icons.lock_outline_rounded, color: _C.dim, size: 16),
        ]),
      ),
      if (showDivider)
        Divider(height: 1, color: _C.border, indent: 16, endIndent: 16),
    ]);
  }

  // ── Tabla comparativa ────────────────────────────────────────────────────

  Widget _buildComparativaTable() {
    return Container(
      decoration: BoxDecoration(
        color: _C.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            color: _C.bg2,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Expanded(flex: 3, child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Feature',
                style: TextStyle(color: _C.t3, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
            )),
            _headerCell('GRATIS', _C.t3),
            _headerCell('EXPLORADOR\n2,99€/mes', _C.silver),
            _headerCell('COMANDANTE\n4,99€/mes', _C.bronze),
          ]),
        ),
        Divider(height: 1, color: _C.border),
        // Rows
        ..._features.asMap().entries.map((e) {
          final isLast = e.key == _features.length - 1;
          final (emoji, titulo, libre, explorer, commander) = e.value;
          return Column(children: [
            Row(children: [
              Expanded(flex: 3, child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(titulo,
                    style: const TextStyle(color: _C.t2, fontSize: 11))),
                ]),
              )),
              _checkCell(libre, _C.t3),
              _checkCell(explorer, _C.silver),
              _checkCell(commander, _C.gold),
            ]),
            if (!isLast)
              Divider(height: 1, color: _C.border, indent: 12, endIndent: 12),
          ]);
        }),
        // Precios footer
        Container(
          decoration: const BoxDecoration(
            color: _C.bg2,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(children: [
            const Expanded(flex: 3, child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Precio',
                style: TextStyle(color: _C.t3, fontSize: 11,
                    fontWeight: FontWeight.w700)),
            )),
            _precioCell('Gratis', _C.t3),
            _precioCell('2,99€\n/mes', _C.silver),
            _precioCell('4,99€\n/mes', _C.bronze),
          ]),
        ),
      ]),
    );
  }

  Widget _headerCell(String text, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(8),
      child: Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    ));
  }

  Widget _checkCell(bool value, Color color) {
    return Expanded(child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: value
            ? Icon(Icons.check_circle_rounded, color: color, size: 16)
            : Icon(Icons.remove_rounded, color: _C.dim, size: 14),
      ),
    ));
  }

  Widget _precioCell(String text, Color color) {
    return Expanded(child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 11,
            fontWeight: FontWeight.w800, height: 1.3)),
    ));
  }

  // ── Planes ───────────────────────────────────────────────────────────────

  Widget _buildLoadingPlans() {
    return Row(children: List.generate(3, (i) => Expanded(child: Padding(
      padding: EdgeInsets.only(left: i > 0 ? 8 : 0),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: _C.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
        ),
      ),
    ))));
  }

  Widget _buildPlanes() {
    // Si RevenueCat tiene offerings, usar packages reales
    if (_offerings?.current != null &&
        _offerings!.current!.availablePackages.isNotEmpty) {
      return _buildPlanesRevenueCat();
    }
    // Fallback: planes locales con precios hardcoded
    return _buildPlanesLocales();
  }

  Widget _buildPlanesRevenueCat() {
    final packages = _offerings!.current!.availablePackages;
    rc.Package? monthly;
    rc.Package? annual;
    for (final p in packages) {
      if (p.packageType == rc.PackageType.monthly) monthly = p;
      if (p.packageType == rc.PackageType.annual) annual = p;
    }
    // Mostrar los disponibles
    return Row(children: [
      if (monthly != null) ...[
        Expanded(child: _planCardRC(
          package: monthly,
          titulo: 'MENSUAL',
          emoji: '',
          accentColor: _C.bronze,
          esRecomendado: false,
        )),
        const SizedBox(width: 10),
      ],
      if (annual != null)
        Expanded(child: _planCardRC(
          package: annual,
          titulo: 'ANUAL',
          emoji: '',
          accentColor: _C.gold,
          esRecomendado: true,
          savingText:
              '${SubscriptionStatus.annualSavingPercent.toStringAsFixed(0)}% ahorro',
        )),
    ]);
  }

  Widget _buildPlanesLocales() {
    return Column(children: [
      // Fila 1: explorador + comandante
      Row(children: [
        Expanded(child: _planCardLocal(_planesLocales[0])),
        const SizedBox(width: 10),
        Expanded(child: _planCardLocal(_planesLocales[1])),
      ]),
      const SizedBox(height: 10),
      // Fila 2: anual (ancho completo)
      _planCardLocalAnual(_planesLocales[2]),
    ]);
  }

  Widget _planCardLocal(_PlanLocal plan) {
    final sel = _selectedLocalId == plan.id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedLocalId = plan.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel
              ? plan.accentColor.withOpacity(0.10)
              : _C.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? plan.accentColor : _C.border,
            width: sel ? 2 : 1,
          ),
          boxShadow: sel
              ? [BoxShadow(
                  color: plan.accentColor.withOpacity(0.15),
                  blurRadius: 16)]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(plan.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(plan.titulo, style: TextStyle(
            color: sel ? plan.accentColor : _C.t3,
            fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5,
          )),
          const SizedBox(height: 4),
          Text(plan.precio, style: TextStyle(
            color: sel ? _C.t1 : _C.t2,
            fontSize: 22, fontWeight: FontWeight.w900,
          )),
          Text(plan.periodo,
            style: const TextStyle(color: _C.t3, fontSize: 11)),
          if (sel) ...[ const SizedBox(height: 8),
            Icon(Icons.check_circle_rounded,
                color: plan.accentColor, size: 16)],
        ]),
      ),
    );
  }

  Widget _planCardLocalAnual(_PlanLocal plan) {
    final sel = _selectedLocalId == plan.id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedLocalId = plan.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sel
              ? plan.accentColor.withOpacity(0.10)
              : _C.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? plan.accentColor : _C.border,
            width: sel ? 2 : 1,
          ),
          boxShadow: sel
              ? [BoxShadow(
                  color: plan.accentColor.withOpacity(0.2),
                  blurRadius: 20)]
              : null,
        ),
        child: Row(children: [
          Text(plan.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(plan.titulo, style: TextStyle(
                color: sel ? plan.accentColor : _C.t3,
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5,
              )),
              const SizedBox(width: 8),
              if (plan.esRecomendado)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: plan.accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('MEJOR VALOR',
                    style: TextStyle(color: _C.bg0, fontSize: 8,
                        fontWeight: FontWeight.w900)),
                ),
            ]),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(plan.precio, style: TextStyle(
                color: sel ? _C.t1 : _C.t2,
                fontSize: 24, fontWeight: FontWeight.w900,
              )),
              Text(plan.periodo,
                style: const TextStyle(
                    color: _C.t3, fontSize: 12)),
              const SizedBox(width: 8),
              if (plan.precioPorMes != null)
                Text(plan.precioPorMes!,
                  style: TextStyle(
                    color: plan.accentColor,
                    fontSize: 11, fontWeight: FontWeight.w700,
                  )),
            ]),
          ])),
          const SizedBox(width: 8),
          if (plan.ahorro != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: plan.accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: plan.accentColor.withOpacity(0.4)),
              ),
              child: Text(plan.ahorro!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: plan.accentColor,
                  fontSize: 10, fontWeight: FontWeight.w800,
                )),
            ),
        ]),
      ),
    );
  }

  Widget _planCardRC({
    required rc.Package package,
    required String titulo,
    required String emoji,
    required Color accentColor,
    required bool esRecomendado,
    String? savingText,
  }) {
    final sel = _selectedPackage?.identifier == package.identifier;
    final price  = package.storeProduct.priceString;
    final period = package.packageType == rc.PackageType.annual
        ? '/año' : '/mes';
    final perMonth = package.packageType == rc.PackageType.annual
        ? '${(package.storeProduct.price / 12).toStringAsFixed(2)}€/mes'
        : null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedPackage = package);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sel ? accentColor.withOpacity(0.09) : _C.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: sel ? accentColor : _C.border,
              width: sel ? 2 : 1),
          boxShadow: sel
              ? [BoxShadow(
                  color: accentColor.withOpacity(0.15), blurRadius: 16)]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (esRecomendado)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('MEJOR VALOR',
                style: TextStyle(color: _C.bg0, fontSize: 8,
                    fontWeight: FontWeight.w900, letterSpacing: 1)),
            )
          else
            const SizedBox(height: 22),
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(titulo, style: TextStyle(
            color: sel ? accentColor : _C.t3,
            fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5,
          )),
          const SizedBox(height: 4),
          Text(price, style: TextStyle(
            color: sel ? _C.t1 : _C.t2,
            fontSize: 20, fontWeight: FontWeight.w900,
          )),
          Text(period,
            style: const TextStyle(color: _C.t3, fontSize: 11)),
          if (perMonth != null) ...[
            const SizedBox(height: 4),
            Text(perMonth,
              style: TextStyle(color: accentColor, fontSize: 10,
                  fontWeight: FontWeight.w700)),
          ],
          if (savingText != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(savingText,
                style: TextStyle(color: accentColor, fontSize: 9,
                    fontWeight: FontWeight.w800)),
            ),
          ],
          if (sel) ...[
            const SizedBox(height: 10),
            Icon(Icons.check_circle_rounded, color: accentColor, size: 18),
          ],
        ]),
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(_errorMsg!,
          style: const TextStyle(
              color: Colors.redAccent, fontSize: 12))),
      ]),
    );
  }

  // ── CTA Button ───────────────────────────────────────────────────────────

  Widget _buildCTAButton() {
    // Determinar label según plan seleccionado
    String label;
    if (_selectedPackage != null) {
      final isAnnual =
          _selectedPackage!.packageType == rc.PackageType.annual;
      label = isAnnual
          ? 'ACTIVAR ANUAL — ${_selectedPackage!.storeProduct.priceString}'
          : 'ACTIVAR MENSUAL — ${_selectedPackage!.storeProduct.priceString}';
    } else {
      final plan =
          _planesLocales.firstWhere((p) => p.id == _selectedLocalId);
      label =
          'ACTIVAR ${plan.titulo} — ${plan.precio}${plan.periodo}';
    }

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: _C.bronze.withOpacity(_glow.value * 0.4),
            blurRadius: 20, offset: const Offset(0, 6),
          )],
        ),
        child: child,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: _purchasing ? null : _comprar,
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.bronze,
            foregroundColor: _C.bg0,
            disabledBackgroundColor: _C.dim,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _purchasing
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.military_tech_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  )),
                ]),
        ),
      ),
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Column(children: [
      // Beneficios rápidos
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _footerPill(' Sin permanencia'),
        _footerPill(' Cancela cuando quieras'),
        _footerPill(' 500  de bienvenida'),
      ]),
      const SizedBox(height: 12),
      Text(
        'Al suscribirte aceptas los Términos de Servicio y la Política de Privacidad. '
        'La suscripción se renueva automáticamente salvo que la canceles '
        'al menos 24h antes del fin del período actual.',
        style: TextStyle(
            color: _C.t3.withOpacity(0.6), fontSize: 9, height: 1.4),
        textAlign: TextAlign.center,
      ),
    ]);
  }

  Widget _footerPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _C.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.border),
      ),
      child: Text(text,
        style: const TextStyle(
            color: _C.t3, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

// =============================================================================
// PAINTER DE FONDO
// =============================================================================

class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x05CAAA6C)
      ..strokeWidth = 1;

    const spacing = 50.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter, radius: 1.2,
        colors: [const Color(0x15DECA46), Colors.transparent],
      ).createShader(rect));

    final cx = size.width / 2;
    for (final r in [size.width * 0.7, size.width * 0.5, size.width * 0.35]) {
      canvas.drawCircle(Offset(cx, -30), r,
        Paint()
          ..color = const Color(0x08CC7C3A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}