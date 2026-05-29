import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/territory_service.dart';
import '../services/stats_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_overlay.dart';
import '../widgets/stats_resumen_widget.dart';
import '../widgets/reveal.dart';
import '../widgets/operative_bg.dart';
import '../widgets/resumen/guerra_global_banner.dart';
import '../widgets/resumen/resumen_map_section.dart';
import '../widgets/resumen/resumen_context_cards.dart';
import '../widgets/resumen/resumen_historial.dart';

// =============================================================================
// PALETA — OPERATIVE DARK · ROJO ACENTO
// =============================================================================
const _kBg       = Color(0xFFE8E8ED);
const _kSurface  = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFE5E5EA);
const _kBorder2  = Color(0xFFD1D1D6);
const _kRed      = Color(0xFFE02020);
const _kBright   = Color(0xFF1C1C1E);
const _kWhite    = Color(0xFF1C1C1E);
const _kGrey     = Color(0xFF636366);
const _kGreyDim  = Color(0xFF8E8E93);
const _kGold     = Color(0xFFFFD60A);

// =============================================================================
// PANTALLA
// =============================================================================
class ResumenScreen extends StatefulWidget {
  final String?  targetUserId;
  final String?  targetNickname;
  final double   distancia;
  final Duration tiempo;
  final List<LatLng> ruta;
  final List<Map<String, dynamic>> logrosCompletados;
  final int?     timestamp;
  final bool     esDesdeCarrera;

  final int  territoriosConquistados;
  final int  puntosLigaGanados;

  final Map<String, dynamic>? objetivoGlobal;
  final bool   globalConquistado;
  final double? nuevaClausula;

  final bool modoRuta;
  final int  monedasRuta;
  final bool esDetalle;

  const ResumenScreen({
    super.key,
    this.targetUserId,
    this.targetNickname,
    required this.distancia,
    required this.tiempo,
    required this.ruta,
    this.logrosCompletados       = const [],
    this.timestamp,
    this.esDesdeCarrera          = false,
    this.territoriosConquistados = 0,
    this.puntosLigaGanados       = 0,
    this.objetivoGlobal,
    this.globalConquistado       = false,
    this.nuevaClausula,
    this.modoRuta                = false,
    this.monedasRuta             = 0,
    this.esDetalle               = false,
  });

  @override
  State<ResumenScreen> createState() => _ResumenScreenState();
}

