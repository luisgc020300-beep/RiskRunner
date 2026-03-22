// lib/Pestañas/coin_shop_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — Tienda de Monedas v2
//  Diseño limpio, minimalista, coherente con la estética de la app.
//
//  PRODUCTOS EN REVENUECAT (configurar cuando vayas a publicar):
//    coins_patrol    → 0,99€  → 150 monedas   Consumable
//    coins_commander → 2,99€  → 500 monedas   Consumable
//    coins_legend    → 7,99€  → 1.500 monedas Consumable
//
//  USO:
//    CoinShopScreen.mostrar(context);
// ══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import '../widgets/custom_navbar.dart';

// =============================================================================
// PALETA
// =============================================================================
class _C {
  static const bg0    = Color(0xFF0A0806);
  static const bg1    = Color(0xFF100D08);
  static const bg2    = Color(0xFF161209);
  static const parch  = Color(0xFFEAD9AA);
  static const bronze = Color(0xFFCC7C3A);
  static const gold   = Color(0xFFDECA46);
  static const silver = Color(0xFFB0BEC5);
  static const border = Color(0xFF2A2010);
  static const border2= Color(0xFF3A2A10);
  static const t1     = Color(0xFFF3EDE1);
  static const t2     = Color(0xFFCAAA6C);
  static const t3     = Color(0xFF8C7242);
  static const dim    = Color(0xFF4A3A20);
  static const dimTxt = Color(0xFF6B5A3A);
  static const green  = Color(0xFF4CAF50);
}

// =============================================================================
// MODELO DE PACK
// =============================================================================
class _Pack {
  final String rcId;
  final String titulo, emoji, precio, descripcion;
  final int monedas;
  final String? etiqueta;
  final Color accent;
  const _Pack({
    required this.rcId, required this.titulo, required this.emoji,
    required this.precio, required this.descripcion,
    required this.monedas, this.etiqueta, required this.accent,
  });
}

const _packs = [
  _Pack(
    rcId: 'coins_patrol', titulo: 'Pack Patrulla',
    emoji: '🪙', precio: '0,99€', monedas: 150,
    descripcion: 'Para un boost puntual o un cambio de color',
    accent: _C.silver,
  ),
  _Pack(
    rcId: 'coins_commander', titulo: 'Pack Comandante',
    emoji: '💰', precio: '2,99€', monedas: 500,
    descripcion: 'Para varias personalizaciones o desbloqueos',
    etiqueta: 'MÁS POPULAR', accent: _C.bronze,
  ),
  _Pack(
    rcId: 'coins_legend', titulo: 'Pack Leyenda',
    emoji: '👑', precio: '7,99€', monedas: 1500,
    descripcion: 'El arsenal completo para dominar el mapa',
    etiqueta: 'MEJOR VALOR', accent: _C.gold,
  ),
];

// =============================================================================
// SCREEN
// =============================================================================
class CoinShopScreen extends StatefulWidget {
  const CoinShopScreen({super.key});

