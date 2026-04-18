import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/territory_service.dart';
import '../services/stats_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_overlay.dart';
import '../widgets/stats_resumen_widget.dart';
import 'fullscreen_map_screen.dart';
import '../config/env.dart';

// =============================================================================
// PALETA — OPERATIVE DARK · ROJO ACENTO
// =============================================================================
const _kBg       = Color(0xFFE8E8ED);
const _kSurface  = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFE5E5EA);
const _kBorder   = Color(0xFFC6C6C8);
const _kBorder2  = Color(0xFFD1D1D6);
const _kRed      = Color(0xFFE02020);
const _kRedDim   = Color(0xFFFF6B6B);
const _kRedGlow  = Color(0x22E02020);
const _kBright   = Color(0xFF1C1C1E);
const _kWhite    = Color(0xFF1C1C1E);
const _kGrey     = Color(0xFF636366);
const _kGreyDim  = Color(0xFF8E8E93);
const _kGold     = Color(0xFFFFD60A);
const _kGoldDim  = Color(0xFFAEAEB2);

// Guerra Global accent
const _kGlobalRed     = Color(0xFFCC2222);
const _kGlobalRedDim  = Color(0xFF7A1414);

// =============================================================================
// MAPBOX
// =============================================================================
const _kMapboxToken   = Env.mapboxPublicToken;
const _kMapboxTileUrl =
    'https://api.mapbox.com/styles/v1/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv/tiles/256/{z}/{x}/{y}?access_token=$_kMapboxToken';

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

  // ── Nuevos: conquistas de la sesión
  final int  territoriosConquistados;
  final int  puntosLigaGanados;

  // ── Nuevos: Guerra Global
  final Map<String, dynamic>? objetivoGlobal;
  final bool globalConquistado;
  final double? nuevaClausula;

  const ResumenScreen({
    super.key,
    this.targetUserId,
    this.targetNickname,
    required this.distancia,
    required this.tiempo,
    required this.ruta,
    this.logrosCompletados          = const [],
    this.timestamp,
    this.esDesdeCarrera             = false,
    this.territoriosConquistados    = 0,
    this.puntosLigaGanados          = 0,
    this.objetivoGlobal,
    this.globalConquistado          = false,
    this.nuevaClausula,
  });

  @override
  State<ResumenScreen> createState() => _ResumenScreenState();
}

