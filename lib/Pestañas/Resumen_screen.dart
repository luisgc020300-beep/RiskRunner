import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:RunnerRisk/Pestañas/Social_screen.dart';
import 'package:RunnerRisk/services/league_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../Widgets/custom_navbar.dart';
import '../services/territory_service.dart';
import '../services/stats_service.dart';
import '../widgets/stats_resumen_widget.dart';
import 'fullscreen_map_screen.dart';

// =============================================================================
// PALETA ACUARELA
// =============================================================================
const _kInk         = Color(0xFF0E0A04);
const _kBg          = Color(0xFF130E06);
const _kSurface     = Color(0xFF1E1608);
const _kSurface2    = Color(0xFF2A1F0F);
const _kBorder      = Color(0xFF3A2A14);
const _kBorder2     = Color(0xFF4A3520);
const _kGold        = Color(0xFFD4A84C);
const _kGoldLight   = Color(0xFFEDD98A);
const _kGoldDim     = Color(0xFF7A5E28);
const _kTerracotta  = Color(0xFFD4722A);
const _kWater       = Color(0xFF5BA3A0);
const _kWaterLight  = Color(0xFF8ECFCC);
const _kVerde       = Color(0xFF8FAF4A);
const _kDim         = Color(0xFF7A6540);
const _kMuted       = Color(0xFF4A3A20);

// =============================================================================
// MAPBOX
// =============================================================================
const _kMapboxToken =
    'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1keTI1bjkwN25qMm9zNzFlOXZkeG9wIn0.l186BxbIhi6-vAXtBjIzsw';
const _kMapboxStyleId = 'luiisgoomezz1/cmmdzh1aj00f501r68crag5gv';
const _kMapboxTileUrl =
    'https://api.mapbox.com/styles/v1/$_kMapboxStyleId/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

// =============================================================================
// PANTALLA
// =============================================================================
class ResumenScreen extends StatefulWidget {
  final String? targetUserId;
  final String? targetNickname;
  final double distancia;
  final Duration tiempo;
  final List<LatLng> ruta;
  final List<Map<String, dynamic>> logrosCompletados;
  final int? timestamp;
  final bool esDesdeCarrera;