  static Future<void> mostrar(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CoinShopScreen()),
    );
  }

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _glowCtrl;
  late Animation<double>   _glow;

  int     _monedas        = 0;
  bool    _loadingMonedas = true;
  String? _comprando;
  String? _errorMsg;
  String? _successMsg;

  Map<String, rc.StoreProduct> _rcProducts = {};
  bool _rcDisponible = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _cargarMonedas();
    _cargarProductosRC();
  }

  Future<void> _cargarMonedas() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(uid).get();
      if (mounted) setState(() {
        _monedas = (doc.data()?['monedas'] as num?)?.toInt() ?? 0;
        _loadingMonedas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMonedas = false);
    }
  }

  Future<void> _cargarProductosRC() async {
    try {
      final ids = _packs.map((p) => p.rcId).toList();
      final products = await rc.Purchases.getProducts(ids,
          productCategory: rc.ProductCategory.nonSubscription);
      if (mounted && products.isNotEmpty) {
        setState(() {
          _rcProducts   = {for (final p in products) p.identifier: p};
          _rcDisponible = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _comprar(_Pack pack) async {
    if (_comprando != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _comprando  = pack.rcId;
      _errorMsg   = null;
      _successMsg = null;
    });

    if (_rcDisponible && _rcProducts.containsKey(pack.rcId)) {
      try {
        final product = _rcProducts[pack.rcId]!;
        final result  = await rc.Purchases.purchaseStoreProduct(product);
        final ok = result.customerInfo.nonSubscriptionTransactions
            .any((t) => t.productIdentifier == pack.rcId);
        if (ok) {
          await _darMonedas(pack.monedas, pack.titulo);
          if (mounted) {
            HapticFeedback.heavyImpact();
            setState(() {
              _comprando  = null;
              _successMsg = '¡${pack.monedas} monedas añadidas! 🪙';
              _monedas   += pack.monedas;
            });
          }
        } else {
          if (mounted) setState(() {
            _comprando = null;
            _errorMsg  = 'No se pudo verificar la compra. '
                'Contacta con soporte si te han cobrado.';
          });
        }
      } on Exception catch (e) {
        if (mounted) setState(() {
          _comprando = null;
          final msg = e.toString().toLowerCase();
          if (!msg.contains('cancel') && !msg.contains('user')) {
            _errorMsg = 'Error al procesar el pago. Inténtalo de nuevo.';
          }
        });
      }
      return;
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() {
      _comprando = null;
      _errorMsg  = 'Las compras estarán disponibles cuando la app '
          'esté publicada en la tienda.';
    });
  }

  Future<void> _darMonedas(int cantidad, String motivo) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final db = FirebaseFirestore.instance;
    await db.collection('players').doc(uid)
        .update({'monedas': FieldValue.increment(cantidad)});
    await db.collection('notifications').add({
      'toUserId':  uid,
      'type':      'coins_purchased',
      'message':   '🪙 ¡Recibiste $cantidad monedas de "$motivo"!',
      'read':      false,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await db.collection('coin_purchases').add({
      'userId':    uid,
      'cantidad':  cantidad,
      'motivo':    motivo,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg0,
      appBar: _appBar(),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _BgPainter())),
        SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            child: Column(children: [
              const SizedBox(height: 14),
              _balanceCard(),
              const SizedBox(height: 26),
              _sectionLabel('ELIGE TU ARSENAL'),
              const SizedBox(height: 12),
              ..._packs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _packCard(p),
              )),
              if (_errorMsg != null) ...[
                const SizedBox(height: 4),
                _banner(_errorMsg!, isError: true),
              ],
              if (_successMsg != null) ...[
                const SizedBox(height: 4),
                _banner(_successMsg!, isError: false),
              ],
              const SizedBox(height: 26),
              _paraQueSection(),
              const SizedBox(height: 20),
              _footerPills(),
              const SizedBox(height: 8),
              Text(
                'Compras únicas y permanentes. '
                'Las monedas son solo para personalización — '
                'no afectan a la conquista de territorios.',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                    color: _C.dimTxt.withOpacity(0.6),
                    fontSize: 10, height: 1.5)),
            ]),
          ),
        ),
      ]),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 4),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: _C.bg0,
    elevation: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back_ios_new_rounded,
          color: _C.t2, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    title: Text('TIENDA DE MONEDAS',
      style: GoogleFonts.rajdhani(
        color: _C.parch, fontSize: 14,
        fontWeight: FontWeight.w900, letterSpacing: 3)),
    actions: [
      IconButton(
        icon: Icon(Icons.help_outline_rounded,
            color: _C.dimTxt, size: 20),
        onPressed: _mostrarAyuda,
      ),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: _C.border),
    ),
  );

  // ── Balance card ─────────────────────────────────────────────────────────
  Widget _balanceCard() => AnimatedBuilder(
    animation: _glow,
    builder: (_, child) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _C.gold.withOpacity(0.2 + _glow.value * 0.15),
        ),
      ),
      child: child,
    ),
    child: Row(children: [
      // Icono moneda grande
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: _C.gold.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(color: _C.gold.withOpacity(0.25)),
        ),
        child: const Center(
          child: Text('🪙', style: TextStyle(fontSize: 24))),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TUS MONEDAS', style: GoogleFonts.rajdhani(
          color: _C.dimTxt, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 2)),
        const SizedBox(height: 3),
        _loadingMonedas
            ? Container(
                width: 64, height: 26,
                decoration: BoxDecoration(
                  color: _C.bg2,
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            : Text('$_monedas', style: GoogleFonts.rajdhani(
                color: _C.gold, fontSize: 28,
                fontWeight: FontWeight.w900, height: 1)),
      ]),
      const Spacer(),
      // Indicador estado tienda
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _rcDisponible
              ? _C.green.withOpacity(0.08)
              : _C.dim.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _rcDisponible
                ? _C.green.withOpacity(0.3)
                : _C.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _rcDisponible ? _C.green : _C.dimTxt,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _rcDisponible ? 'Activa' : 'Próximamente',
            style: GoogleFonts.rajdhani(
              color: _rcDisponible ? _C.green : _C.dimTxt,
              fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]),
  );

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Row(children: [
    Container(
      width: 3, height: 14,
      decoration: BoxDecoration(
        color: _C.bronze,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
    const SizedBox(width: 10),
    Text(text, style: GoogleFonts.rajdhani(
      color: _C.dimTxt, fontSize: 10,
      fontWeight: FontWeight.w700, letterSpacing: 2)),
  ]);

  // ── Pack card ─────────────────────────────────────────────────────────────
  Widget _packCard(_Pack pack) {
    final estaComprando = _comprando == pack.rcId;
    final precioMostrado = _rcDisponible &&
            _rcProducts.containsKey(pack.rcId)
        ? _rcProducts[pack.rcId]!.priceString
        : pack.precio;

    return Container(
      decoration: BoxDecoration(
        color: _C.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pack.accent.withOpacity(0.3)),
      ),
      child: Column(children: [
        // Etiqueta si existe
        if (pack.etiqueta != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: pack.accent,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15)),
            ),
            child: Text(pack.etiqueta!,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                color: _C.bg0, fontSize: 10,
                fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Emoji + monedas
            Column(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: pack.accent.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: pack.accent.withOpacity(0.25)),
                ),
                child: Center(child: Text(pack.emoji,
                    style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pack.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: pack.accent.withOpacity(0.3)),
                ),
                child: Text(
                  _fmtCoins(pack.monedas),
                  style: GoogleFonts.rajdhani(
                    color: pack.accent, fontSize: 11,
                    fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(width: 14),

            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(pack.titulo, style: GoogleFonts.rajdhani(
                color: _C.t1, fontSize: 15,
                fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(pack.descripcion, style: GoogleFonts.rajdhani(
                  color: _C.dimTxt, fontSize: 12, height: 1.3)),
            ])),

            const SizedBox(width: 12),

            // Precio + botón
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
              Text(precioMostrado, style: GoogleFonts.rajdhani(
                color: pack.accent, fontSize: 20,
                fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _buyBtn(pack, estaComprando),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buyBtn(_Pack pack, bool comprando) {
    final bloqueado = _comprando != null && !comprando;
    return GestureDetector(
      onTap: bloqueado || comprando ? null : () => _comprar(pack),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: bloqueado
              ? _C.dim
              : comprando
                  ? pack.accent.withOpacity(0.5)
                  : pack.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: comprando
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text('COMPRAR', style: GoogleFonts.rajdhani(
                color: _C.bg0, fontSize: 11,
                fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
    );
  }

  // ── Banner ────────────────────────────────────────────────────────────────
  Widget _banner(String msg, {required bool isError}) {
    final color = isError ? Colors.redAccent : _C.green;
    final icon  = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: GoogleFonts.rajdhani(
            color: color, fontSize: 12, height: 1.4))),
        GestureDetector(
          onTap: () => setState(() {
            _errorMsg = null;
            _successMsg = null;
          }),
          child: Icon(Icons.close_rounded, color: color, size: 14),
        ),
      ]),
    );
  }

  // ── Para qué sirven ───────────────────────────────────────────────────────
  Widget _paraQueSection() {
    final usos = [
      ('🎨', 'Personalizar tu avatar',
          'Peinados, colores neón, opciones exclusivas'),
      ('🛡️', 'Escudos de territorio',
          'Protege tus zonas días extra'),
      ('⚡', 'Boost de XP puntual',
          'Multiplica tus puntos en una carrera'),
      ('💰', 'Apuestas en desafíos',
          'Sube la apuesta en tus duelos PvP'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      _sectionLabel('¿PARA QUÉ SIRVEN?'),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: _C.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        child: Column(
          children: usos.asMap().entries.map((e) {
            final isLast = e.key == usos.length - 1;
            final (emoji, titulo, sub) = e.value;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _C.bronze.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _C.bronze.withOpacity(0.2)),
                    ),
                    child: Center(child: Text(emoji,
                        style: const TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(titulo, style: GoogleFonts.rajdhani(
                      color: _C.t1, fontSize: 13,
                      fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text(sub, style: GoogleFonts.rajdhani(
                        color: _C.dimTxt, fontSize: 11)),
                  ])),
                ]),
              ),
              if (!isLast)
                Divider(height: 1, color: _C.border,
                    indent: 14, endIndent: 14),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  // ── Footer pills ──────────────────────────────────────────────────────────
  Widget _footerPills() => Wrap(
    spacing: 6, runSpacing: 6,
    alignment: WrapAlignment.center,
    children: [
      _pill('Pago único'),
      _pill('No caducan'),
      _pill('Solo cosméticos'),
      _pill('Sin pay-to-win'),
    ],
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: _C.bg2,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.border),
    ),
    child: Text(text, style: GoogleFonts.rajdhani(
        color: _C.dimTxt, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  // ── Ayuda ─────────────────────────────────────────────────────────────────
  void _mostrarAyuda() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.bg1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: _C.dim,
              borderRadius: BorderRadius.circular(2),
            )),
          const SizedBox(height: 20),
          Text('Preguntas frecuentes',
            style: GoogleFonts.rajdhani(
              color: _C.t1, fontSize: 15,
              fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 18),
          _faq('¿Las monedas caducan?',
              'No. Son tuyas para siempre, sin fecha de expiración.'),
          _faq('¿Dan ventaja en el juego?',
              'No. Solo sirven para personalización — avatares, colores, '
              'escudos cosméticos. La conquista depende únicamente de cuánto corres.'),
          _faq('¿Las recupero si cambio de móvil?',
              'Sí. Están vinculadas a tu cuenta. '
              'Si inicias sesión en otro dispositivo, siguen ahí.'),
          _faq('¿Son lo mismo que Premium?',
              'No. Premium es una suscripción mensual que desbloquea features '
              'permanentes. Las monedas son compras puntuales para cosméticos.'),
        ]),
      ),
    );
  }

  Widget _faq(String q, String a) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      Text(q, style: GoogleFonts.rajdhani(
        color: _C.bronze, fontSize: 13,
        fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(a, style: GoogleFonts.rajdhani(
          color: _C.dimTxt, fontSize: 12, height: 1.4)),
    ]),
  );

  // ── Helper ────────────────────────────────────────────────────────────────
  String _fmtCoins(int m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}K 🪙' : '$m 🪙';
}

// =============================================================================
// BACKGROUND PAINTER
// =============================================================================
class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x04CAAA6C)
      ..strokeWidth = 1;
    const sp = 52.0;
    for (double x = 0; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 0.35);
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter, radius: 1.0,
        colors: [const Color(0x0FDECA46), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}