class _ResumenScreenState extends State<ResumenScreen>
    with TickerProviderStateMixin {

  // ── Animaciones
  late AnimationController _masterCtrl;
  late AnimationController _odometroCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _rutaCtrl;
  late AnimationController _glitchCtrl;

  late Animation<double> _headerReveal;
  late Animation<double> _heroReveal;
  late Animation<double> _mapReveal;
  late Animation<double> _statsReveal;
  late Animation<double> _cardsReveal;
  late Animation<double> _distAnim;
  late Animation<double> _pulse;
  late Animation<double> _rutaProgress;
  late Animation<double> _glitch;

  // ── Mapa
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
  int  _paginaActual  = 1;
  bool _hayMasPaginas = false;
  bool _cargandoMas   = false;

  List<TerritoryData> _territoriosEnMapa = [];
  Color _acento = _kRed;

  int    _territoriosConquistados = 0;
  int    _rachaActual             = 0;
  int    _puntosLigaSesion        = 0;
  int    _totalPuntosLiga         = 0;
  double _distMostrada            = 0;

  CarreraStats?       _carreraActual;
  List<CarreraStats>  _historialStats = [];

  Map<String, dynamic>? _retoCompletadoEnSesion;

  // ── Guerra Global (resolución desde widget directamente)
  bool get _esGuerraGlobal => widget.objetivoGlobal != null;

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

    _glitchCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _glitch = Tween<double>(begin: 0, end: 1).animate(_glitchCtrl);

    userId = widget.targetUserId ??
        FirebaseAuth.instance.currentUser?.uid ?? '';

    // Pasar conquistas de sesión al estado
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
    _glitchCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  // LÓGICA
  // ==========================================================================
  Future<void> _inicializarPantalla() async {
    // Reto completado (llega desde LiveActivity vía arguments)
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

    await _cargarUbicacionInicial();
    await _cargarColorUsuario();

    if (widget.esDesdeCarrera) {
      await _guardarActivityLog();
      await _guardarYMostrarTerritorioActual();
      await _actualizarRacha();
      OnboardingService.registrarRunCompletado();
    } else {
      await _cargarTodosLosTerritorios();
    }

    await Future.delayed(const Duration(milliseconds: 200));
    await _cargarHistorialTotal();
    _cargarStatsResumen();

    if (widget.esDesdeCarrera && mounted) {
      if (_territoriosConquistados > 0) {
        _mostrarBannerConquista(_territoriosConquistados);
      }
      if (_puntosLigaSesion > 0 && !_esGuerraGlobal) {
        // El banner de liga se muestra en la card, no como snack adicional
      }
      // Banner especial si conquistó territorio global
      if (_esGuerraGlobal && widget.globalConquistado) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _snack('', '¡Territorio global conquistado!',
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
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _glitchCtrl.repeat(reverse: true);
          Future.delayed(const Duration(milliseconds: 600),
              () { if (mounted) _glitchCtrl.stop(); });
        }
      });
    }
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
    if (!widget.esDesdeCarrera) return;
    try {
      final historial = await StatsService.cargarCarreras(limite: 20);
      if (historial.isEmpty || !mounted) return;
      setState(() {
        _historialStats = historial;
        _carreraActual  = historial.first;
      });
    } catch (e) { debugPrint('Error stats: $e'); }
  }

  Future<void> _guardarActivityLog() async {
    if (userId.isEmpty || widget.distancia <= 0) return;
    try {
      final horas = widget.tiempo.inSeconds / 3600;
      final ahora = DateTime.now();
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId':          userId,
        'distancia':       widget.distancia,
        'tiempo_segundos': widget.tiempo.inSeconds,
        'velocidad_media': horas > 0 ? widget.distancia / horas : 0.0,
        'timestamp':       FieldValue.serverTimestamp(),
        'fecha_dia': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}',
        // Metadatos de modo
        'titulo': _esGuerraGlobal
            ? 'Guerra Global · ${widget.objetivoGlobal!['territorioNombre'] ?? ''}'
            : 'Carrera Libre',
        'modo': _esGuerraGlobal ? 'guerra_global' : 'competitivo',
        if (_esGuerraGlobal) ...{
          'objetivo_global_id':          widget.objetivoGlobal!['territorioId'],
          'objetivo_global_conquistado': widget.globalConquistado,
        },
      });
    } catch (e) { debugPrint('Error log: $e'); }
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
        'racha_actual':            nueva,
        'ultima_fecha_actividad':  Timestamp.now(),
      });
      if (mounted) setState(() => _rachaActual = nueva);
      if (mounted && nueva > 1) _mostrarBannerRacha(nueva);
    } catch (e) { debugPrint('Error racha: $e'); }
  }

  void _mostrarBannerRacha(int r) =>
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _snack('', '¡Racha de $r días!',
            r >= 7
                ? ' Una semana seguida conquistando'
                : 'Sigue así, conquistador',
            _kGrey);
      });

  void _mostrarBannerConquista(int n) =>
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _snack('', '¡Territorio conquistado!',
            n == 1
                ? '1 rival eliminado del mapa'
                : '$n rivales eliminados',
            _kGrey);
      });

  void _snack(String emoji, String title, String sub, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:        const Duration(seconds: 4),
      backgroundColor: Colors.transparent,
      elevation:       0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color:        _kSurface2,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: color.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.15), blurRadius: 20)
          ],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(color: _kWhite,
                      fontWeight: FontWeight.w800,
                      fontSize: 13, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(
                      color: color.withOpacity(0.8), fontSize: 11)),
            ],
          )),
        ]),
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
        final c = (data['territorio_color'] as num?)?.toInt();
        final pts = (data['puntos_liga'] as num?)?.toInt() ?? 0;
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
    // La CF (conquistarTerritorio) ya guardó el territorio en Firestore.
    // Solo construimos el objeto local para mostrarlo en el mapa del resumen.
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

  Future<void> _cargarTodosLosTerritorios() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 6));
      final res = <TerritoryData>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final raw  = data['puntos'] as List<dynamic>?;
        if (raw == null || raw.isEmpty) continue;
        final pts = raw.map((p) {
          final m = p as Map<String, dynamic>;
          return LatLng((m['lat'] as num).toDouble(),
              (m['lng'] as num).toDouble());
        }).toList();
        final latC =
            pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
        final lngC =
            pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
        DateTime? uv;
        final ts = data['ultima_visita'];
        if (ts is Timestamp) uv = ts.toDate();
        res.add(TerritoryData(
          docId:         doc.id,
          ownerId:       userId,
          ownerNickname: 'YO',
          color:         _acento,
          puntos:        pts,
          centro:        LatLng(latC, lngC),
          esMio:         true,
          ultimaVisita:  uv,
        ));
      }
      if (mounted) setState(() => _territoriosEnMapa = res);
    } catch (e) { debugPrint('Error territorios: $e'); }
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
        final d = doc.data();
        // Solo incluir carreras reales (tienen distancia > 0 y no son solo retos)
        final dist = (d['distancia'] as num? ?? 0).toDouble();
        if (dist <= 0 || d['id_reto_completado'] != null) continue;
        lista.add({
          'titulo':     d['titulo'] ?? 'Carrera completada',
          'recompensa': (d['recompensa'] as num? ?? 0).toInt(),
          'fecha':      d['fecha_dia'] ?? 'Reciente',
          'timestamp':  d['timestamp'],
          'distancia':  dist,
          'modo':       d['modo'] ?? 'competitivo',
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
          _hayMasPaginas          = lista.length >= 50;
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

  Future<void> _compartirEnFeed(BuildContext ctx) async {
    if (userId.isEmpty) return;
    final ctrl = TextEditingController();
    HapticFeedback.lightImpact();
    await showModalBottomSheet(
      context:          ctx,
      isScrollControlled: true,
      backgroundColor:  _kSurface2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (bCtx) {
        bool pub = false;
        return StatefulBuilder(builder: (bCtx, setM) => Padding(
          padding: EdgeInsets.only(
            left:   24, right: 24, top: 20,
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
                    color: _kBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder2)),
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
                style: const TextStyle(color: _kWhite, fontSize: 13),
                maxLines: 3, maxLength: 300,
                decoration: InputDecoration(
                  hintText:        '¿Qué tal fue la carrera?',
                  hintStyle:       const TextStyle(color: _kGreyDim, fontSize: 13),
                  filled:          true,
                  fillColor:       _kBg,
                  counterStyle:    const TextStyle(color: _kGreyDim, fontSize: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder2)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder2)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: _kGrey, width: 1.5)),
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
                          ? widget.distancia /
                              (widget.tiempo.inSeconds / 3600)
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
                        _snack('', '¡Publicado!',
                            'Tu conquista ya está en el feed', _kGrey);
                      }
                    } catch (e) {
                      debugPrint('Error publicando post: $e');
                      setM(() => pub = false);
                      if (bCtx.mounted) {
                        _snack('', 'Error al publicar',
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
                      : const Text('PUBLICAR',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 3)),
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
        color: _kRed,
        backgroundColor: _kSurface2,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _OperativeBg())),
          SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Reveal(anim: _headerReveal, child: _buildHeader()),
                  const SizedBox(height: 24),

                  // ── Banner de Guerra Global (si aplica)
                  if (_esGuerraGlobal)
                    _Reveal(
                      anim: _heroReveal,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildBannerGuerraGlobal(),
                      ),
                    ),

                  _Reveal(anim: _heroReveal, child: _buildHeroOdometro()),
                  const SizedBox(height: 10),

                  _Reveal(
                      anim: _heroReveal, child: _buildSecondaryMetrics()),
                  const SizedBox(height: 20),

                  _Reveal(anim: _mapReveal, child: _buildMapSection()),
                  const SizedBox(height: 18),

                  if (widget.esDesdeCarrera && _carreraActual != null)
                    _Reveal(
                      anim: _statsReveal,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: StatsResumenWidget(
                          carreraActual: _carreraActual!,
                          historial:     _historialStats,
                        ),
                      ),
                    ),

                  _Reveal(anim: _statsReveal, child: _buildTotalesRow()),
                  const SizedBox(height: 10),

                  _Reveal(anim: _cardsReveal, child: _buildContextCards()),
                  const SizedBox(height: 24),

                  _Reveal(anim: _cardsReveal, child: _buildHistorial()),
                  const SizedBox(height: 24),

                  _Reveal(anim: _cardsReveal, child: _buildAcciones()),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ==========================================================================
  // BANNER GUERRA GLOBAL
  // ==========================================================================
  Widget _buildBannerGuerraGlobal() {
    final nombre     = widget.objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio';
    final kmReq      = (widget.objetivoGlobal!['kmRequeridos']    as num?)?.toDouble() ?? 0;
    final recompensa = (widget.objetivoGlobal!['recompensa']      as num?)?.toInt()    ?? 0;
    final conquistado = widget.globalConquistado;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: conquistado
              ? [const Color(0xFF1A1000), const Color(0xFF3A2800)]
              : [const Color(0xFF1A0000), const Color(0xFF2A0808)],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: conquistado
              ? _kGold.withOpacity(0.5)
              : _kGlobalRed.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (conquistado ? _kGold : _kGlobalRed).withOpacity(0.15),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera
            Row(children: [
              Text(conquistado ? '' : '',
                  style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GUERRA GLOBAL',
                    style: TextStyle(
                      color:         conquistado ? _kGold : _kGlobalRed,
                      fontSize:      9,
                      fontWeight:    FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    nombre,
                    style: const TextStyle(
                        color:      _kBright,
                        fontSize:   16,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              )),
              // Estado
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (conquistado ? _kGold : _kGlobalRed)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (conquistado ? _kGold : _kGlobalRed)
                        .withOpacity(0.4),
                  ),
                ),
                child: Text(
                  conquistado ? ' CONQUISTADO' : ' NO COMPLETADO',
                  style: TextStyle(
                    color:         conquistado ? _kGold : _kGlobalRed,
                    fontSize:      9,
                    fontWeight:    FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 16),
            Container(height: 1, color: _kBorder2),
            const SizedBox(height: 16),

            // ── Stats
            Row(children: [
              _ggStat('KM RECORRIDOS',
                  widget.distancia.toStringAsFixed(2), _kWhite),
              _ggDivider(),
              _ggStat('KM REQUERIDOS',
                  kmReq.toStringAsFixed(1), _kGrey),
              _ggDivider(),
              _ggStat(
                'PROGRESO',
                kmReq > 0
                    ? '${((widget.distancia / kmReq).clamp(0, 1) * 100).toInt()}%'
                    : '--',
                conquistado ? _kGold : _kGlobalRed,
              ),
            ]),

            // ── Barra de progreso
            const SizedBox(height: 12),
            Stack(children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                    color:        _kBorder2,
                    borderRadius: BorderRadius.circular(3)),
              ),
              FractionallySizedBox(
                widthFactor: kmReq > 0
                    ? (widget.distancia / kmReq).clamp(0.0, 1.0)
                    : 0,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: conquistado
                          ? [_kGoldDim, _kGold]
                          : [_kGlobalRedDim, _kGlobalRed],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (conquistado ? _kGold : _kGlobalRed)
                            .withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ]),

            // ── Nueva cláusula establecida tras conquista
            if (conquistado && widget.nuevaClausula != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _kGoldDim.withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  const Text('', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                            color: _kGrey, fontSize: 11),
                        children: [
                          const TextSpan(
                              text: 'Próxima cláusula: '),
                          TextSpan(
                            text:
                                '${widget.nuevaClausula!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: _kGold,
                                fontWeight: FontWeight.w900),
                          ),
                          const TextSpan(
                              text:
                                  ' — el siguiente en conquistarlo necesitará recorrer esta distancia.'),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ],

            // ── Recompensa (nota: se paga al final de la semana)
            if (conquistado) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kGold.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGoldDim.withOpacity(0.5)),
                ),
                child: Row(children: [
                  const Text('', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('+$recompensa monedas reservadas',
                          style: const TextStyle(
                              color:      _kGold,
                              fontSize:   13,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        'Las recompensas se entregan al final de la semana si sigues siendo el dueño.',
                        style: TextStyle(
                            color:    _kGoldDim.withOpacity(0.85),
                            fontSize: 10),
                      ),
                    ],
                  )),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ggStat(String label, String value, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(
            color:         _kGrey,
            fontSize:      7,
            fontWeight:    FontWeight.w700,
            letterSpacing: 1.5),
            textAlign: TextAlign.center),
      ]));

  Widget _ggDivider() =>
      Container(width: 1, height: 36, color: _kBorder2,
          margin: const EdgeInsets.symmetric(horizontal: 8));

  // ── Loading
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
                color: _kGrey.withOpacity(_pulse.value), width: 1.5),
          ),
          child: const Center(
              child: Text('', style: TextStyle(fontSize: 24))),
        ),
      ),
      const SizedBox(height: 18),
      const Text('PROCESANDO MISIÓN', style: TextStyle(
          color:         _kGrey,
          fontSize:      9,
          fontWeight:    FontWeight.w900,
          letterSpacing: 4)),
    ])),
  );

  // ── Header
  Widget _buildHeader() {
    final titulo = widget.targetNickname != null
        ? widget.targetNickname!.toUpperCase()
        : _esGuerraGlobal ? 'INFORME DE CAMPAÑA GLOBAL' : 'INFORME DE CAMPAÑA';
    final ahora  = DateTime.now();
    const meses  = ['ENE','FEB','MAR','ABR','MAY','JUN',
                     'JUL','AGO','SEP','OCT','NOV','DIC'];
    final fecha  =
        '${ahora.day.toString().padLeft(2, '0')} ${meses[ahora.month - 1]} ${ahora.year}';

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (Navigator.canPop(context))
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
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
        )
      else
        const SizedBox(width: 38),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(animation: _glitchCtrl, builder: (_, __) {
            final s = (_glitch.value > 0.5) ? 1.5 : 0.0;
            return Stack(children: [
              Transform.translate(
                offset: Offset(s, 0),
                child: Text(titulo, style: TextStyle(
                    color:      _kGrey.withOpacity(0.25),
                    fontSize:   titulo.length > 20 ? 16 : 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5)),
              ),
              Text(titulo, style: TextStyle(
                  color:      _kWhite,
                  fontSize:   titulo.length > 20 ? 16 : 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
            ]);
          }),
          const SizedBox(height: 2),
          Row(children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color:  _esGuerraGlobal ? _kGold : _kRed,
                shape:  BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(fecha, style: const TextStyle(
                color: _kGrey, fontSize: 10, letterSpacing: 1)),
          ]),
        ],
      )),
      AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (_esGuerraGlobal ? _kGold : _kRed).withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: (_esGuerraGlobal ? _kGold : _kRed)
                  .withOpacity(_pulse.value * 0.6 + 0.1),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color:  _esGuerraGlobal ? _kGold : _kRed,
                shape:  BoxShape.circle,
                boxShadow: [BoxShadow(
                    color:      _esGuerraGlobal ? _kGold : _kRed,
                    blurRadius: 5)],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _esGuerraGlobal ? 'GLOBAL' : 'HOY',
              style: TextStyle(
                color:         _esGuerraGlobal ? _kGold : _kRed,
                fontSize:      8,
                fontWeight:    FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
          ]),
        )),
    ]);
  }

  // ── Hero odómetro
  Widget _buildHeroOdometro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color:        _kSurface,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _kBorder2),
        boxShadow: [
          BoxShadow(
              color: _kRed.withOpacity(0.06),
              blurRadius: 30, spreadRadius: -5),
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10),
        ],
      ),
      child: Stack(children: [
        Positioned.fill(child: IgnorePointer(
            child: CustomPaint(painter: _ScanlinesPainter()))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionLabel('DISTANCIA TOTAL'),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_distMostrada.toStringAsFixed(2),
              style: const TextStyle(
                color:       _kWhite,
                fontSize:    76,
                fontWeight:  FontWeight.w900,
                height:      0.95,
                letterSpacing: -2,
                shadows: [
                  Shadow(color: _kRed, blurRadius: 24),
                  Shadow(color: Color(0x33E53935), blurRadius: 50),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 8),
              child: Text('KM', style: TextStyle(
                  color:         _kRed,
                  fontSize:      22,
                  fontWeight:    FontWeight.w900,
                  letterSpacing: 3)),
            ),
          ]),
          const SizedBox(height: 10),
          AnimatedBuilder(animation: _odometroCtrl, builder: (_, __) =>
            Stack(children: [
              Container(height: 2, width: double.infinity,
                  decoration: BoxDecoration(
                      color:        _kBorder2,
                      borderRadius: BorderRadius.circular(1))),
              FractionallySizedBox(
                widthFactor: _odometroCtrl.value,
                child: Container(height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: const LinearGradient(
                        colors: [_kRedDim, _kRed, _kRedGlow]),
                  ),
                ),
              ),
            ])),
        ]),
      ]),
    );
  }

  Widget _buildSecondaryMetrics() {
    final horas  = widget.tiempo.inSeconds / 3600;
    final vel    = horas > 0 && widget.distancia > 0
        ? widget.distancia / horas : 0.0;
    final ritmo  = vel > 0.5 ? () {
      final mpk = 60.0 / vel;
      final min = mpk.floor();
      final seg = ((mpk - min) * 60).round();
      return "$min'${seg.toString().padLeft(2, '0')}\"";
    }() : '--:--';
    final tiempo =
        '${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}';

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: _kBorder2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            const Text('TIEMPO', style: TextStyle(
                color:         _kGrey,
                fontSize:      7,
                fontWeight:    FontWeight.w900,
                letterSpacing: 2)),
          ]),
          const SizedBox(height: 8),
          Text(tiempo, style: const TextStyle(
              color:        _kBright,
              fontSize:     28,
              fontWeight:   FontWeight.w900,
              letterSpacing: 1)),
        ]),
      )),
      const SizedBox(width: 8),
      Expanded(flex: 4, child: Column(children: [
        _metricTileSmall(ritmo, 'MIN/KM', '', accent: false),
        const SizedBox(height: 8),
        _metricTileSmall(vel.toStringAsFixed(1), 'KM/H', '', accent: true),
      ])),
    ]);
  }

  Widget _metricTileSmall(String v, String l, String emoji,
      {bool accent = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: _kBorder2),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v, style: TextStyle(
                  color:      accent ? _kBright : _kWhite,
                  fontSize:   15,
                  fontWeight: FontWeight.w900,
                  height:     1)),
              const SizedBox(height: 2),
              Text(l, style: const TextStyle(
                  color:         _kGreyDim,
                  fontSize:      7,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 1.5)),
            ],
          )),
        ]),
      );

  // ── Mapa
  Widget _buildMapSection() {
    final tieneRuta = widget.ruta.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(_territoriosConquistados > 0
          ? 'TERRITORIO CONQUISTADO'
          : 'RUTA DE CARRERA'),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
              FullscreenMapScreen(
                territorios:     _territoriosEnMapa,
                colorTerritorio: _acento,
                centroInicial:   _centroMapa!,
                ruta:            widget.ruta,
                mostrarRuta:     widget.esDesdeCarrera,
              )));
        },
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(
                color: _acento.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                  color:      _acento.withOpacity(0.08),
                  blurRadius: 20),
              BoxShadow(
                  color:      Colors.black.withOpacity(0.4),
                  blurRadius: 8),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _centroMapa!,
                  initialZoom:   15,
                  onMapReady: () {
                    if (tieneRuta) {
                      _mapController.fitCamera(CameraFit.bounds(
                          bounds:  LatLngBounds.fromPoints(widget.ruta),
                          padding: const EdgeInsets.all(52)));
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:          _kMapboxTileUrl,
                    userAgentPackageName: 'com.runner_risk.app',
                    tileDimension:        256,
                    additionalOptions:
                        const {'accessToken': _kMapboxToken},
                  ),
                  if (_territoriosEnMapa.isNotEmpty)
                    PolygonLayer(polygons: _territoriosEnMapa.map((t) =>
                        Polygon(
                          points:            t.puntos,
                          color:             t.color.withOpacity(0.35),
                          borderColor:       t.color,
                          borderStrokeWidth: 2.0,
                        )).toList()),
                  if (tieneRuta && widget.esDesdeCarrera)
                    AnimatedBuilder(
                      animation: _rutaProgress,
                      builder: (_, __) {
                        final n = (widget.ruta.length * _rutaProgress.value)
                            .round()
                            .clamp(2, widget.ruta.length);
                        return PolylineLayer(polylines: [
                          Polyline(
                              points:      widget.ruta.sublist(0, n),
                              strokeWidth: 7.0,
                              color:       _kRed.withOpacity(0.15)),
                          Polyline(
                              points:      widget.ruta.sublist(0, n),
                              strokeWidth: 3.0,
                              color:       _kRed),
                        ]);
                      },
                    ),
                  if (!tieneRuta)
                    MarkerLayer(markers: [
                      Marker(
                        point: _centroMapa!,
                        child: Icon(Icons.location_on,
                            color: _kRed, size: 26),
                      ),
                    ]),
                ],
              ),
              Positioned.fill(child: IgnorePointer(
                  child: DecoratedBox(decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: RadialGradient(
                        center: Alignment.center, radius: 1.1,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3)
                        ]),
                  )))),
              Positioned(top: 10, left: 10,
                  child: _mapBadge(
                      '${_territoriosEnMapa.length} zona${_territoriosEnMapa.length == 1 ? '' : 's'}',
                      '')),
              Positioned(top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:        Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(6),
                    border:       Border.all(color: _kBorder2),
                  ),
                  child: const Icon(Icons.open_in_full_rounded,
                      color: _kGrey, size: 12),
                )),
              Positioned(bottom: 0, left: 0, right: 0,
                child: AnimatedBuilder(
                  animation: _rutaProgress,
                  builder: (_, __) => LinearProgressIndicator(
                    value:           _rutaProgress.value,
                    backgroundColor: Colors.black.withOpacity(0.3),
                    valueColor:
                        AlwaysStoppedAnimation(_kGrey.withOpacity(0.6)),
                    minHeight: 2,
                  ),
                )),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _mapBadge(String text, String emoji) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
        color:        Colors.black.withOpacity(0.72),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: _kBorder2)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 9)),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(
          color: _kWhite, fontSize: 9, fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _buildTotalesRow() => Row(children: [
    Expanded(child: _totalCell(
        retosTotalesHistorial.toString(), 'CARRERAS TOTALES', '')),
    const SizedBox(width: 8),
    Expanded(child: _totalCell(
        monedasTotalesHistorial.toString(),
        'PUNTOS ACUMULADOS', '', accent: true)),
  ]);

  Widget _totalCell(String v, String l, String emoji,
      {bool accent = false}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _kBorder2)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(
                color:      accent ? _kBright : _kWhite,
                fontSize:   18,
                fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(
                color:         _kGrey,
                fontSize:      7,
                fontWeight:    FontWeight.w700,
                letterSpacing: 1.2)),
          ]),
        ]),
      );

  Widget _buildContextCards() {
    final cards = <Widget>[];
    if (widget.esDesdeCarrera && _rachaActual > 0) cards.add(_buildRachaCard());
    if (widget.esDesdeCarrera && _puntosLigaSesion > 0)
      cards.add(_buildLigaCard());
    if (widget.esDesdeCarrera && _territoriosConquistados > 0)
      cards.add(_buildConquistaCard());
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      const SizedBox(height: 18),
      ...cards.map((c) =>
          Padding(padding: const EdgeInsets.only(bottom: 8), child: c)),
    ]);
  }

  Widget _buildRachaCard() {
    final hitos = [3, 7, 14, 30];
    final hito  = hitos.firstWhere((h) => _rachaActual < h, orElse: () => 30);
    final pct   = (_rachaActual / hito).clamp(0.0, 1.0);
    return _contextCard(
      emoji:    '',
      tag:      'RACHA',
      headline: '$_rachaActual ${_rachaActual == 1 ? 'día' : 'días'} consecutivos',
      sub:      _rachaActual < 7
          ? 'Faltan ${7 - _rachaActual} días para la semana'
          : '¡Más de una semana sin parar!',
      color:    _kGrey,
      trailing: _ring(pct, '$_rachaActual/$hito', _kGrey),
    );
  }

  Widget _buildLigaCard() => _contextCard(
    emoji:    '',
    tag:      'LIGA',
    headline: '+$_puntosLigaSesion pts esta sesión',
    sub:      '$_totalPuntosLiga pts totales acumulados',
    color:    _kGold,
    trailing: _ring(
      (_totalPuntosLiga % 100) / 100.0,
      '+$_puntosLigaSesion',
      _kGold,
    ),
  );

  Widget _buildConquistaCard() => _contextCard(
    emoji:    '',
    tag:      'CONQUISTA',
    headline: '$_territoriosConquistados territorio${_territoriosConquistados == 1 ? '' : 's'} arrebatado${_territoriosConquistados == 1 ? '' : 's'}',
    sub:      'El rival ya ha sido notificado',
    color:    _kGrey,
  );

  Widget _contextCard({
    required String emoji,
    required String tag,
    required String headline,
    required String sub,
    required Color  color,
    Widget? trailing,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.05), blurRadius: 16),
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: color.withOpacity(0.2)),
            ),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tag, style: TextStyle(
                  color:         color,
                  fontSize:      8,
                  fontWeight:    FontWeight.w900,
                  letterSpacing: 2.5)),
              const SizedBox(height: 3),
              Text(headline, style: const TextStyle(
                  color: _kBright, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(color: _kGrey, fontSize: 11)),
            ],
          )),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing,
          ],
        ]),
      );

  Widget _ring(double value, String label, Color color) => SizedBox(
    width: 48, height: 48,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
        value:           value,
        strokeWidth:     2.5,
        backgroundColor: _kBorder2,
        valueColor:      AlwaysStoppedAnimation(color),
      ),
      Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color:      color,
              fontSize:   7,
              fontWeight: FontWeight.w900)),
    ]),
  );

  // ── Historial
  Widget _buildHistorial() {
    final lista    = (_verTodosLosLogros || _searchCtrl.text.isNotEmpty)
        ? _logrosFiltrados
        : _logrosFiltrados.take(_paginaTamanio * _paginaActual).toList();
    final mostrados = _verTodosLosLogros ? _logrosFiltrados : lista;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sectionLabel('HISTORIAL DE MISIONES')),
        if (todosLosLogros.length > 5)
          GestureDetector(
            onTap: () => setState(() {
              _verTodosLosLogros = !_verTodosLosLogros;
              if (!_verTodosLosLogros) {
                _searchCtrl.clear();
                _logrosFiltrados = todosLosLogros;
              }
            }),
            child: Text(
              _verTodosLosLogros ? 'MENOS' : 'TODO',
              style: const TextStyle(
                  color:         _kGrey,
                  fontSize:      8,
                  fontWeight:    FontWeight.w900,
                  letterSpacing: 2),
            ),
          ),
      ]),
      const SizedBox(height: 12),

      // Banner de reto completado
      if (_retoCompletadoEnSesion != null) ...[
        _buildBannerRetoCompletado(_retoCompletadoEnSesion!),
        const SizedBox(height: 16),
      ],

      if (_verTodosLosLogros) ...[
        TextField(
          controller: _searchCtrl,
          onChanged:  _filtrarBusqueda,
          style:      const TextStyle(color: _kWhite, fontSize: 13),
          decoration: InputDecoration(
            hintText:    'Buscar carrera...',
            hintStyle:   const TextStyle(color: _kGreyDim, fontSize: 13),
            prefixIcon:  const Icon(Icons.search_rounded,
                color: _kGrey, size: 16),
            filled:      true,
            fillColor:   _kSurface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kGrey, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 10),
      ],

      if (mostrados.isEmpty)
        const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sin carreras registradas',
              style: TextStyle(color: _kGreyDim, fontSize: 12)),
        ))
      else
        ...mostrados.asMap().entries.map((e) =>
            TweenAnimationBuilder<double>(
              tween:    Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 280 + e.key * 35),
              curve:    Curves.easeOut,
              builder: (_, v, child) => Opacity(
                opacity: v,
                child:   Transform.translate(
                    offset: Offset(16 * (1 - v), 0), child: child),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child:   _historialRow(e.key, e.value),
              ),
            )),
    ]);
  }

  Widget _buildBannerRetoCompletado(Map<String, dynamic> reto) {
    final premio = (reto['premio'] as num?)?.toInt() ?? 0;
    final titulo = reto['titulo'] as String? ?? 'Misión completada';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBg,
        border: Border(
          left:   const BorderSide(color: _kGold, width: 3),
          top:    BorderSide(color: _kGoldDim.withOpacity(0.5)),
          right:  BorderSide(color: _kGoldDim.withOpacity(0.5)),
          bottom: BorderSide(color: _kGoldDim.withOpacity(0.5)),
        ),
        boxShadow: [
          BoxShadow(color: _kGold.withOpacity(0.10), blurRadius: 20),
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8),
        ],
      ),
      child: Row(children: [
        TweenAnimationBuilder<double>(
          tween:    Tween(begin: 0.7, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve:    Curves.elasticOut,
          builder:  (_, v, child) =>
              Transform.scale(scale: v, child: child),
          child: const Text('', style: TextStyle(fontSize: 32)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('MISIÓN COMPLETADA', style: TextStyle(
                color:         _kGold,
                fontSize:      9,
                fontWeight:    FontWeight.w900,
                letterSpacing: 3)),
            const SizedBox(height: 3),
            Text(titulo, style: const TextStyle(
                color: _kBright, fontSize: 15, fontWeight: FontWeight.w800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              'Has completado este reto y se ha sumado a tus logros',
              style: TextStyle(
                  color:    _kGoldDim.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
        if (premio > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color:  _kGoldDim.withOpacity(0.15),
              border: Border.all(color: _kGoldDim.withOpacity(0.5)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('+$premio', style: const TextStyle(
                  color:      _kGold,
                  fontSize:   16,
                  fontWeight: FontWeight.w900,
                  height:     1)),
              const Text('PTS', style: TextStyle(
                  color:         _kGoldDim,
                  fontSize:      7,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 1.5)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _historialRow(int idx, Map<String, dynamic> d) {
    final dist       = (d['distancia'] as double? ?? 0);
    final recompensa = (d['recompensa'] as int? ?? 0);
    final isFirst    = idx == 0;
    final modo       = d['modo'] as String? ?? 'competitivo';
    final esGlobal   = modo == 'guerra_global';

    return Container(
      decoration: BoxDecoration(
        color:        _kSurface,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder2),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: esGlobal
                  ? _kGold
                  : (isFirst ? _kGrey : _kGreyDim),
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Text(
              '${idx + 1}'.padLeft(2, '0'),
              style: TextStyle(
                  color: esGlobal
                      ? _kGold
                      : (isFirst ? _kGrey : _kGreyDim),
                  fontSize:   10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5),
            ),
          ),
          Container(width: 1, color: _kBorder),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 11),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (esGlobal) ...[
                        const Text('',
                            style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          d['titulo'] ?? 'Carrera completada',
                          style: TextStyle(
                              color: esGlobal
                                  ? _kGold
                                  : (isFirst ? _kBright
                                      : _kWhite.withOpacity(0.75)),
                              fontSize:   12,
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        _kBorder2.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(4),
                          border:       Border.all(color: _kBorder2),
                        ),
                        child: Text('${dist.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color:      _kBright,
                                fontSize:   10,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Text(d['fecha'] ?? '--',
                          style: const TextStyle(
                              color: _kGrey, fontSize: 9)),
                    ]),
                  ],
                )),
                const SizedBox(width: 10),
                if (recompensa > 0)
                  Column(
                    mainAxisAlignment:  MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color:        _kBorder2.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                          border:       Border.all(color: _kBorder2),
                        ),
                        child: Text('+$recompensa', style: const TextStyle(
                            color:      _kBright,
                            fontSize:   11,
                            fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(height: 2),
                      const Text('PTS', style: TextStyle(
                          color:         _kGreyDim,
                          fontSize:      7,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 1)),
                    ],
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Acciones + botón de vuelta
  Widget _buildAcciones() => Column(children: [

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
          color: _kWhite,
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('', style: TextStyle(fontSize: 16)),
          SizedBox(width: 10),
          Text('PUBLICAR EN EL FEED', style: TextStyle(
              color:         _kBg,
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
        child:   Text('·',
            style: TextStyle(color: _kGreyDim, fontSize: 10)),
      ),
      Expanded(child: Container(height: 1, color: _kBorder2)),
    ]),

  ]);

  Widget _sectionLabel(String t) => Row(children: [
    Container(
      width: 3, height: 11,
      decoration: BoxDecoration(
          color:        _kGrey,
          borderRadius: BorderRadius.circular(2)),
    ),
    const SizedBox(width: 8),
    Text(t, style: const TextStyle(
        color:         _kGrey,
        fontSize:      8,
        fontWeight:    FontWeight.w900,
        letterSpacing: 3)),
  ]);
}

// =============================================================================
// WIDGET HELPER: Reveal
// =============================================================================
class _Reveal extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _Reveal({required this.anim, required this.child});

  @override
  Widget build(BuildContext ctx) => AnimatedBuilder(
    animation: anim,
    builder: (_, __) => Opacity(
      opacity: anim.value.clamp(0.0, 1.0),
      child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)), child: child),
    ),
  );
}

// =============================================================================
// PAINTERS
// =============================================================================
class _OperativeBg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = const Color(0xFFFFFFFF).withOpacity(0.03);
    const spacing = 32.0;
    for (double x = spacing / 2; x < size.width; x += spacing)
      for (double y = spacing / 2; y < size.height; y += spacing)
        canvas.drawCircle(Offset(x, y), 0.8, dot);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, -0.8), radius: 0.9,
          colors: [
            const Color(0xFFFFFFFF).withOpacity(0.025),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_OperativeBg old) => false;
}

class _ScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color       = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1;
    const step = 18.0;
    for (double y = step; y < size.height; y += step)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_ScanlinesPainter old) => false;
}