class _ResumenScreenState extends State<ResumenScreen>
    with TickerProviderStateMixin {

  // ── Animaciones ───────────────────────────────────────────────────────────
  late AnimationController _masterCtrl;
  late AnimationController _odometroCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _rutaCtrl;
  late Animation<double> _headerReveal;
  late Animation<double> _heroReveal;
  late Animation<double> _mapReveal;
  late Animation<double> _statsReveal;
  late Animation<double> _cardsReveal;
  late Animation<double> _distAnim;
  late Animation<double> _pulse;
  late Animation<double> _rutaProgress;

  // ── Mapa ──────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  String  userId    = '';
  bool    isLoading = true;
  LatLng? _centroMapa;

  int    monedasTotalesHistorial = 0;
  int    retosTotalesHistorial   = 0;
  List<Map<String, dynamic>> todosLosLogros = [];
  bool   _verTodosLosLogros = false;
  final  TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _logrosFiltrados = [];

  static const int _paginaTamanio = 20;
  int _paginaActual = 1;

  List<TerritoryData> _territoriosEnMapa = [];
  Color _acento = _kRed;

  int    _territoriosConquistados = 0;
  int    _rachaActual             = 0;
  int    _puntosLigaSesion        = 0;
  int    _totalPuntosLiga         = 0;
  double _distMostrada            = 0;

  CarreraStats?      _carreraActual;
  List<CarreraStats> _historialStats = [];

  Map<String, dynamic>? _retoCompletadoEnSesion;

  bool get _esGuerraGlobal => widget.objetivoGlobal != null;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // ==========================================================================
  // INIT / DISPOSE
  // ==========================================================================
  @override
  void initState() {
    super.initState();

    _masterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400));
    _headerReveal = CurvedAnimation(parent: _masterCtrl,
        curve: const Interval(0.00, 0.25, curve: Curves.easeOut));
    _heroReveal = CurvedAnimation(parent: _masterCtrl,
        curve: const Interval(0.15, 0.45, curve: Curves.easeOut));
    _mapReveal = CurvedAnimation(parent: _masterCtrl,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut));
    _statsReveal = CurvedAnimation(parent: _masterCtrl,
        curve: const Interval(0.50, 0.75, curve: Curves.easeOut));
    _cardsReveal = CurvedAnimation(parent: _masterCtrl,
        curve: const Interval(0.65, 1.00, curve: Curves.easeOut));

    _odometroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _distAnim = Tween<double>(begin: 0, end: widget.distancia).animate(
        CurvedAnimation(parent: _odometroCtrl, curve: Curves.easeOutCubic));
    _distAnim.addListener(() {
      if (mounted) setState(() => _distMostrada = _distAnim.value);
    });

    _rutaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _rutaProgress = CurvedAnimation(parent: _rutaCtrl, curve: Curves.easeInOut);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.2, end: 0.8).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    userId = widget.targetUserId ??
        FirebaseAuth.instance.currentUser?.uid ?? '';

    _territoriosConquistados = widget.territoriosConquistados;
    _puntosLigaSesion        = widget.puntosLigaGanados;

    _inicializarPantalla();
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    _odometroCtrl.dispose();
    _pulseCtrl.dispose();
    _rutaCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  // LÓGICA
  // ==========================================================================
  Future<void> _inicializarPantalla() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['retoCompletado'] != null) {
        final reto = args['retoCompletado'] as Map<String, dynamic>;
        setState(() => _retoCompletadoEnSesion = reto);
        _guardarRetoCompletado(reto);
      }
    });

    try {
      await _cargarUbicacionInicial();
      await _cargarColorUsuario();

      if (widget.esDesdeCarrera) {
        if (!widget.modoRuta) await _guardarYMostrarTerritorioActual();
        await _actualizarRacha();
        OnboardingService.registrarRunCompletado();
        _verificarSolicitudResena();
      } else {
        if (!widget.modoRuta) await _guardarYMostrarTerritorioActual();
      }
    } catch (e) {
      debugPrint('Resumen _inicializarPantalla error: $e');
    } finally {
      if (mounted && isLoading) setState(() => isLoading = false);
    }

    await Future.delayed(const Duration(milliseconds: 200));
    await _cargarHistorialTotal();
    _cargarStatsResumen();

    if (widget.esDesdeCarrera && mounted) {
      if (_territoriosConquistados > 0) {
        _mostrarBannerConquista(_territoriosConquistados);
      }
      if (_esGuerraGlobal && widget.globalConquistado) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _snack('¡Territorio global conquistado!',
                widget.objetivoGlobal!['territorioNombre'] as String? ?? '',
                _kGold);
          }
        });
      }
    }

    if (mounted) {
      HapticFeedback.mediumImpact();
      _masterCtrl.forward();
      Future.delayed(const Duration(milliseconds: 300),
          () { if (mounted) _odometroCtrl.forward(); });
      Future.delayed(const Duration(milliseconds: 700),
          () { if (mounted) _rutaCtrl.forward(); });
    }
  }

  // ── Compartir resumen ────────────────────────────────────────────────────
  Future<void> _compartirResumen() async {
    HapticFeedback.mediumImpact();
    final km      = widget.distancia.toStringAsFixed(2);
    final min     = widget.tiempo.inMinutes.toString().padLeft(2, '0');
    final seg     = (widget.tiempo.inSeconds % 60).toString().padLeft(2, '0');
    final ritmo   = widget.tiempo.inSeconds > 0 && widget.distancia > 0
        ? () {
            final ritmoTotal = widget.tiempo.inSeconds / 60.0 / widget.distancia;
            final ritmoMin   = ritmoTotal.floor();
            final ritmoSeg   = ((ritmoTotal - ritmoMin) * 60).round();
            return "${ritmoMin}'${ritmoSeg.toString().padLeft(2, '0')}\"";
          }()
        : null;

    final buffer = StringBuffer();
    buffer.writeln('Acabo de correr $km km con Runner Risk');
    buffer.writeln('$min:$seg${ritmo != null ? ' · $ritmo/km' : ''}');
    if (_territoriosConquistados > 0) {
      buffer.writeln('$_territoriosConquistados territorios conquistados · +$_puntosLigaSesion pts de liga');
    }
    if (_rachaActual > 1) {
      buffer.writeln('Racha de $_rachaActual días consecutivos');
    }
    buffer.writeln('Conquista tu ciudad con Runner Risk');

    await SharePlus.instance.share(ShareParams(text: buffer.toString().trim()));
  }

  // ── Solicitar valoracion App Store ───────────────────────────────────────
  Future<void> _verificarSolicitudResena() async {
    if (!widget.esDesdeCarrera) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final runs  = (prefs.getInt('runs_completados_local') ?? 0) + 1;
      await prefs.setInt('runs_completados_local', runs);

      const milestones = {5, 20, 50};
      if (!milestones.contains(runs)) return;

      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (_) {}
  }

  Future<void> _guardarRetoCompletado(Map<String, dynamic> reto) async {
    if (userId.isEmpty) return;
    try {
      final ahora   = DateTime.now();
      final fechaId =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}';
      final premio  = (reto['premio'] as num?)?.toInt() ?? 0;

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId':             userId,
        'id_reto_completado': reto['id'],
        'titulo':             reto['titulo'],
        'recompensa':         premio,
        'timestamp':          FieldValue.serverTimestamp(),
        'fecha_dia':          fechaId,
        'distancia':          widget.distancia,
        'tiempo_segundos':    widget.tiempo.inSeconds,
      });

      if (premio > 0) {
        await FirebaseFirestore.instance
            .collection('players')
            .doc(userId)
            .update({'monedas': FieldValue.increment(premio)});
      }
    } catch (e) {
      debugPrint('Error guardando reto completado: $e');
    }

    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final onboardingState = await OnboardingService.cargarEstado();
    if (!mounted) return;
    await mostrarTooltipOnboarding(
      context:   context,
      tooltipId: 'reto_completado',
      state:     onboardingState,
    );
  }

  Future<void> _cargarStatsResumen() async {
    try {
      final historial = await StatsService.cargarCarreras(limite: 20);
      if (!mounted) return;
      CarreraStats? carreraActual;
      if (widget.esDesdeCarrera && historial.isNotEmpty) {
        carreraActual = historial.first;
      } else {
        final velMedia = widget.tiempo.inSeconds > 0
            ? widget.distancia / (widget.tiempo.inSeconds / 3600)
            : 0.0;
        final ritmo = velMedia > 0 ? 60.0 / velMedia : 0.0;
        final zona = ritmo < 4.5 ? ZonaRitmo.competicion
            : ritmo < 5.5 ? ZonaRitmo.umbral
            : ritmo < 6.5 ? ZonaRitmo.moderado
            : ritmo < 7.5 ? ZonaRitmo.facil
            : ZonaRitmo.recuperacion;
        final fechaSesion = widget.timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(widget.timestamp!)
            : DateTime.now();
        carreraActual = CarreraStats(
          id:          '',
          fecha:       fechaSesion,
          distanciaKm: widget.distancia,
          tiempoSeg:   widget.tiempo.inSeconds,
          ritmoMinKm:  ritmo,
          zona:        zona,
          calles:      [],
          ruta:        widget.ruta,
        );
      }
      setState(() {
        _historialStats = historial;
        _carreraActual  = carreraActual;
      });
    } catch (e) { debugPrint('Error stats: $e'); }
  }

  Future<void> _actualizarRacha() async {
    if (userId.isEmpty) return;
    try {
      final ref  = FirebaseFirestore.instance.collection('players').doc(userId);
      final doc  = await ref.get();
      if (!doc.exists) return;
      final data  = doc.data()!;
      final racha = (data['racha_actual'] as num?)?.toInt() ?? 0;
      final ts    = data['ultima_fecha_actividad'] as Timestamp?;
      final hoy   = DateTime.now();
      final hoySH = DateTime(hoy.year, hoy.month, hoy.day);
      int nueva;
      if (ts == null) {
        nueva = 1;
      } else {
        final u   = ts.toDate();
        final uSH = DateTime(u.year, u.month, u.day);
        final d   = hoySH.difference(uSH).inDays;
        if (d == 0)      { if (mounted) setState(() => _rachaActual = racha); return; }
        else if (d == 1) nueva = racha + 1;
        else             nueva = 1;
      }
      await ref.update({
        'racha_actual':           nueva,
        'ultima_fecha_actividad': Timestamp.now(),
      });
      if (mounted) setState(() => _rachaActual = nueva);
      if (mounted && nueva > 1) _mostrarBannerRacha(nueva);
    } catch (e) { debugPrint('Error racha: $e'); }
  }

  void _mostrarBannerRacha(int r) =>
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _snack('¡Racha de $r días!',
            r >= 7 ? 'Una semana seguida conquistando' : 'Sigue así, conquistador',
            _kGrey);
      });

  void _mostrarBannerConquista(int n) =>
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _snack('¡Territorio conquistado!',
            n == 1 ? '1 rival eliminado del mapa' : '$n rivales eliminados',
            _kGrey);
      });

  void _snack(String title, String sub, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:        const Duration(seconds: 4),
      backgroundColor: Colors.transparent,
      elevation:       0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color:        _kSurface2,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: color.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 20)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(
                color: _kWhite, fontWeight: FontWeight.w800,
                fontSize: 13, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(
                color: color.withValues(alpha: 0.8), fontSize: 11)),
          ],
        ),
      ),
    ));
  }

  Future<void> _cargarColorUsuario() async {
    if (userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(userId).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final c   = (data['territorio_color'] as num?)?.toInt();
        final pts = (data['puntos_liga']      as num?)?.toInt() ?? 0;
        setState(() {
          if (c != null) _acento = Color(c);
          _totalPuntosLiga = pts;
        });
      }
    } catch (_) {}
  }

  Future<void> _cargarUbicacionInicial() async {
    _centroMapa = widget.ruta.isNotEmpty
        ? widget.ruta.first
        : const LatLng(37.1350, -3.6330);
    if (mounted) setState(() {});
  }

  Future<void> _guardarYMostrarTerritorioActual() async {
    if (widget.ruta.length < 2) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final latC = widget.ruta.map((p) => p.latitude).reduce((a, b) => a + b) /
        widget.ruta.length;
    final lngC = widget.ruta.map((p) => p.longitude).reduce((a, b) => a + b) /
        widget.ruta.length;
    if (mounted) {
      setState(() {
        _territoriosEnMapa = [
          TerritoryData(
            docId:         'preview',
            ownerId:       user.uid,
            ownerNickname: 'YO',
            color:         _acento,
            puntos:        widget.ruta,
            centro:        LatLng(latC, lngC),
            esMio:         true,
            ultimaVisita:  DateTime.now(),
          ),
        ];
      });
    }
  }


  Future<void> _cargarHistorialTotal() async {
    if (userId.isEmpty) return;
    if (mounted) setState(() => isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 5));

      final lista   = <Map<String, dynamic>>[];
      int   monedas = 0;
      for (final doc in snap.docs) {
        final d    = doc.data();
        final dist = (d['distancia'] as num? ?? 0).toDouble();
        if (dist <= 0 || d['id_reto_completado'] != null) continue;
        lista.add({
          'docId':           doc.id,
          'titulo':          d['titulo'] ?? 'Carrera completada',
          'recompensa':      (d['recompensa'] as num? ?? 0).toInt(),
          'fecha':           d['fecha_dia'] ?? 'Reciente',
          'timestamp':       d['timestamp'],
          'distancia':       dist,
          'tiempo_segundos': (d['tiempo_segundos'] as num? ?? 0).toInt(),
          'modo':            d['modo'] ?? 'competitivo',
        });
        monedas += (d['recompensa'] as num? ?? 0).toInt();
      }
      if (mounted) {
        setState(() {
          todosLosLogros          = lista;
          _logrosFiltrados        = lista;
          retosTotalesHistorial   = lista.length;
          monedasTotalesHistorial = monedas;
          _paginaActual           = 1;
          isLoading               = false;
        });
      }
    } catch (e) {
      debugPrint('Error historial: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filtrarBusqueda(String q) => setState(() {
    _logrosFiltrados = todosLosLogros
        .where((l) =>
            l['titulo'].toString().toLowerCase().contains(q.toLowerCase()))
        .toList();
  });

  Future<void> _abrirResumenDesdeLogro(Map<String, dynamic> d) async {
    final docId = d['docId'] as String?;
    if (docId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('activity_logs').doc(docId).get();
      if (!mounted || !doc.exists) return;
      final data    = doc.data()!;
      final rutaRaw = data['ruta'] as List<dynamic>? ?? [];
      var ruta = rutaRaw.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng((m['lat'] as num).toDouble(),
                      (m['lng'] as num).toDouble());
      }).toList();
      // Fallback: si no hay ruta guardada, usar posición final como centro
      if (ruta.isEmpty) {
        final latF = (data['latFinal'] as num?)?.toDouble();
        final lngF = (data['lngFinal'] as num?)?.toDouble();
        if (latF != null && lngF != null) {
          ruta = [LatLng(latF, lngF)];
        }
      }
      if (!mounted) return;
      final ts = d['timestamp'];
      final tsMs = ts is Timestamp ? ts.millisecondsSinceEpoch : null;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ResumenScreen(
        distancia      : (d['distancia'] as double? ?? 0),
        tiempo         : Duration(seconds: d['tiempo_segundos'] as int? ?? 0),
        ruta           : ruta,
        esDesdeCarrera : false,
        esDetalle      : true,
        timestamp      : tsMs,
        modoRuta       : (d['modo'] as String? ?? '') == 'ruta',
      )));
    } catch (e) {
      debugPrint('Error abriendo resumen desde logro: $e');
    }
  }

  Future<void> _compartirEnFeed(BuildContext ctx) async {
    if (userId.isEmpty) return;
    final ctrl = TextEditingController();
    HapticFeedback.lightImpact();
    await showModalBottomSheet(
      context:            ctx,
      isScrollControlled: true,
      backgroundColor:    _kSurface2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (bCtx) {
        bool pub = false;
        return StatefulBuilder(builder: (bCtx, setM) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(bCtx).viewInsets.bottom + 36,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 32, height: 3,
                  decoration: BoxDecoration(
                      color: _kBorder2,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 22),
              _sectionLabel('PUBLICAR EN FEED'),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color:        _kBg,
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: _kBorder2)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _feedNum(widget.distancia.toStringAsFixed(2), 'KM'),
                    Container(width: 1, height: 28, color: _kBorder2),
                    _feedNum(
                        '${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}',
                        'TIEMPO'),
                    Container(width: 1, height: 28, color: _kBorder2),
                    _feedNum(
                        widget.tiempo.inSeconds > 0
                            ? (widget.distancia /
                                    (widget.tiempo.inSeconds / 3600))
                                .toStringAsFixed(1)
                            : '0.0',
                        'KM/H'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                style:      const TextStyle(color: _kWhite, fontSize: 13),
                maxLines: 3, maxLength: 300,
                decoration: InputDecoration(
                  hintText:     '¿Qué tal fue la carrera?',
                  hintStyle:    const TextStyle(color: _kGreyDim, fontSize: 13),
                  filled:       true,
                  fillColor:    _kBg,
                  counterStyle: const TextStyle(color: _kGreyDim, fontSize: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder2)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder2)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kGrey, width: 1.5)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: pub ? null : () async {
                    setM(() => pub = true);
                    try {
                      final playerDoc = await FirebaseFirestore.instance
                          .collection('players').doc(userId).get();
                      final pd = playerDoc.data() ?? {};
                      final velMedia = widget.tiempo.inSeconds > 0
                          ? widget.distancia / (widget.tiempo.inSeconds / 3600)
                          : 0.0;
                      await FirebaseFirestore.instance
                          .collection('posts')
                          .add({
                        'userId'          : userId,
                        'userNickname'    : pd['nickname'] ?? 'Runner',
                        'userNivel'       : (pd['nivel'] as num?)?.toInt() ?? 1,
                        'userAvatarBase64': pd['foto_base64'],
                        'tipo'            : 'run',
                        'titulo'          : 'Carrera de ${widget.distancia.toStringAsFixed(2)} km',
                        'descripcion'     : ctrl.text.trim(),
                        'distanciaKm'     : widget.distancia,
                        'tiempoSegundos'  : widget.tiempo.inSeconds,
                        'velocidadMedia'  : velMedia,
                        'ruta'            : widget.ruta
                            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                            .toList(),
                        'likes'           : [],
                        'saved'           : [],
                        'comentariosCount': 0,
                        'timestamp'       : Timestamp.now(),
                      });
                      if (bCtx.mounted) {
                        Navigator.pop(bCtx);
                        _snack('¡Publicado!',
                            'Tu conquista ya está en el feed', _kGrey);
                      }
                    } catch (e) {
                      debugPrint('Error publicando post: $e');
                      setM(() => pub = false);
                      if (bCtx.mounted) {
                        _snack('Error al publicar',
                            'Comprueba tu conexión', _kGreyDim);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kWhite,
                    foregroundColor: _kBg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: pub
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: _kWhite, strokeWidth: 2))
                      : const Text('PUBLICAR', style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12, letterSpacing: 3)),
                ),
              ),
            ],
          ),
        ));
      },
    );
    ctrl.dispose();
  }

  Widget _feedNum(String v, String l) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(v, style: const TextStyle(
            color: _kWhite, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(l, style: const TextStyle(
            color: _kGrey, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ]);

  // ==========================================================================
  // BUILD PRINCIPAL
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    if (isLoading || _centroMapa == null) return _buildLoading();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _cargarHistorialTotal,
        color:           _kGrey,
        backgroundColor: _kSurface2,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: const OperativeBgPainter())),
          SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal(anim: _headerReveal, child: _buildHeader()),
                  const SizedBox(height: 24),

                  if (_esGuerraGlobal)
                    Reveal(
                      anim: _heroReveal,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GuerraGlobalBanner(
                          objetivoGlobal:    widget.objetivoGlobal!,
                          globalConquistado: widget.globalConquistado,
                          distancia:         widget.distancia,
                          nuevaClausula:     widget.nuevaClausula,
                        ),
                      ),
                    ),

                  Reveal(anim: _heroReveal, child: _buildHeroOdometro()),
                  const SizedBox(height: 10),

                  Reveal(anim: _heroReveal, child: _buildSecondaryMetrics()),
                  const SizedBox(height: 20),

                  Reveal(
                    anim: _mapReveal,
                    child: ResumenMapSection(
                      ruta:                    widget.ruta,
                      modoRuta:                widget.modoRuta,
                      esDesdeCarrera:          widget.esDesdeCarrera,
                      territoriosEnMapa:       _territoriosEnMapa,
                      acento:                  _acento,
                      centroMapa:              _centroMapa!,
                      mapController:           _mapController,
                      rutaProgress:            _rutaProgress,
                      territoriosConquistados: _territoriosConquistados,
                      sectionLabel:            widget.modoRuta
                          ? 'TU RUTA'
                          : _territoriosConquistados > 0
                              ? 'TERRITORIO CONQUISTADO'
                              : 'RUTA DE CARRERA',
                    ),
                  ),
                  const SizedBox(height: 18),

                  if (_carreraActual != null)
                    Reveal(
                      anim: _statsReveal,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: StatsResumenWidget(
                          carreraActual: _carreraActual!,
                          historial:     _historialStats,
                        ),
                      ),
                    ),

                  Reveal(anim: _statsReveal, child: _buildTotalesRow()),
                  const SizedBox(height: 10),

                  Reveal(
                    anim: _cardsReveal,
                    child: ResumenContextCards(
                      esDesdeCarrera:          widget.esDesdeCarrera,
                      modoRuta:                widget.modoRuta,
                      esGuerraGlobal:          _esGuerraGlobal,
                      rachaActual:             _rachaActual,
                      monedasRuta:             widget.monedasRuta,
                      puntosLigaSesion:        _puntosLigaSesion,
                      totalPuntosLiga:         _totalPuntosLiga,
                      territoriosConquistados: _territoriosConquistados,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Reveal(
                    anim: _cardsReveal,
                    child: ResumenHistorial(
                      logrosFiltrados:        _logrosFiltrados,
                      todosLosLogros:         todosLosLogros,
                      verTodos:               _verTodosLosLogros,
                      searchCtrl:             _searchCtrl,
                      paginaActual:           _paginaActual,
                      paginaTamanio:          _paginaTamanio,
                      retoCompletadoEnSesion: _retoCompletadoEnSesion,
                      onSearch:               _filtrarBusqueda,
                      onTapLogro:             _abrirResumenDesdeLogro,
                      onToggleVerTodos: () => setState(() {
                        _verTodosLosLogros = !_verTodosLosLogros;
                        if (!_verTodosLosLogros) {
                          _searchCtrl.clear();
                          _logrosFiltrados = todosLosLogros;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Reveal(anim: _cardsReveal, child: _buildAcciones()),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ==========================================================================
  // WIDGETS LOCALES
  // ==========================================================================

  Widget _buildLoading() => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape:  BoxShape.circle,
            border: Border.all(
                color: _kGrey.withValues(alpha: _pulse.value), width: 1.5),
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text('PROCESANDO MISIÓN', style: TextStyle(
          color: _kGrey, fontSize: 9,
          fontWeight: FontWeight.w900, letterSpacing: 4)),
    ])),
  );

  Widget _buildHeader() {
    final titulo = widget.targetNickname != null
        ? widget.targetNickname!.toUpperCase()
        : widget.modoRuta
            ? 'RESUMEN DE RUTA LIBRE'
            : _esGuerraGlobal ? 'RESUMEN DE LA CARRERA GLOBAL' : 'RESUMEN DE LA CARRERA';
    final ahora  = widget.timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.timestamp!)
        : DateTime.now();
    const meses  = ['ENE','FEB','MAR','ABR','MAY','JUN',
                     'JUL','AGO','SEP','OCT','NOV','DIC'];
    final fecha  =
        '${ahora.day.toString().padLeft(2, '0')} ${meses[ahora.month - 1]} ${ahora.year}';

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (widget.esDetalle) {
            Navigator.popUntil(context, (route) => route.isFirst);
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
          }
        },
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: _kBorder2),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _kGrey, size: 13),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(
              color:         _isDark ? Colors.white : _kWhite,
              fontSize:      titulo.length > 20 ? 15 : 19,
              fontWeight:    FontWeight.w900,
              letterSpacing: 0.5)),
          const SizedBox(height: 3),
          Text(fecha, style: const TextStyle(
              color: _kGreyDim, fontSize: 10, letterSpacing: 0.5)),
        ],
      )),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(6),
          border:       Border.all(color: _kBorder2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              color: _esGuerraGlobal ? _kGold : _kGrey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _esGuerraGlobal ? 'GLOBAL' : 'HOY',
            style: TextStyle(
              color:         _esGuerraGlobal ? _kGold : _kGrey,
              fontSize:      8,
              fontWeight:    FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _compartirResumen,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: _kBorder2),
          ),
          child: const Icon(Icons.ios_share_rounded, color: _kGrey, size: 16),
        ),
      ),
    ]);
  }

  Widget _buildHeroOdometro() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
    decoration: BoxDecoration(
      color:        _kSurface,
      borderRadius: BorderRadius.circular(12),
      border:       Border.all(color: _kBorder2),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('DISTANCIA TOTAL'),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_distMostrada.toStringAsFixed(2),
          style: const TextStyle(
            color:         _kWhite,
            fontSize:      76,
            fontWeight:    FontWeight.w900,
            height:        0.95,
            letterSpacing: -2,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 10, left: 10),
          child: Text('KM', style: TextStyle(
              color:         _kGreyDim,
              fontSize:      20,
              fontWeight:    FontWeight.w700,
              letterSpacing: 2)),
        ),
      ]),
      const SizedBox(height: 10),
      AnimatedBuilder(animation: _odometroCtrl, builder: (_, __) =>
        Stack(children: [
          Container(height: 2, width: double.infinity,
              decoration: BoxDecoration(
                  color: _kBorder2, borderRadius: BorderRadius.circular(1))),
          FractionallySizedBox(
            widthFactor: _odometroCtrl.value,
            child: Container(height: 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: _kGrey,
              ),
            ),
          ),
        ])),
    ]),
  );

  Widget _buildSecondaryMetrics() {
    final isDark = _isDark;
    final horas = widget.tiempo.inSeconds / 3600;
    final vel   = horas > 0 && widget.distancia > 0
        ? widget.distancia / horas : 0.0;
    final ritmo = vel > 0.5 ? () {
      final mpk = 60.0 / vel;
      final min = mpk.floor();
      final seg = ((mpk - min) * 60).round();
      return "$min'${seg.toString().padLeft(2, '0')}\"";
    }() : '--:--';
    final tiempo =
        '${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}';

    final cardBg     = isDark ? const Color(0xFF2C2C2E) : _kSurface;
    final cardBorder = isDark ? const Color(0xFF3A3A3C) : _kBorder2;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color:        cardBg,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TIEMPO', style: const TextStyle(
              color: _kGrey, fontSize: 7,
              fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 8),
          Text(tiempo, style: TextStyle(
              color: isDark ? Colors.white : _kBright, fontSize: 28,
              fontWeight: FontWeight.w900, letterSpacing: 1)),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _metricTileSmall(ritmo, 'MIN/KM', isDark: isDark)),
        const SizedBox(width: 8),
        Expanded(child: _metricTileSmall(vel.toStringAsFixed(1), 'KM/H', isDark: isDark)),
        const SizedBox(width: 8),
        Expanded(child: _metricTileSmall(
            (widget.distancia * (55 + vel * 1.0).clamp(55.0, 82.0))
                .round().toString(),
            'KCAL', isDark: isDark)),
      ]),
    ]);
  }

  Widget _metricTileSmall(String v, String l, {bool isDark = false}) {
    final cardBg     = isDark ? const Color(0xFF2C2C2E) : _kSurface;
    final cardBorder = isDark ? const Color(0xFF3A3A3C) : _kBorder2;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color:        cardBg,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v, style: TextStyle(
              color:      isDark ? Colors.white : _kWhite,
              fontSize:   18,
              fontWeight: FontWeight.w900,
              height:     1)),
          const SizedBox(height: 2),
          Text(l, style: const TextStyle(
              color: _kGreyDim, fontSize: 7,
              fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildTotalesRow() => Row(children: [
    Expanded(child: _totalCell(
        retosTotalesHistorial.toString(), 'CARRERAS TOTALES')),
    const SizedBox(width: 8),
    Expanded(child: _totalCell(
        monedasTotalesHistorial.toString(),
        'PUNTOS ACUMULADOS', accent: true)),
  ]);

  Widget _totalCell(String v, String l, {bool accent = false}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _kBorder2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v, style: TextStyle(
                color:      accent ? _kBright : _kWhite,
                fontSize:   18,
                fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(
                color: _kGrey, fontSize: 7,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ],
        ),
      );

  Widget _buildAcciones() {
    final isDark = _isDark;
    return Column(children: [
    GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _compartirEnFeed(context);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isDark ? Colors.white : _kWhite,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 10),
          Text('PUBLICAR EN EL FEED', style: TextStyle(
              color:         isDark ? _kWhite : _kBg,
              fontSize:      11,
              fontWeight:    FontWeight.w900,
              letterSpacing: 2.5)),
        ]),
      ),
    ),
    const SizedBox(height: 20),
    Row(children: [
      Expanded(child: Container(height: 1, color: _kBorder2)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child:   Text('·', style: TextStyle(color: _kGreyDim, fontSize: 10)),
      ),
      Expanded(child: Container(height: 1, color: _kBorder2)),
    ]),
  ]);
  }

  Widget _sectionLabel(String t) => Row(children: [
    Container(
      width: 3, height: 11,
      decoration: BoxDecoration(
          color: _kGrey, borderRadius: BorderRadius.circular(2)),
    ),
    const SizedBox(width: 8),
    Text(t, style: const TextStyle(
        color: _kGrey, fontSize: 8,
        fontWeight: FontWeight.w900, letterSpacing: 3)),
  ]);
}