  const ResumenScreen({
    super.key,
    this.targetUserId,
    this.targetNickname,
    required this.distancia,
    required this.tiempo,
    required this.ruta,
    this.logrosCompletados = const [],
    this.timestamp,
    this.esDesdeCarrera = false,
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

  // ── Datos
  final MapController _mapController = MapController();
  String userId = '';
  bool isLoading = true;
  LatLng? _centroMapa;

  int monedasTotalesHistorial = 0;
  int retosTotalesHistorial   = 0;
  List<Map<String, dynamic>> todosLosLogros = [];
  bool _verTodosLosLogros = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _logrosFiltrados = [];

  List<TerritoryData> _territoriosEnMapa = [];
  Color _acento = _kTerracotta;

  int _territoriosConquistados = 0;
  int _rachaActual             = 0;
  int _puntosLigaSesion        = 0;
  double _distMostrada         = 0;

  // ── Story
  bool _generandoStory = false;
  final GlobalKey _storyKey = GlobalKey();

  CarreraStats? _carreraActual;
  List<CarreraStats> _historialStats = [];

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
        vsync: this, duration: const Duration(milliseconds: 80))
      ..repeat(reverse: true);
    _glitch = Tween<double>(begin: 0, end: 1).animate(_glitchCtrl);

    userId = widget.targetUserId ??
        FirebaseAuth.instance.currentUser?.uid ?? '';
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
    await _cargarUbicacionInicial();
    await _cargarColorUsuario();
    if (widget.esDesdeCarrera) {
      await _guardarActivityLog();
      await _guardarYMostrarTerritorioActual();
      await _actualizarRacha();
    } else {
      await _cargarTodosLosTerritorios();
    }
    await Future.delayed(const Duration(milliseconds: 200));
    await _cargarHistorialTotal();
    _cargarStatsResumen();
    if (widget.esDesdeCarrera && mounted) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final int c = (args?['territoriosConquistados'] as int?) ?? 0;
      final int p = (args?['puntosLigaGanados'] as int?) ?? 0;
      if (c > 0) { setState(() => _territoriosConquistados = c); _mostrarBannerConquista(c); }
      if (p > 0) setState(() => _puntosLigaSesion = p);
    }
    if (mounted) {
      HapticFeedback.mediumImpact();
      _masterCtrl.forward();
      Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _odometroCtrl.forward(); });
      Future.delayed(const Duration(milliseconds: 700), () { if (mounted) _rutaCtrl.forward(); });
      Future.delayed(const Duration(milliseconds: 600), () { if (mounted) _glitchCtrl.stop(); });
    }
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
        'userId': userId,
        'distancia': widget.distancia,
        'tiempo_segundos': widget.tiempo.inSeconds,
        'velocidad_media': horas > 0 ? widget.distancia / horas : 0.0,
        'timestamp': FieldValue.serverTimestamp(),
        'fecha_dia': '${ahora.year}-${ahora.month.toString().padLeft(2,'0')}-${ahora.day.toString().padLeft(2,'0')}',
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
      await ref.update({'racha_actual': nueva, 'ultima_fecha_actividad': Timestamp.now()});
      if (mounted) setState(() => _rachaActual = nueva);
      if (mounted && nueva > 1) _mostrarBannerRacha(nueva);
    } catch (e) { debugPrint('Error racha: $e'); }
  }

  void _mostrarBannerRacha(int r) => Future.delayed(const Duration(milliseconds: 900), () {
    if (!mounted) return;
    _snack('🔥', '¡Racha de $r días!',
        r >= 7 ? '🏆 Una semana seguida conquistando' : 'Sigue así, conquistador', _kGold);
  });

  void _mostrarBannerConquista(int n) => Future.delayed(const Duration(milliseconds: 600), () {
    if (!mounted) return;
    _snack('⚔️', '¡Territorio conquistado!',
        n == 1 ? '1 rival eliminado del mapa' : '$n rivales eliminados', _kTerracotta);
  });

  void _snack(String emoji, String title, String sub, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.transparent, elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _kSurface2, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 16)],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w800, fontSize: 14)),
            Text(sub, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
          ])),
        ]),
      ),
    ));
  }

  Future<void> _cargarColorUsuario() async {
    if (userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('players').doc(userId).get();
      if (doc.exists) {
        final c = (doc.data()?['territorio_color'] as num?)?.toInt();
        if (c != null && mounted) setState(() => _acento = Color(c));
      }
    } catch (_) {}
  }

  Future<void> _cargarUbicacionInicial() async {
    _centroMapa = widget.ruta.isNotEmpty
        ? widget.ruta.first : const LatLng(37.1350, -3.6330);
    if (mounted) setState(() {});
  }

  Future<void> _guardarYMostrarTerritorioActual() async {
    if (widget.ruta.length < 2) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('territories').add({
        'userId': user.uid,
        'puntos': widget.ruta.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      await LeagueService.sumarPuntosLiga(user.uid, 15);
      final latC = widget.ruta.map((p) => p.latitude).reduce((a, b) => a + b) / widget.ruta.length;
      final lngC = widget.ruta.map((p) => p.longitude).reduce((a, b) => a + b) / widget.ruta.length;
      if (mounted) setState(() {
        _territoriosEnMapa = [TerritoryData(
          docId: 'nuevo', ownerId: user.uid, ownerNickname: 'YO',
          color: _acento, puntos: widget.ruta,
          centro: LatLng(latC, lngC), esMio: true, ultimaVisita: DateTime.now(),
        )];
      });
    } catch (e) { debugPrint('Error territorio: $e'); }
  }

  Future<void> _cargarTodosLosTerritorios() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('territories')
          .where('userId', isEqualTo: userId).get().timeout(const Duration(seconds: 6));
      final res = <TerritoryData>[];
      for (var doc in snap.docs) {
        final data = doc.data();
        final raw  = data['puntos'] as List<dynamic>?;
        if (raw == null || raw.isEmpty) continue;
        final pts  = raw.map((p) {
          final m = p as Map<String, dynamic>;
          return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        }).toList();
        final latC = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
        final lngC = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
        DateTime? uv;
        final ts = data['ultima_visita'];
        if (ts is Timestamp) uv = ts.toDate();
        res.add(TerritoryData(
          docId: doc.id, ownerId: userId, ownerNickname: 'YO',
          color: _acento, puntos: pts, centro: LatLng(latC, lngC),
          esMio: true, ultimaVisita: uv,
        ));
      }
      if (mounted) setState(() => _territoriosEnMapa = res);
    } catch (e) { debugPrint('Error territorios: $e'); }
  }

  Future<void> _cargarHistorialTotal() async {
    if (userId.isEmpty) return;
    if (mounted) setState(() => isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('activity_logs')
          .where('userId', isEqualTo: userId).get().timeout(const Duration(seconds: 5));
      final lista = <Map<String, dynamic>>[];
      int monedas = 0;
      for (var doc in snap.docs) {
        final d = doc.data();
        lista.add({
          'titulo': d['titulo'] ?? 'Carrera completada',
          'recompensa': (d['recompensa'] as num? ?? 0).toInt(),
          'fecha': d['fecha_dia'] ?? 'Reciente',
          'timestamp': d['timestamp'],
          'distancia': (d['distancia'] as num? ?? 0).toDouble(),
        });
        monedas += (d['recompensa'] as num? ?? 0).toInt();
      }
      lista.sort((a, b) {
        final ta = a['timestamp'] as Timestamp?;
        final tb = b['timestamp'] as Timestamp?;
        if (ta == null || tb == null) return 0;
        return tb.compareTo(ta);
      });
      if (mounted) setState(() {
        todosLosLogros          = lista;
        _logrosFiltrados        = lista;
        retosTotalesHistorial   = lista.length;
        monedasTotalesHistorial = monedas;
        isLoading               = false;
      });
    } catch (e) {
      debugPrint('Error historial: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filtrarBusqueda(String q) => setState(() {
    _logrosFiltrados = todosLosLogros
        .where((l) => l['titulo'].toString().toLowerCase().contains(q.toLowerCase()))
        .toList();
  });

  Future<void> _compartirEnFeed(BuildContext ctx) async {
    if (userId.isEmpty) return;
    final ctrl = TextEditingController();
    HapticFeedback.lightImpact();
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: _kSurface2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (bCtx) {
        bool pub = false;
        return StatefulBuilder(builder: (bCtx, setM) => Padding(
          padding: EdgeInsets.only(
              left: 24, right: 24, top: 20,
              bottom: MediaQuery.of(bCtx).viewInsets.bottom + 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                  width: 32, height: 4,
                  decoration: BoxDecoration(
                      color: _kBorder2, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 22),
              _tagLabel('PUBLICAR EN FEED'),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _acento.withValues(alpha: 0.3))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _feedNum(widget.distancia.toStringAsFixed(2), 'KM'),
                    Container(width: 1, height: 30, color: _kBorder2),
                    _feedNum(
                        '${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:'
                        '${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}',
                        'TIEMPO'),
                    Container(width: 1, height: 30, color: _kBorder2),
                    _feedNum(
                        widget.tiempo.inSeconds > 0
                            ? (widget.distancia / (widget.tiempo.inSeconds / 3600))
                                .toStringAsFixed(1)
                            : '0.0',
                        'KM/H'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(
                  hintText: '¿Qué tal fue la carrera?',
                  hintStyle: const TextStyle(color: _kDim, fontSize: 13),
                  filled: true,
                  fillColor: _kBg,
                  counterStyle: const TextStyle(color: _kDim, fontSize: 11),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kBorder2)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kBorder2)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _acento, width: 1.5)),
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
                          .collection('players')
                          .doc(userId)
                          .get();
                      final pd = playerDoc.data() ?? {};
                      final velMedia = widget.tiempo.inSeconds > 0
                          ? widget.distancia / (widget.tiempo.inSeconds / 3600)
                          : 0.0;
                      await FirebaseFirestore.instance.collection('posts').add({
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
                      debugPrint('✅ Post publicado en Firestore para userId: $userId');
                      if (bCtx.mounted) {
                        Navigator.pop(bCtx);
                        _snack('🚀', '¡Publicado!',
                            'Tu conquista ya está en el feed', _kGold);
                      }
                    } catch (e) {
                      debugPrint('❌ Error publicando post: $e');
                      setM(() => pub = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _acento,
                    foregroundColor: _kInk,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: pub
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: _kInk, strokeWidth: 2))
                      : const Text('PUBLICAR',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 2.5)),
                ),
              ),
            ],
          ),
        ));
      },
    );
  }

  Widget _feedNum(String v, String l) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(v, style: TextStyle(
            color: _acento, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(l, style: const TextStyle(
            color: _kDim, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ]);

  // ==========================================================================
  // STORY 9:16 — captura y comparte
  // ==========================================================================
  Future<void> _compartirStory() async {
    if (_generandoStory) return;
    HapticFeedback.mediumImpact();
    setState(() => _generandoStory = true);
    try {
      // Pequeña pausa para que el widget esté renderizado
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _storyKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('RenderObject no encontrado');
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo capturar la imagen');
      final bytes = byteData.buffer.asUint8List();
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/runner_risk_story.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '🏃 Acabo de conquistar territorio en Runner Risk\n'
            '${widget.distancia.toStringAsFixed(2)} km • '
            '${widget.tiempo.inMinutes}min\n'
            '#RunnerRisk #Conquista',
      );
    } catch (e) {
      debugPrint('Error generando story: $e');
      if (mounted) _snack('⚠️', 'Error al generar la imagen', 'Inténtalo de nuevo', _kTerracotta);
    } finally {
      if (mounted) setState(() => _generandoStory = false);
    }
  }

  Widget _buildStoryCard() {
    const double w = 360;
    const double h = 640;
    final horas = widget.tiempo.inSeconds / 3600;
    final vel   = horas > 0 && widget.distancia > 0 ? widget.distancia / horas : 0.0;
    final mpk   = vel > 0.5 ? 60.0 / vel : 0.0;
    final ritmo = mpk > 0
        ? "${mpk.floor()}'${((mpk - mpk.floor()) * 60).round().toString().padLeft(2, '0')}\""
        : '--';
    final tiempo = '${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:'
        '${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}';
    final ahora = DateTime.now();
    const meses = ['ENE','FEB','MAR','ABR','MAY','JUN','JUL','AGO','SEP','OCT','NOV','DIC'];
    final fecha = '${ahora.day.toString().padLeft(2,'0')} ${meses[ahora.month - 1]} ${ahora.year}';

    return RepaintBoundary(
      key: _storyKey,
      child: SizedBox(
        width: w, height: h,
        child: ClipRect(
          child: Container(
            width: w, height: h,
            decoration: const BoxDecoration(color: Color(0xFF0A0704)),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _StoryBgPainter(acento: _acento))),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 52, 28, 40),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: _acento.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _acento.withValues(alpha: 0.4)),
                      ),
                      child: const Center(child: Text('⚔', style: TextStyle(fontSize: 16))),
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('RUNNER RISK', style: TextStyle(
                          color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w900, letterSpacing: 2)),
                      Text(fecha, style: TextStyle(color: _acento, fontSize: 9, letterSpacing: 1)),
                    ]),
                  ]),
                  const SizedBox(height: 44),
                  Text('DISTANCIA', style: TextStyle(
                      color: _acento, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(widget.distancia.toStringAsFixed(2), style: const TextStyle(
                        color: Colors.white, fontSize: 82, fontWeight: FontWeight.w900,
                        height: 0.9, letterSpacing: -2,
                        shadows: [Shadow(color: Color(0xFFD4A84C), blurRadius: 30)])),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10, left: 8),
                      child: Text('KM', style: TextStyle(
                          color: Color(0xFFD4A84C), fontSize: 24,
                          fontWeight: FontWeight.w900, letterSpacing: 2)),
                    ),
                  ]),
                  const SizedBox(height: 28),
                  Row(children: [
                    _storyMetric(tiempo, 'TIEMPO', '⏱'),
                    _storyDivider(),
                    _storyMetric(ritmo, 'MIN/KM', '🏃'),
                    _storyDivider(),
                    _storyMetric(vel.toStringAsFixed(1), 'KM/H', '⚡'),
                  ]),
                  const SizedBox(height: 28),
                  Container(height: 1, color: _acento.withValues(alpha: 0.2)),
                  const SizedBox(height: 24),
                  if (_territoriosConquistados > 0)
                    _storyBadge('⚔️',
                      '$_territoriosConquistados territorio'
                      '${_territoriosConquistados == 1 ? '' : 's'} conquistado'
                      '${_territoriosConquistados == 1 ? '' : 's'}',
                      _kTerracotta),
                  if (_rachaActual > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _storyBadge('🔥', 'Racha de $_rachaActual días', _kGold),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _acento.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _acento.withValues(alpha: 0.35)),
                    ),
                    child: Row(children: [
                      const Text('🏙️', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('CONQUISTA TU TERRITORIO', style: TextStyle(
                            color: Colors.white, fontSize: 11,
                            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        Text('runnerrisk.app', style: TextStyle(
                            color: _acento, fontSize: 10, letterSpacing: 1)),
                      ])),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _storyMetric(String value, String label, String emoji) =>
      Expanded(child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(
            color: _acento, fontSize: 8,
            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ]));

  Widget _storyDivider() => Container(width: 1, height: 40, color: _kBorder2);

  Widget _storyBadge(String emoji, String text, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      );

  // ==========================================================================
  // BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    if (isLoading || _centroMapa == null) return _buildLoading();
    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 2),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _ParchmentBg(acento: _acento))),
        SafeArea(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _Reveal(anim: _headerReveal, child: _buildHeader()),
            const SizedBox(height: 32),

            _Reveal(anim: _heroReveal, child: _buildHeroOdometro()),
            const SizedBox(height: 14),

            _Reveal(anim: _heroReveal, child: _buildSecondaryMetrics()),
            const SizedBox(height: 24),

            _Reveal(anim: _mapReveal, child: _buildMapSection()),
            const SizedBox(height: 20),

            if (widget.esDesdeCarrera && _carreraActual != null)
              _Reveal(
                anim: _statsReveal,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: StatsResumenWidget(
                    carreraActual: _carreraActual!,
                    historial: _historialStats,
                  ),
                ),
              ),

            _Reveal(anim: _statsReveal, child: _buildTotalesRow()),
            _Reveal(anim: _cardsReveal, child: _buildContextCards()),
            const SizedBox(height: 28),
            _Reveal(anim: _cardsReveal, child: _buildHistorial()),
            const SizedBox(height: 28),
            _Reveal(anim: _cardsReveal, child: _buildAcciones()),
          ]),
        )),
      ]),
    );
  }

  // ── Loading
  Widget _buildLoading() => Scaffold(
    backgroundColor: _kBg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
        Container(width: 72, height: 72,
          decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(
                  color: _kGold.withValues(alpha: _pulse.value), width: 2)),
          child: const Center(
              child: Text('🏴', style: TextStyle(fontSize: 28))))),
      const SizedBox(height: 20),
      const Text('PROCESANDO MISIÓN', style: TextStyle(
          color: _kGold, fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 4)),
    ])),
  );

  // ── Header
  Widget _buildHeader() {
    final titulo = widget.targetNickname != null
        ? widget.targetNickname!.toUpperCase() : 'INFORME DE CAMPAÑA';
    final ahora  = DateTime.now();
    const meses  = ['ENE','FEB','MAR','ABR','MAY','JUN',
                     'JUL','AGO','SEP','OCT','NOV','DIC'];
    final fecha  = '${ahora.day.toString().padLeft(2,'0')} '
        '${meses[ahora.month-1]} ${ahora.year}';
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (Navigator.canPop(context))
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
          child: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: _kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder2)),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _kDim, size: 15)),
        )
      else const SizedBox(width: 40),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glitchCtrl, builder: (_, __) {
          final s = (_glitch.value > 0.5) ? 1.5 : 0.0;
          return Stack(children: [
            Transform.translate(offset: Offset(s, 0),
              child: Text(titulo, style: TextStyle(
                  color: _kGold.withValues(alpha: 0.3),
                  fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
            Text(titulo, style: const TextStyle(color: Colors.white,
                fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ]);
        }),
        const SizedBox(height: 3),
        Row(children: [
          Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: _kGold, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(fecha, style: const TextStyle(
              color: _kDim, fontSize: 11, letterSpacing: 1)),
        ]),
      ])),
      AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _kGold.withValues(alpha: _pulse.value * 0.5 + 0.08)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 5, height: 5, decoration: BoxDecoration(
                color: _kGold, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _kGold, blurRadius: 4)])),
            const SizedBox(width: 6),
            Text('HOY', style: TextStyle(color: _kGold, fontSize: 9,
                fontWeight: FontWeight.w900, letterSpacing: 2.5)),
          ]),
        )),
    ]);
  }

  // ── Hero odómetro
  Widget _buildHeroOdometro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(color: _kGold.withValues(alpha: 0.07), blurRadius: 40),
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12),
        ],
      ),
      child: Stack(children: [
        Positioned.fill(child: IgnorePointer(
            child: CustomPaint(painter: _ParchmentLines(color: _kGold)))),
        Positioned(top: -4, right: -4, child: Opacity(opacity: 0.04,
            child: CustomPaint(painter: _HexPainter(color: _kGoldLight),
                size: const Size(88, 88)))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tagLabel('DISTANCIA TOTAL'),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_distMostrada.toStringAsFixed(2),
              style: const TextStyle(
                color: Colors.white, fontSize: 80,
                fontWeight: FontWeight.w900, height: 0.95, letterSpacing: -2,
                shadows: [
                  Shadow(color: _kGold, blurRadius: 28),
                  Shadow(color: Color(0x44D4A84C), blurRadius: 60),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(bottom: 10, left: 8),
              child: Text('KM', style: TextStyle(
                  color: _kGold, fontSize: 26,
                  fontWeight: FontWeight.w900, letterSpacing: 3))),
          ]),
          const SizedBox(height: 6),
          AnimatedBuilder(animation: _odometroCtrl, builder: (_, __) =>
            ClipRRect(borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _odometroCtrl.value,
                backgroundColor: _kBorder,
                valueColor: const AlwaysStoppedAnimation(_kGold),
                minHeight: 2,
              ),
            )),
        ]),
      ]),
    );
  }

  // ── Métricas secundarias
  Widget _buildSecondaryMetrics() {
    final horas = widget.tiempo.inSeconds / 3600;
    final vel   = horas > 0 && widget.distancia > 0
        ? widget.distancia / horas : 0.0;
    final ritmo = vel > 0.5 ? () {
      final mpk = 60.0 / vel;
      final min = mpk.floor();
      final seg = ((mpk - min) * 60).round();
      return "$min'${seg.toString().padLeft(2,'0')}\"";
    }() : '--:--';
    final tiempo = '${widget.tiempo.inMinutes.toString().padLeft(2,'0')}:'
        '${(widget.tiempo.inSeconds % 60).toString().padLeft(2,'0')}';
    return Row(children: [
      Expanded(child: _metricTile(tiempo, 'TIEMPO', '⏱')),
      const SizedBox(width: 10),
      Expanded(child: _metricTile(ritmo, 'MIN/KM', '🏃')),
      const SizedBox(width: 10),
      Expanded(child: _metricTile(
          vel.toStringAsFixed(1), 'KM/H', '⚡', accent: true)),
    ]);
  }

  Widget _metricTile(String v, String l, String emoji,
      {bool accent = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: _kSurface, borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: accent
                  ? _acento.withValues(alpha: 0.35) : _kBorder),
          boxShadow: accent
              ? [BoxShadow(
                  color: _acento.withValues(alpha: 0.07), blurRadius: 12)]
              : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Text(v, style: TextStyle(
              color: accent ? _acento : Colors.white,
              fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(l, style: const TextStyle(
              color: _kDim, fontSize: 8,
              fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        ]),
      );

  // ── Mapa
  Widget _buildMapSection() {
    final tieneRuta = widget.ruta.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tagLabel('TERRITORIO CONQUISTADO'),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
              FullscreenMapScreen(
                territorios: _territoriosEnMapa,
                colorTerritorio: _acento,
                centroInicial: _centroMapa!,
                ruta: widget.ruta,
                mostrarRuta: widget.esDesdeCarrera,
              )));
        },
        child: Container(
          height: 210,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kGold.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                  color: _kGold.withValues(alpha: 0.08), blurRadius: 20),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4), blurRadius: 8),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _centroMapa!, initialZoom: 15,
                  onMapReady: () {
                    if (tieneRuta) _mapController.fitCamera(
                        CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(widget.ruta),
                            padding: const EdgeInsets.all(52)));
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: _kMapboxTileUrl,
                    userAgentPackageName: 'com.runner_risk.app',
                    tileSize: 256,
                    additionalOptions: const {'accessToken': _kMapboxToken},
                  ),
                  if (_territoriosEnMapa.isNotEmpty)
                    PolygonLayer(polygons: _territoriosEnMapa.map((t) =>
                        Polygon(
                          points: t.puntos,
                          color: t.color.withValues(alpha: 0.45),
                          borderColor: t.color,
                          borderStrokeWidth: 2.5,
                        )).toList()),
                  if (tieneRuta && widget.esDesdeCarrera)
                    AnimatedBuilder(
                        animation: _rutaProgress,
                        builder: (_, __) {
                          final n = (widget.ruta.length * _rutaProgress.value)
                              .round().clamp(2, widget.ruta.length);
                          return PolylineLayer(polylines: [
                            Polyline(
                                points: widget.ruta.sublist(0, n),
                                strokeWidth: 8.0,
                                color: _kGold.withValues(alpha: 0.2)),
                            Polyline(
                                points: widget.ruta.sublist(0, n),
                                strokeWidth: 3.5,
                                color: _acento),
                          ]);
                        }),
                  if (!tieneRuta)
                    MarkerLayer(markers: [
                      Marker(
                          point: _centroMapa!,
                          child: Icon(Icons.location_on,
                              color: _acento, size: 28))
                    ]),
                ],
              ),
              Positioned.fill(child: IgnorePointer(
                  child: DecoratedBox(decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: RadialGradient(
                        center: Alignment.center, radius: 1.1,
                        colors: [
                          Colors.transparent,
                          _kInk.withValues(alpha: 0.25)
                        ]),
                  )))),
              Positioned(top: 10, left: 10,
                  child: _mapBadge(
                      '${_territoriosEnMapa.length} zona'
                      '${_territoriosEnMapa.length == 1 ? '' : 's'}',
                      '🏴')),
              Positioned(top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: _kParchment.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder2)),
                    child: const Icon(Icons.open_in_full_rounded,
                        color: _kDim, size: 13),
                  )),
              Positioned(bottom: 0, left: 0, right: 0,
                child: AnimatedBuilder(
                    animation: _rutaProgress,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _rutaProgress.value,
                      backgroundColor: Colors.black.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation(
                          _kGold.withValues(alpha: 0.75)),
                      minHeight: 3,
                    ))),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _mapBadge(String text, String emoji) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: _kParchment.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kGold.withValues(alpha: 0.45))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 10)),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(
          color: _kGoldLight, fontSize: 10, fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _buildTotalesRow() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Expanded(child: _totalCell(
          retosTotalesHistorial.toString(), 'CARRERAS TOTALES', '🏃')),
      const SizedBox(width: 10),
      Expanded(child: _totalCell(
          monedasTotalesHistorial.toString(),
          'PUNTOS ACUMULADOS', '⚡', accent: true)),
    ]),
  );

  Widget _totalCell(String v, String l, String emoji,
      {bool accent = false}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _kSurface, borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: accent
                    ? _acento.withValues(alpha: 0.3) : _kBorder)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(
                color: accent ? _acento : Colors.white,
                fontSize: 20, fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(
                color: _kDim, fontSize: 8,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ]),
        ]),
      );

  Widget _buildContextCards() {
    final cards = <Widget>[];
    if (widget.esDesdeCarrera && _rachaActual > 0)
      cards.add(_buildRachaCard());
    if (widget.esDesdeCarrera && _puntosLigaSesion > 0)
      cards.add(_buildLigaCard());
    if (widget.esDesdeCarrera && _territoriosConquistados > 0)
      cards.add(_buildConquistaCard());
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      const SizedBox(height: 20),
      ...cards.map((c) =>
          Padding(padding: const EdgeInsets.only(bottom: 10), child: c)),
    ]);
  }

  Widget _buildRachaCard() {
    final hitos = [3, 7, 14, 30];
    final hito  = hitos.firstWhere(
        (h) => _rachaActual < h, orElse: () => 30);
    final pct   = (_rachaActual / hito).clamp(0.0, 1.0);
    return _contextCard(
      emoji: '🔥', tag: 'RACHA',
      headline: '$_rachaActual '
          '${_rachaActual == 1 ? 'día' : 'días'} consecutivos',
      sub: _rachaActual < 7
          ? 'Faltan ${7 - _rachaActual} días para la semana'
          : '¡Más de una semana sin parar!',
      color: _kGold,
      trailing: _ring(pct, '$_rachaActual/$hito', _kGold),
    );
  }

  Widget _buildLigaCard() => FutureBuilder<DocumentSnapshot>(
    future: FirebaseFirestore.instance
        .collection('players').doc(userId).get(),
    builder: (_, snap) {
      int total = 0;
      if (snap.hasData && snap.data!.exists)
        total = ((snap.data!.data() as Map<String, dynamic>)
                ['puntos_liga'] as num? ?? 0)
            .toInt();
      final liga = LeagueHelper.getLeague(total);
      return _contextCard(
        emoji: liga.emoji,
        tag: 'LIGA — ${liga.name.toUpperCase()}',
        headline: '+$_puntosLigaSesion pts esta sesión',
        sub: '$total pts totales acumulados',
        color: liga.color,
        trailing: _ring(
            (total % 100) / 100.0, '+$_puntosLigaSesion', liga.color),
      );
    },
  );

  Widget _buildConquistaCard() => _contextCard(
    emoji: '⚔️', tag: 'CONQUISTA',
    headline: '$_territoriosConquistados territorio'
        '${_territoriosConquistados == 1 ? '' : 's'} arrebatado'
        '${_territoriosConquistados == 1 ? '' : 's'}',
    sub: 'El rival ya ha sido notificado',
    color: _kTerracotta,
  );

  Widget _contextCard({
    required String emoji, required String tag,
    required String headline, required String sub,
    required Color color, Widget? trailing,
  }) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.06), blurRadius: 20),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          Container(width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Center(
                child: Text(emoji,
                    style: const TextStyle(fontSize: 22)))),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(tag, style: TextStyle(
                color: color, fontSize: 9,
                fontWeight: FontWeight.w900, letterSpacing: 2.5)),
            const SizedBox(height: 4),
            Text(headline, style: const TextStyle(
                color: Colors.white,
                fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(
                color: _kDim, fontSize: 12)),
          ])),
          if (trailing != null) ...[
            const SizedBox(width: 12), trailing
          ],
        ]),
      );

  Widget _ring(double value, String label, Color color) => SizedBox(
    width: 52, height: 52,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
          value: value, strokeWidth: 3,
          backgroundColor: _kBorder2,
          valueColor: AlwaysStoppedAnimation(color)),
      Text(label, textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontSize: 8, fontWeight: FontWeight.w900)),
    ]),
  );

  Widget _buildHistorial() {
    final lista = (_verTodosLosLogros || _searchCtrl.text.isNotEmpty)
        ? _logrosFiltrados : todosLosLogros.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _tagLabel('HISTORIAL DE MISIONES')),
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
                    color: _kGold, fontSize: 9,
                    fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
      ]),
      const SizedBox(height: 14),
      if (_verTodosLosLogros) ...[
        TextField(
          controller: _searchCtrl, onChanged: _filtrarBusqueda,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar carrera...',
            hintStyle: const TextStyle(color: _kDim, fontSize: 13),
            prefixIcon: const Icon(
                Icons.search_rounded, color: _kGold, size: 17),
            filled: true, fillColor: _kSurface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kGold, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (lista.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('Sin carreras registradas',
              style: TextStyle(color: _kDim, fontSize: 13))))
      else
        ...lista.asMap().entries.map((e) =>
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 300 + e.key * 50),
              curve: Curves.easeOut,
              builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                      offset: Offset(20 * (1 - v), 0), child: child)),
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _historialRow(e.key, e.value)),
            )),
    ]);
  }

  Widget _historialRow(int idx, Map<String, dynamic> d) {
    final dist = (d['distancia'] as double? ?? 0).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
          color: _kSurface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      child: Row(children: [
        SizedBox(width: 24, child: Text('${idx + 1}',
            style: TextStyle(
                color: _kGold.withValues(alpha: 0.55),
                fontSize: 12, fontWeight: FontWeight.w900))),
        const SizedBox(width: 4),
        Container(width: 1, height: 28, color: _kBorder2),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d['titulo'], style: const TextStyle(
              color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Row(children: [
            Text('$dist km', style: TextStyle(
                color: _kGold.withValues(alpha: 0.75), fontSize: 11)),
            const SizedBox(width: 8),
            const Text('·', style: TextStyle(color: _kMuted)),
            const SizedBox(width: 8),
            Text(d['fecha'],
                style: const TextStyle(color: _kDim, fontSize: 11)),
          ]),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _kGold.withValues(alpha: 0.18))),
          child: Text('+${d['recompensa']}',
              style: const TextStyle(
                  color: _kGold, fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Widget _buildAcciones() => Column(children: [

    // ── Botón COMPARTIR STORY (principal)
    GestureDetector(
      onTap: _compartirStory,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              _acento.withValues(alpha: _generandoStory ? 0.05 : 0.18),
              _acento.withValues(alpha: _generandoStory ? 0.02 : 0.08),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(
              color: _acento.withValues(alpha: _generandoStory ? 0.2 : 0.6),
              width: 1.5),
          boxShadow: _generandoStory ? [] : [
            BoxShadow(color: _acento.withValues(alpha: 0.12), blurRadius: 20),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_generandoStory)
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: _acento, strokeWidth: 2))
          else
            const Text('📲', style: TextStyle(fontSize: 17)),
          const SizedBox(width: 10),
          Text(
            _generandoStory ? 'GENERANDO...' : 'COMPARTIR EN STORIES',
            style: TextStyle(
              color: _generandoStory ? _kDim : _acento,
              fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2.5,
            ),
          ),
        ]),
      ),
    ),

    const SizedBox(height: 10),

    // ── Botón PUBLICAR EN FEED (secundario)
    GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); _compartirEnFeed(context); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder2),
          color: _kSurface,
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('📡', style: TextStyle(fontSize: 15)),
          SizedBox(width: 10),
          Text('PUBLICAR EN EL FEED', style: TextStyle(
              color: _kDim, fontSize: 11,
              fontWeight: FontWeight.w900, letterSpacing: 2)),
        ]),
      ),
    ),

    const SizedBox(height: 16),

    // ── Story card offscreen (invisible, solo para captura)
    Opacity(
      opacity: 0,
      child: SizedBox(
        width: 1, height: 1,
        child: OverflowBox(
          maxWidth: 360, maxHeight: 640,
          alignment: Alignment.topLeft,
          child: _buildStoryCard(),
        ),
      ),
    ),
  ]);

  Widget _tagLabel(String t) => Row(children: [
    Container(width: 3, height: 12, decoration: BoxDecoration(
        color: _kGold, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(t, style: const TextStyle(
        color: _kGold, fontSize: 9,
        fontWeight: FontWeight.w900, letterSpacing: 3)),
  ]);

  static const Color _kParchment = Color(0xFF2A1F0F);
}

// =============================================================================
// WIDGET HELPER: Reveal animado
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
          offset: Offset(0, 22 * (1 - anim.value)), child: child),
    ),
  );
}

// =============================================================================
// PAINTERS
// =============================================================================
class _ParchmentBg extends CustomPainter {
  final Color acento;
  const _ParchmentBg({required this.acento});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.65), radius: 1.1,
        colors: [
          const Color(0xFFD4A84C).withValues(alpha: 0.07),
          Colors.transparent
        ],
      ).createShader(rect));

    final dot = Paint()
      ..color = const Color(0xFFD4A84C).withValues(alpha: 0.05);
    const spacing = 36.0;
    for (double x = spacing / 2; x < size.width; x += spacing)
      for (double y = spacing / 2; y < size.height; y += spacing)
        canvas.drawCircle(Offset(x, y), 1, dot);

    final lp = Paint()
      ..color = const Color(0xFFD4A84C).withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (int i = 0; i < 12; i++) {
      final o = i * 18.0;
      canvas.drawLine(Offset(size.width - 90 + o, 0),
          Offset(size.width + o, 90), lp);
    }

    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.15)
          ],
        ).createShader(Rect.fromLTWH(
            0, size.height * 0.7, size.width, size.height * 0.3)),
    );
  }

  @override
  bool shouldRepaint(_ParchmentBg old) => old.acento != acento;
}

class _ParchmentLines extends CustomPainter {
  final Color color;
  const _ParchmentLines({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 22.0;
    for (double y = step; y < size.height; y += step)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_ParchmentLines old) => old.color != color;
}

class _StoryBgPainter extends CustomPainter {
  final Color acento;
  const _StoryBgPainter({required this.acento});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.7, -0.8), radius: 1.2,
          colors: [acento.withValues(alpha: 0.12), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    final dot = Paint()..color = acento.withValues(alpha: 0.06);
    const spacing = 36.0;
    for (double x = spacing / 2; x < size.width; x += spacing)
      for (double y = spacing / 2; y < size.height; y += spacing)
        canvas.drawCircle(Offset(x, y), 1, dot);
    final lp = Paint()
      ..color = acento.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (int i = 0; i < 10; i++) {
      final o = i * 20.0;
      canvas.drawLine(Offset(size.width - 80 + o, 0), Offset(size.width + o, 80), lp);
    }
  }

  @override
  bool shouldRepaint(_StoryBgPainter old) => old.acento != acento;
}

class _HexPainter extends CustomPainter {
  final Color color;
  const _HexPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final hexPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (final factor in [0.25, 0.40, 0.50]) {
      final r = size.width * factor;
      final path = ui.Path();
      for (int i = 0; i < 6; i++) {
        final a = (i * 60 - 30) * math.pi / 180;
        final vx = cx + r * math.cos(a);
        final vy = cy + r * math.sin(a);
        i == 0 ? path.moveTo(vx, vy) : path.lineTo(vx, vy);
      }
      path.close();
      canvas.drawPath(path, hexPaint);
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}