// lib/screens/perfil_screen.dart
// ═══════════════════════════════════════════════════════════
//  PERFIL — "GHOST OPERATIVE FILE"
//  Concepto: dossier clasificado de un agente de campo
//  Tipografía: Rajdhani (condensada, técnica, militar)
//  Paleta: negro absoluto + accent neon del territorio
//  Arquitectura: 3 zonas — IDENTIDAD / COMBATE / OPERACIONES
//  Diferenciador: número de operativo, KM a sangre, win-rate
//  animado, stagger de entrada por zona
// ═══════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:RunnerRisk/Pesta%C3%B1as/Social_screen.dart' as social;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../Widgets/custom_navbar.dart';
import 'historial_guerra_screen.dart';
import 'package:RunnerRisk/models/notif_item.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/league_card_widget.dart';
import '../services/league_service.dart';
import '../models/avatar_config.dart';
import '../Widgets/avatar_widget.dart';
import 'avatar_customizer_screen.dart';

// ─── Paleta ─────────────────────────────────────────────────
const _kBg       = Color(0xFF030303);
const _kSurface  = Color(0xFF0C0C0C);
const _kSurface2 = Color(0xFF101010);
const _kBorder   = Color(0xFF161616);
const _kBorder2  = Color(0xFF1F1F1F);
const _kMuted    = Color(0xFF333333);
const _kDim      = Color(0xFF4A4A4A);
const _kSubtext  = Color(0xFF666666);
const _kText     = Color(0xFFB0B0B0);
const _kWhite    = Color(0xFFEEEEEE);

// ─── Tipografía (Rajdhani — técnica, condensada, militaresca)
TextStyle _rajdhani(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height, List<Shadow>? shadows}) {
  return GoogleFonts.rajdhani(
    fontSize: size, fontWeight: weight, color: color,
    letterSpacing: spacing, height: height, shadows: shadows,
  );
}

class PerfilScreen extends StatefulWidget {
  final String? targetUserId;
  const PerfilScreen({super.key, this.targetUserId});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen>
    with TickerProviderStateMixin {

  // ── Identidad ─────────────────────────────────────────────
  String? get myUserId    => FirebaseAuth.instance.currentUser?.uid;
  String? get viewedUserId => widget.targetUserId ?? myUserId;
  bool get isOwnProfile   =>
      widget.targetUserId == null || widget.targetUserId == myUserId;

  final TextEditingController _nicknameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String   nickname         = '';
  String   email            = '';
  int      monedas          = 0;
  int      nivel            = 1;
  int      territorios      = 0;
  String?  fotoBase64;
  bool     isLoading        = true;
  bool     isSaving         = false;
  bool     isUploadingPhoto = false;

  // ── Stats ─────────────────────────────────────────────────
  double   _kmTotales               = 0;
  double   _velocidadMediaHistorica = 0;
  int      _totalCarreras           = 0;
  int      _territoriosConquistados = 0;
  Duration _tiempoTotalActividad    = Duration.zero;

  List<Map<String, dynamic>> _logros          = [];
  List<Map<String, dynamic>> _carrerasRecientes = [];
  int _rachaActual = 0;

  // ── Guerra ────────────────────────────────────────────────
  List<NotifItem> _perdidos       = [];
  List<NotifItem> _ganados        = [];
  bool            _loadingHistorial = true;
  int             _tabGuerraIndex   = 0;

  // ── Territorio / color ───────────────────────────────────
  Color _colorTerritorio = const Color(0xFF8B1A1A); // Rojo Imperio por defecto
  bool _colorPanelExpandido = false;

  // Colores estilo Risk — oscuros, serios, de tablero de guerra
  static const List<_RiskColor> _coloresDisponibles = [
    _RiskColor(Color(0xFF8B1A1A), 'Rojo Imperio'),
    _RiskColor(Color(0xFF1A3A6B), 'Azul Atlántico'),
    _RiskColor(Color(0xFF2D5A1B), 'Verde Ejército'),
    _RiskColor(Color(0xFF7A5C1E), 'Ocre Sahara'),
    _RiskColor(Color(0xFF4A1A6B), 'Violeta Regio'),
    _RiskColor(Color(0xFF1A5A5A), 'Teal Glaciar'),
    _RiskColor(Color(0xFF5A3010), 'Marrón Fortaleza'),
    _RiskColor(Color(0xFF3A3A3A), 'Gris Acero'),
    _RiskColor(Color(0xFF6B3A1A), 'Bronce Asedio'),
    _RiskColor(Color(0xFF1A4A3A), 'Verde Selva'),
    _RiskColor(Color(0xFF5A1A3A), 'Granate Real'),
    _RiskColor(Color(0xFF2A2A5A), 'Azul Noche'),
  ];

  // ── Amistad ───────────────────────────────────────────────
  String  _friendshipStatus  = 'none';
  String? _friendshipDocId;
  bool    _loadingFriendship = false;

  // ── Liga ─────────────────────────────────────────────────
  int        _rangoEnLiga = 0;
  int        _puntosLiga  = 0;
  LeagueInfo? _ligaInfo;

  // ── Mapa ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _territoriosDelUsuario  = [];
  bool _loadingTerritoriosMapa   = false;
  bool _mapaTerritoriosExpandido = false;

  AvatarConfig _avatarConfig = const AvatarConfig();

  // ── Animaciones ───────────────────────────────────────────
  late AnimationController _entradaAnim;   // stagger entrada
  late AnimationController _loopAnim;      // radar / pulse infinito
  late AnimationController _scanAnim;      // scan line

  late Animation<double> _fadeZona1;
  late Animation<double> _fadeZona2;
  late Animation<double> _fadeZona3;
  late Animation<Offset>  _slideZona2;
  late Animation<Offset>  _slideZona3;
  late Animation<double>  _pulse;
  late Animation<double>  _scan;

  // ── Helpers de color ─────────────────────────────────────
  Color get _accent     => _colorTerritorio;
  Color get _accentLow  => _accent.withValues(alpha: 0.08);
  Color get _accentMid  => _accent.withValues(alpha: 0.20);
  Color get _accentGlow => _accent.withValues(alpha: 0.45);

  // ── ID de operativo (6 chars del UID) ────────────────────
  String get _operativeId {
    final uid = viewedUserId ?? '';
    return uid.length >= 6 ? uid.substring(0, 6).toUpperCase() : 'UNKNWN';
  }

  @override
  void initState() {
    super.initState();

    _entradaAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _loopAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000))
      ..repeat(reverse: true);
    _scanAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();

    // Stagger: zona1 → zona2 → zona3
    _fadeZona1 = CurvedAnimation(
        parent: _entradaAnim, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
    _fadeZona2 = CurvedAnimation(
        parent: _entradaAnim, curve: const Interval(0.25, 0.75, curve: Curves.easeOut));
    _fadeZona3 = CurvedAnimation(
        parent: _entradaAnim, curve: const Interval(0.5, 1.0, curve: Curves.easeOut));
    _slideZona2 = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _entradaAnim,
            curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic)));
    _slideZona3 = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _entradaAnim,
            curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic)));
    _pulse = CurvedAnimation(parent: _loopAnim, curve: Curves.easeInOut);
    _scan  = CurvedAnimation(parent: _scanAnim, curve: Curves.linear);

    _cargarTodo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!isLoading && isOwnProfile) _recargarDatosDinamicos();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _entradaAnim.dispose();
    _loopAnim.dispose();
    _scanAnim.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  LÓGICA — sin cambios
  // ═══════════════════════════════════════════════════════════

  Future<void> _recargarDatosDinamicos() async {
    if (viewedUserId == null) return;
    await Future.wait([
      _cargarEstadisticas(), _cargarLogros(),
      _cargarCarrerasRecientes(), _cargarHistorialGuerra(), _cargarRacha(),
    ]);
  }

  Future<void> _cargarTodo() async {
    if (viewedUserId == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _cargarPerfil(), _cargarEstadisticas(), _cargarLogros(),
        _cargarCarrerasRecientes(), _cargarRangoEnLiga(), _cargarRacha(),
        _cargarHistorialGuerra(),
        if (!isOwnProfile) _cargarEstadoAmistad(),
      ]);
    } catch (e) {
      debugPrint('Error cargando perfil: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _entradaAnim.forward();
      }
    }
  }

  Future<void> _cargarPerfil() async {
    final doc = await FirebaseFirestore.instance
        .collection('players').doc(viewedUserId).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data()!;
    final territoriosSnap = await FirebaseFirestore.instance
        .collection('territories').where('userId', isEqualTo: viewedUserId).get();
    final colorInt = (data['territorio_color'] as num?)?.toInt();
    final pts      = (data['puntos_liga'] as num? ?? 0).toInt();
    final liga     = LeagueHelper.getLeague(pts);
    final avatarMap = data['avatar_config'] as Map<String, dynamic>?;
    if (avatarMap != null) {
      try { _avatarConfig = AvatarConfig.fromMap(avatarMap); }
      catch (e) { debugPrint('Error avatar config: $e'); }
    }
    setState(() {
      nickname   = data['nickname'] as String? ?? '';
      email      = isOwnProfile
          ? (data['email'] as String? ?? FirebaseAuth.instance.currentUser?.email ?? '')
          : '';
      monedas    = (data['monedas'] as num?)?.toInt() ?? 0;
      nivel      = (data['nivel'] as num?)?.toInt() ?? 1;
      territorios = territoriosSnap.docs.length;
      fotoBase64  = data['foto_base64'] as String?;
      _puntosLiga = pts;
      _ligaInfo   = liga;
      if (isOwnProfile) _nicknameController.text = nickname;
      if (colorInt != null) _colorTerritorio = Color(colorInt);
      if (avatarMap != null) _avatarConfig = AvatarConfig.fromMap(avatarMap);
    });
  }

  Future<void> _abrirCustomizador() async {
    if (!isOwnProfile) return;
    final nuevaConfig = await Navigator.push<AvatarConfig>(
      context,
      MaterialPageRoute(builder: (_) => AvatarCustomizerScreen(
          initialConfig: _avatarConfig, monedas: monedas)),
    );
    if (nuevaConfig != null && mounted) setState(() => _avatarConfig = nuevaConfig);
  }

  Future<void> _cargarRangoEnLiga() async {
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('players').doc(viewedUserId).get();
      if (!myDoc.exists) return;
      final myPts   = (myDoc.data()?['puntos_liga'] as num? ?? 0).toInt();
      final ligaInfo = LeagueHelper.getLeague(myPts);
      final int maxPts = ligaInfo.maxPts ?? 999999;
      final rankQ = await FirebaseFirestore.instance
          .collection('players')
          .where('puntos_liga', isGreaterThan: myPts)
          .where('puntos_liga', isLessThanOrEqualTo: maxPts)
          .count().get();
      if (mounted) {
        final int raw = (rankQ.count as num?)?.toInt() ?? 0;
        setState(() => _rangoEnLiga = raw + 1);
      }
    } catch (e) {
      debugPrint('Error rango: $e');
      if (mounted) setState(() => _rangoEnLiga = 0);
    }
  }

  Future<void> _cargarEstadoAmistad() async {
    if (myUserId == null || viewedUserId == null) return;
    try {
      final q1 = await FirebaseFirestore.instance.collection('friendships')
          .where('senderId', isEqualTo: myUserId)
          .where('receiverId', isEqualTo: viewedUserId).limit(1).get();
      if (q1.docs.isNotEmpty) {
        final d = q1.docs.first;
        setState(() {
          _friendshipDocId  = d.id;
          _friendshipStatus = d['status'] == 'accepted' ? 'accepted' : 'pending_sent';
        });
        return;
      }
      final q2 = await FirebaseFirestore.instance.collection('friendships')
          .where('senderId', isEqualTo: viewedUserId)
          .where('receiverId', isEqualTo: myUserId).limit(1).get();
      if (q2.docs.isNotEmpty) {
        final d = q2.docs.first;
        setState(() {
          _friendshipDocId  = d.id;
          _friendshipStatus = d['status'] == 'accepted' ? 'accepted' : 'pending_received';
        });
        return;
      }
      setState(() => _friendshipStatus = 'none');
    } catch (e) { debugPrint('Error amistad: $e'); }
  }

  Future<void> _enviarSolicitudAmistad() async {
    if (myUserId == null || viewedUserId == null) return;
    setState(() => _loadingFriendship = true);
    try {
      final ref = await FirebaseFirestore.instance.collection('friendships').add({
        'senderId': myUserId, 'receiverId': viewedUserId,
        'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId': viewedUserId, 'type': 'friend_request',
        'fromUserId': myUserId, 'fromNickname': await _getMyNickname(),
        'message': 'Te ha enviado una solicitud de amistad',
        'read': false, 'timestamp': FieldValue.serverTimestamp(),
      });
      setState(() { _friendshipStatus = 'pending_sent'; _friendshipDocId = ref.id; });
    } catch (e) { debugPrint('Error solicitud: $e'); }
    finally { if (mounted) setState(() => _loadingFriendship = false); }
  }

  Future<void> _aceptarSolicitud() async {
    if (_friendshipDocId == null) return;
    setState(() => _loadingFriendship = true);
    try {
      await FirebaseFirestore.instance.collection('friendships')
          .doc(_friendshipDocId).update({'status': 'accepted'});
      setState(() => _friendshipStatus = 'accepted');
    } catch (e) { debugPrint('Error aceptando: $e'); }
    finally { if (mounted) setState(() => _loadingFriendship = false); }
  }

  Future<void> _eliminarAmistad() async {
    if (_friendshipDocId == null) return;
    setState(() => _loadingFriendship = true);
    try {
      await FirebaseFirestore.instance.collection('friendships')
          .doc(_friendshipDocId).delete();
      setState(() { _friendshipStatus = 'none'; _friendshipDocId = null; });
    } catch (e) { debugPrint('Error eliminando amistad: $e'); }
    finally { if (mounted) setState(() => _loadingFriendship = false); }
  }

  Future<String> _getMyNickname() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(myUserId).get();
      return doc.data()?['nickname'] as String? ?? 'Runner';
    } catch (_) { return 'Runner'; }
  }

  Future<void> _cargarTerritoriosDelUsuario() async {
    if (viewedUserId == null) return;
    setState(() => _loadingTerritoriosMapa = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories').where('userId', isEqualTo: viewedUserId).get();
      final List<Map<String, dynamic>> lista = [];
      for (final doc in snap.docs) {
        final data     = doc.data();
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;
        final puntos = rawPuntos.map((p) {
          final m = p as Map<String, dynamic>;
          return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        }).toList();
        lista.add({'docId': doc.id, 'puntos': puntos});
      }
      if (mounted) setState(() {
        _territoriosDelUsuario     = lista;
        _loadingTerritoriosMapa    = false;
        _mapaTerritoriosExpandido  = true;
      });
    } catch (e) {
      debugPrint('Error territorios: $e');
      if (mounted) setState(() => _loadingTerritoriosMapa = false);
    }
  }

  void _abrirChat() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => social.ChatScreen(
        currentUserId: myUserId!, friendId: widget.targetUserId!,
        friendNickname: nickname, friendFoto: fotoBase64,
      ),
    ));
  }

  Future<void> _cargarRacha() async {
    if (viewedUserId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(viewedUserId).get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final int racha = (data['racha_actual'] as num?)?.toInt() ?? 0;
      final Timestamp? ultimaFechaTs = data['ultima_fecha_actividad'] as Timestamp?;
      int rachaVisible = racha;
      if (ultimaFechaTs != null) {
        final DateTime ultima      = ultimaFechaTs.toDate();
        final DateTime hoySinHora  = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        final DateTime ultimaSinH  = DateTime(ultima.year, ultima.month, ultima.day);
        if (hoySinHora.difference(ultimaSinH).inDays > 1) rachaVisible = 0;
      }
      if (mounted) setState(() => _rachaActual = rachaVisible);
    } catch (e) { debugPrint('Error racha: $e'); }
  }

  Future<void> _cargarEstadisticas() async {
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs').where('userId', isEqualTo: viewedUserId).get();
      double kmTotal = 0, sumVel = 0;
      int countVel = 0, totalSeg = 0;
      for (final doc in logsSnap.docs) {
        final d    = doc.data();
        final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
        final seg  = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
        kmTotal += dist; totalSeg += seg;
        if (dist > 0 && seg > 0) { sumVel += dist / (seg / 3600); countVel++; }
      }
      final conqSnap = await FirebaseFirestore.instance.collection('notifications')
          .where('toUserId', isEqualTo: viewedUserId)
          .where('type', isEqualTo: 'territory_conquered').get();
      if (mounted) setState(() {
        _kmTotales               = kmTotal;
        _velocidadMediaHistorica = countVel > 0 ? sumVel / countVel : 0;
        _totalCarreras           = logsSnap.docs.length;
        _tiempoTotalActividad    = Duration(seconds: totalSeg);
        _territoriosConquistados = conqSnap.docs.length;
      });
    } catch (e) { debugPrint('Error stats: $e'); }
  }

  Future<void> _cargarLogros() async {
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs').where('userId', isEqualTo: viewedUserId).get();
      final List<Map<String, dynamic>> logrosData = [];
      for (final doc in logsSnap.docs) {
        final d = doc.data();
        if (d['id_reto_completado'] != null && d['titulo'] != null)
          logrosData.add({...d, 'docId': doc.id});
      }
      logrosData.sort((a, b) {
        final tA = a['timestamp'] as Timestamp?;
        final tB = b['timestamp'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });
      if (mounted) setState(() => _logros = logrosData.take(10).toList());
    } catch (e) { debugPrint('Error logros: $e'); }
  }

  Future<void> _cargarCarrerasRecientes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('activity_logs').where('userId', isEqualTo: viewedUserId).get();
      final List<Map<String, dynamic>> carreras = [];
      for (final doc in snap.docs) {
        final d    = doc.data();
        final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
        if (dist > 0) carreras.add({...d, 'docId': doc.id});
      }
      carreras.sort((a, b) {
        final tA = a['timestamp'] as Timestamp?;
        final tB = b['timestamp'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });
      if (mounted) setState(() => _carrerasRecientes = carreras.take(5).toList());
    } catch (e) { debugPrint('Error carreras: $e'); }
  }

  Future<void> _cargarHistorialGuerra() async {
    if (viewedUserId == null) return;
    setState(() => _loadingHistorial = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('notifications')
          .where('toUserId', isEqualTo: viewedUserId).get();
      final List<NotifItem> perdidos = [], ganados = [];
      for (final doc in snap.docs) {
        final item = NotifItem.fromFirestore(doc);
        if (item.tipo == 'territory_lost') perdidos.add(item);
        else if (item.tipo == 'territory_conquered' || item.tipo == 'territory_steal_success')
          ganados.add(item);
      }
      for (final list in [perdidos, ganados]) {
        list.sort((a, b) {
          if (a.timestamp == null || b.timestamp == null) return 0;
          return b.timestamp!.compareTo(a.timestamp!);
        });
      }
      if (mounted) setState(() {
        _perdidos = perdidos; _ganados = ganados; _loadingHistorial = false;
      });
    } catch (e) {
      debugPrint('Error historial: $e');
      if (mounted) setState(() => _loadingHistorial = false);
    }
  }

  Future<void> _seleccionarFoto() async {
    if (!isOwnProfile) return;
    showModalBottomSheet(
      context: context, backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 3,
              decoration: BoxDecoration(color: _kMuted, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text('FOTO DE PERFIL', style: _rajdhani(11, FontWeight.w700, _accent, spacing: 3)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _BotonFoto(icon: Icons.camera_alt_outlined,
                label: 'Cámara', accent: _accent,
                onTap: () { Navigator.pop(ctx); _tomarFoto(ImageSource.camera); })),
            const SizedBox(width: 12),
            Expanded(child: _BotonFoto(icon: Icons.photo_library_outlined,
                label: 'Galería', accent: _accent,
                onTap: () { Navigator.pop(ctx); _tomarFoto(ImageSource.gallery); })),
          ]),
          if (fotoBase64 != null) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: TextButton.icon(
                onPressed: () { Navigator.pop(ctx); _eliminarFoto(); },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: Text('Eliminar foto',
                    style: _rajdhani(13, FontWeight.w600, Colors.redAccent)),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _tomarFoto(ImageSource source) async {
    if (!isOwnProfile) return;
    try {
      final XFile? imagen = await _picker.pickImage(
          source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (imagen == null) return;
      setState(() => isUploadingPhoto = true);
      Uint8List? bytes;
      if (kIsWeb) { bytes = await imagen.readAsBytes(); }
      else {
        bytes = await FlutterImageCompress.compressWithFile(
          imagen.path, minWidth: 256, minHeight: 256,
          quality: 70, format: CompressFormat.jpeg,
        );
      }
      if (bytes == null) { setState(() => isUploadingPhoto = false); return; }
      final b64 = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('players')
          .doc(myUserId).update({'foto_base64': b64});
      if (mounted) {
        setState(() { fotoBase64 = b64; isUploadingPhoto = false; });
        _mostrarSnackbar('Foto actualizada');
      }
    } catch (e) {
      if (mounted) { setState(() => isUploadingPhoto = false); _mostrarSnackbar('Error al subir la foto', error: true); }
    }
  }

  Future<void> _eliminarFoto() async {
    if (!isOwnProfile) return;
    try {
      await FirebaseFirestore.instance.collection('players')
          .doc(myUserId).update({'foto_base64': FieldValue.delete()});
      if (mounted) { setState(() => fotoBase64 = null); _mostrarSnackbar('Foto eliminada'); }
    } catch (_) { _mostrarSnackbar('Error al eliminar la foto', error: true); }
  }

  Future<void> _guardarNickname() async {
    if (!isOwnProfile) return;
    final nn = _nicknameController.text.trim();
    if (nn.isEmpty)  { _mostrarSnackbar('El nickname no puede estar vacío', error: true); return; }
    if (nn == nickname) { _mostrarSnackbar('El nickname no ha cambiado'); return; }
    if (nn.length < 3) { _mostrarSnackbar('Mínimo 3 caracteres', error: true); return; }
    setState(() => isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('players')
          .doc(myUserId).update({'nickname': nn});
      if (mounted) {
        setState(() { nickname = nn; isSaving = false; });
        _mostrarSnackbar('Nickname actualizado');
      }
    } catch (_) {
      if (mounted) { setState(() => isSaving = false); _mostrarSnackbar('Error al guardar', error: true); }
    }
  }

  Future<void> _guardarColorTerritorio(Color color) async {
    if (!isOwnProfile) return;
    setState(() => _colorTerritorio = color);
    try {
      await FirebaseFirestore.instance.collection('players')
          .doc(myUserId).update({'territorio_color': color.value});
      _mostrarSnackbar('Color actualizado');
    } catch (_) { _mostrarSnackbar('Error al guardar el color', error: true); }
  }

  void _mostrarSnackbar(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _rajdhani(13, FontWeight.w700, Colors.black)),
      backgroundColor: error ? Colors.redAccent : _accent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ));
  }

  void _mostrarDialogoEditarNickname() {
    if (!isOwnProfile) return;
    _nicknameController.text = nickname;
    showModalBottomSheet(
      context: context, backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 3,
              decoration: BoxDecoration(color: _kMuted, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 24),
          Text('EDITAR CALLSIGN', style: _rajdhani(11, FontWeight.w700, _accent, spacing: 3)),
          const SizedBox(height: 4),
          Text('Se actualizará en toda la app',
              style: _rajdhani(12, FontWeight.w400, _kSubtext)),
          const SizedBox(height: 20),
          TextField(
            controller: _nicknameController, autofocus: true, maxLength: 20,
            style: _rajdhani(20, FontWeight.w700, Colors.white, spacing: 1),
            decoration: InputDecoration(
              hintText: 'Tu callsign...',
              hintStyle: _rajdhani(20, FontWeight.w400, _kMuted),
              prefixIcon: Icon(Icons.terminal_rounded, color: _accent, size: 18),
              filled: true, fillColor: _kSurface2,
              counterStyle: _rajdhani(10, FontWeight.w400, _kSubtext),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _accent, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _guardarNickname(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Text('CONFIRMAR', style: _rajdhani(13, FontWeight.w700, Colors.black, spacing: 3)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Formatters ────────────────────────────────────────────
  String _formatTiempo(Duration d) {
    final h = d.inHours; final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  }
  String _formatFechaCorta(dynamic ts) {
    if (ts == null) return '--';
    if (ts is! Timestamp) return '--';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
  String _nivelTitulo(int n) {
    if (n >= 50) return 'LEYENDA';
    if (n >= 30) return 'ÉLITE';
    if (n >= 20) return 'VETERANO';
    if (n >= 10) return 'EXPLORADOR';
    return 'ROOKIE';
  }
  String _formatearTiempoGuerra(Timestamp? ts) {
    if (ts == null) return '--';
    final dif = DateTime.now().difference(ts.toDate());
    if (dif.inMinutes < 1)  return 'Ahora';
    if (dif.inMinutes < 60) return '${dif.inMinutes}m';
    if (dif.inHours < 24)   return '${dif.inHours}h';
    if (dif.inDays == 1)    return 'Ayer';
    if (dif.inDays < 7)     return '${dif.inDays}d';
    final dt = ts.toDate();
    return '${dt.day}/${dt.month}';
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: isLoading ? _buildLoader() : _buildContent(),
      bottomNavigationBar: isOwnProfile ? const CustomBottomNavbar(currentIndex: 4) : null,
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: Colors.transparent, elevation: 0,
    leading: !isOwnProfile
        ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 18),
            onPressed: () => Navigator.pop(context))
        : null,
    actions: isOwnProfile ? [
      AnimatedBuilder(
        animation: _loopAnim,
        builder: (_, __) => IconButton(
          icon: Icon(Icons.refresh_rounded,
              color: _accent.withValues(alpha: 0.5 + 0.5 * _pulse.value), size: 20),
          onPressed: _cargarTodo,
        ),
      ),
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: _kDim, size: 20),
        color: _kSurface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: _accent.withValues(alpha: 0.15))),
        onSelected: (v) async {
          switch (v) {
            case 'avatar':
              _abrirCustomizador();
              break;
            case 'stats':
              Navigator.pushNamed(context, '/resumen');
              break;
            case 'guerra':
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const HistorialGuerraScreen()));
              break;
            case 'liga':
              _mostrarSnackbar('Inicializando ligas...');
              await LeagueService.migrarJugadoresSinLiga();
              await _cargarTodo();
              _mostrarSnackbar('Ligas inicializadas');
              break;
            case 'logout':
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              break;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'avatar',
            child: _popupItem(Icons.palette_rounded, 'Personalizar avatar', _accent)),
          PopupMenuItem(value: 'stats',
            child: _popupItem(Icons.bar_chart_rounded, 'Estadísticas completas', _accent)),
          PopupMenuItem(value: 'guerra',
            child: _popupItem(Icons.history_rounded, 'Historial de guerra', Colors.redAccent)),
          PopupMenuItem(value: 'liga',
            child: _popupItem(Icons.sync_rounded, 'Inicializar puntos de liga', Colors.tealAccent)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'logout',
            child: _popupItem(Icons.logout_rounded, 'Cerrar sesión', Colors.redAccent)),
        ],
      ),
      const SizedBox(width: 4),
    ] : [],
  );

  // ─── Loader ──────────────────────────────────────────────
  Widget _buildLoader() {
    return Center(
      child: AnimatedBuilder(
        animation: _loopAnim,
        builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 56, height: 56,
            child: CustomPaint(painter: _LoaderPainter(
                accent: _accent, progress: _scan.value, pulse: _pulse.value))),
          const SizedBox(height: 20),
          Text('CARGANDO EXPEDIENTE',
              style: _rajdhani(10, FontWeight.w700,
                  _accent.withValues(alpha: 0.5 + 0.5 * _pulse.value), spacing: 4)),
        ]),
      ),
    );
  }

  // ─── Content ─────────────────────────────────────────────
  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ══ ZONA 1 — IDENTIDAD ══════════════════════════════
        FadeTransition(opacity: _fadeZona1, child: _buildZonaIdentidad()),

        // ══ ZONA 2 — DATOS DE COMBATE ════════════════════════
        SlideTransition(position: _slideZona2,
          child: FadeTransition(opacity: _fadeZona2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(children: [

                // Botones sociales para perfil ajeno
                if (!isOwnProfile) ...[
                  const SizedBox(height: 20),
                  _buildFriendshipButton(),
                  const SizedBox(height: 8),
                  _socialBtn('Enviar mensaje', Icons.chat_bubble_outline_rounded,
                      _accent, _abrirChat),
                ],

                const SizedBox(height: 24),

                // KM a sangre — el dato más importante, ocupa todo el ancho
                _buildKmSangre(),

                const SizedBox(height: 10),

                // Tres stats en fila — diseño asimétrico
                _buildTriadaStats(),

                const SizedBox(height: 10),

                // Racha — diseño de medidor circular
                _buildRachaGauge(),

                const SizedBox(height: 10),

                // Liga card
                if (viewedUserId != null) _SafeLeagueCard(userId: viewedUserId!),

                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),

        // ══ ZONA 3 — OPERACIONES ════════════════════════════
        SlideTransition(position: _slideZona3,
          child: FadeTransition(opacity: _fadeZona3,
            child: Column(children: [

              // Separador de zona con label
              _buildZonaSeparador('REGISTRO DE OPERACIONES'),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(children: [

                  // Guerra — el más dramático
                  _buildGuerraPanel(),
                  const SizedBox(height: 10),

                  // Misiones recientes
                  _buildMisionesRecientes(),
                  const SizedBox(height: 10),

                  // Logros
                  _buildLogrosPanel(),
                  const SizedBox(height: 10),

                  // Mapa
                  _buildMapaPanel(),

                  if (isOwnProfile) ...[
                    const SizedBox(height: 24),
                    _buildZonaSeparador('CONFIGURACIÓN DE OPERATIVO'),
                    const SizedBox(height: 16),
                    _buildColorPanel(),
                  ],

                  const SizedBox(height: 100),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  ZONA 1 — IDENTIDAD
  //  Ocupa la pantalla completa. Fondo con painter táctico.
  //  Avatar centrado con anillos + dossier info alrededor.
  // ═══════════════════════════════════════════════════════════

  Widget _buildZonaIdentidad() {
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: h * 0.52,
      child: Stack(fit: StackFit.expand, children: [

        // Fondo animado
        Container(color: _kBg),
        AnimatedBuilder(
          animation: Listenable.merge([_loopAnim, _scanAnim]),
          builder: (_, __) => CustomPaint(
            painter: _DossierBgPainter(accent: _accent, pulse: _pulse.value, scan: _scan.value),
          ),
        ),

        // Fade inferior hacia bg
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(height: h * 0.20, decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, _kBg]),
          )),
        ),

        // ── Número de operativo — esquina sup izq ────────────
        Positioned(top: 58, left: 20,
          child: _buildOperativeId(),
        ),

        // ── Liga badge — esquina sup der ─────────────────────
        Positioned(top: 58, right: 20,
          child: _buildLigaBadge(),
        ),

        // ── Avatar centrado + info abajo ─────────────────────
        Positioned(bottom: 0, left: 0, right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // Avatar
            _buildAvatar(),
            const SizedBox(height: 16),

            // Nombre — tipografía enorme
            GestureDetector(
              onTap: isOwnProfile ? _mostrarDialogoEditarNickname : null,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AnimatedBuilder(animation: _loopAnim,
                  builder: (_, __) => Text(
                    nickname.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 38, fontWeight: FontWeight.w700,
                      color: _kWhite, letterSpacing: 4, height: 1,
                      shadows: [
                        Shadow(color: _accent.withValues(alpha: 0.3 + 0.2 * _pulse.value),
                            blurRadius: 20),
                      ],
                    ),
                  ),
                ),
                if (isOwnProfile) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.edit_outlined, color: _kMuted, size: 14),
                ],
              ]),
            ),
            const SizedBox(height: 6),

            // Título + nivel
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _tagPill(_nivelTitulo(nivel), _accent, filled: true),
              const SizedBox(width: 8),
              _tagPill('NIV. $nivel', _accent),
              const SizedBox(width: 8),
              _tagPill('⚡ $monedas', Colors.amber.withValues(alpha: 0.85)),
            ]),

            if (isOwnProfile && email.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(email, style: _rajdhani(10, FontWeight.w400, _kMuted)),
            ],

            const SizedBox(height: 28),
          ]),
        ),
      ]),
    );
  }

  Widget _buildOperativeId() {
    return AnimatedBuilder(
      animation: _loopAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _kBg.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _accent.withValues(alpha: 0.18 + 0.08 * _pulse.value)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('OPERATIVE ID', style: _rajdhani(7, FontWeight.w700, _kDim, spacing: 2)),
          Text(_operativeId, style: _rajdhani(16, FontWeight.w700, _accent, spacing: 2)),
          Row(children: [
            Container(width: 5, height: 5, decoration: BoxDecoration(
              color: _rachaActual > 0
                  ? Color.lerp(const Color(0xFF39FF14), const Color(0xFF00CC00), _pulse.value)!
                  : _kMuted,
              shape: BoxShape.circle,
            )),
            const SizedBox(width: 5),
            Text(
              _rachaActual > 0 ? 'ACTIVO' : 'INACTIVO',
              style: _rajdhani(8, FontWeight.w700,
                  _rachaActual > 0 ? const Color(0xFF39FF14).withValues(alpha: 0.8) : _kMuted,
                  spacing: 1.5),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildLigaBadge() {
    final liga = _ligaInfo;
    if (liga == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kBg.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: liga.color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text('LIGA', style: _rajdhani(7, FontWeight.w700, _kDim, spacing: 2)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(liga.emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(liga.name.toUpperCase(),
              style: _rajdhani(14, FontWeight.w700, liga.color, spacing: 1)),
        ]),
        if (_rangoEnLiga > 0)
          Text('#$_rangoEnLiga EN LIGA',
              style: _rajdhani(8, FontWeight.w700, liga.color.withValues(alpha: 0.7), spacing: 1)),
      ]),
    );
  }

  Widget _buildAvatar() {
    return AnimatedBuilder(
      animation: _loopAnim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          // Anillo exterior
          Container(width: 116 + 8 * _pulse.value, height: 116 + 8 * _pulse.value,
            decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(
                  color: _accent.withValues(alpha: 0.08 + 0.06 * _pulse.value), width: 1)),
          ),
          // Anillo medio
          Container(width: 102, height: 102,
            decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(color: _accent.withValues(alpha: 0.2 + 0.1 * _pulse.value), width: 1.5)),
          ),
          // Avatar
          GestureDetector(
            onTap: isOwnProfile ? _seleccionarFoto : null,
            child: Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurface2,
                border: Border.all(color: _accent, width: 2),
                boxShadow: [
                  BoxShadow(color: _accent.withValues(alpha: 0.35 + 0.2 * _pulse.value),
                      blurRadius: 24 + 12 * _pulse.value),
                ],
              ),
              child: isUploadingPhoto
                  ? Center(child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: _accent, strokeWidth: 1.5)))
                  : ClipOval(child: fotoBase64 != null
                      ? Image.memory(base64Decode(fotoBase64!),
                          fit: BoxFit.cover, width: 88, height: 88)
                      : AvatarWidget(config: _avatarConfig, size: 88)),
            ),
          ),
          // Botón personalizar
          if (isOwnProfile)
            Positioned(bottom: 6, right: 6,
              child: GestureDetector(
                onTap: _abrirCustomizador,
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: _accent, shape: BoxShape.circle,
                    border: Border.all(color: _kBg, width: 2),
                    boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.6), blurRadius: 8)],
                  ),
                  child: const Icon(Icons.palette_rounded, color: Colors.black, size: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tagPill(String text, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: _rajdhani(
          10, FontWeight.w700, filled ? Colors.black : color, spacing: 0.5)),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  KM A SANGRE — dato principal, rompe el grid
  // ═══════════════════════════════════════════════════════════

  Widget _buildKmSangre() {
    final progreso = (_kmTotales % 100) / 100;
    final hito     = ((_kmTotales ~/ 100) + 1) * 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _accent, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DISTANCIA TOTAL', style: _rajdhani(9, FontWeight.w700, _kDim, spacing: 2.5)),
        const SizedBox(height: 4),

        // Número gigante
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _loopAnim,
              builder: (_, __) => Text(
                _kmTotales.toStringAsFixed(1),
                style: GoogleFonts.rajdhani(
                  fontSize: 72, fontWeight: FontWeight.w700,
                  color: _accent, height: 0.9,
                  shadows: [Shadow(color: _accent.withValues(alpha: 0.25 + 0.1 * _pulse.value),
                      blurRadius: 30)],
                ),
              ),
            ),
          ),

          // Mini columna de stats
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            _miniKpi(_velocidadMediaHistorica > 0
                ? '${_velocidadMediaHistorica.toStringAsFixed(1)}'
                : '--', 'KM/H'),
            const SizedBox(height: 8),
            _miniKpi(_formatTiempo(_tiempoTotalActividad), 'TIEMPO'),
            const SizedBox(height: 8),
            _miniKpi('$_totalCarreras', 'MISIONES'),
          ]),
        ]),

        const SizedBox(height: 2),
        Text('KM', style: _rajdhani(13, FontWeight.w700, _accent.withValues(alpha: 0.4), spacing: 4)),

        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('HITO $hito KM', style: _rajdhani(9, FontWeight.w600, _kDim, spacing: 1.5)),
          Text('${(progreso * 100).toStringAsFixed(0)}%',
              style: _rajdhani(9, FontWeight.w700, _accent.withValues(alpha: 0.7))),
        ]),
        const SizedBox(height: 5),
        _glowBar(progreso),
      ]),
    );
  }

  Widget _miniKpi(String val, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(val, style: _rajdhani(16, FontWeight.w700, _accent, height: 1)),
      Text(label, style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1.5)),
    ]);
  }

  // ═══════════════════════════════════════════════════════════
  //  TRÍADA DE STATS — asimétrica: grande / medio / medio
  // ═══════════════════════════════════════════════════════════

  Widget _buildTriadaStats() {
    final ligaColor = _ligaInfo?.color ?? _accent;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Zonas — grande (más importante)
      Expanded(flex: 5, child: _buildStatGrande(
        '$territorios', 'ZONAS\nACTIVAS', Icons.crop_square_rounded, _accent)),

      const SizedBox(width: 8),

      // Columna derecha — dos pequeñas
      Expanded(flex: 4, child: Column(children: [
        _buildStatPequena('$_territoriosConquistados',
            'CONQUISTAS', Icons.military_tech_rounded, Colors.amber),
        const SizedBox(height: 8),
        _buildStatPequena(
            _rangoEnLiga > 0 ? '#$_rangoEnLiga' : '—',
            'RANKING LIGA', Icons.leaderboard_rounded, ligaColor),
      ])),
    ]);
  }

  Widget _buildStatGrande(String val, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color.withValues(alpha: 0.5), size: 14),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _loopAnim,
          builder: (_, __) => Text(val,
            style: GoogleFonts.rajdhani(
              fontSize: 52, fontWeight: FontWeight.w700, color: color, height: 1,
              shadows: [Shadow(color: color.withValues(alpha: 0.25 + 0.1 * _pulse.value), blurRadius: 16)],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: _rajdhani(9, FontWeight.w600, _kDim, spacing: 1.5, height: 1.4)),
      ]),
    );
  }

  Widget _buildStatPequena(String val, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        Icon(icon, color: color.withValues(alpha: 0.5), size: 13),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val, style: _rajdhani(22, FontWeight.w700, color, height: 1)),
          Text(label, style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1, height: 1.3)),
        ])),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  RACHA — medidor circular con arc
  // ═══════════════════════════════════════════════════════════

  Widget _buildRachaGauge() {
    final bool activa  = _rachaActual > 0;
    final hitos        = [3, 7, 14, 30];
    final int hito     = _rachaActual == 0
        ? 3 : hitos.firstWhere((h) => _rachaActual < h, orElse: () => 30);
    final double prog  = (_rachaActual / hito).clamp(0.0, 1.0);

    String msg;
    if (!activa)           msg = 'Sin actividad reciente';
    else if (_rachaActual == 1) msg = 'Buen comienzo. No pares.';
    else if (_rachaActual < 7)  msg = '${7 - _rachaActual} días para una semana';
    else if (_rachaActual < 30) msg = 'Más de una semana consecutiva';
    else                        msg = 'Un mes sin parar. Leyenda.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activa ? _accent.withValues(alpha: 0.2) : _kBorder),
      ),
      child: Row(children: [

        // Gauge circular
        SizedBox(width: 76, height: 76,
          child: AnimatedBuilder(
            animation: _loopAnim,
            builder: (_, __) => CustomPaint(
              painter: _RachaGaugePainter(
                  progress: prog, accent: activa ? _accent : _kMuted,
                  pulse: _pulse.value, activa: activa),
              child: Center(child: Text(
                activa ? '🔥' : '💤',
                style: const TextStyle(fontSize: 26),
              )),
            ),
          ),
        ),

        const SizedBox(width: 18),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RACHA OPERATIVA',
              style: _rajdhani(9, FontWeight.w700, activa ? _accent : _kDim, spacing: 2)),
          const SizedBox(height: 4),
          RichText(text: TextSpan(children: [
            TextSpan(text: '$_rachaActual',
              style: GoogleFonts.rajdhani(
                fontSize: 40, fontWeight: FontWeight.w700,
                color: activa ? _accent : _kMuted, height: 1,
              ),
            ),
            TextSpan(text: _rachaActual == 1 ? '  DÍA' : '  DÍAS',
              style: _rajdhani(14, FontWeight.w600, activa ? _accent.withValues(alpha: 0.4) : _kMuted, spacing: 1),
            ),
          ])),
          const SizedBox(height: 3),
          Text(msg, style: _rajdhani(11, FontWeight.w500, _kSubtext)),
        ])),

        // Meta
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('META', style: _rajdhani(8, FontWeight.w700, _kDim, spacing: 2)),
          Text('$hito', style: _rajdhani(28, FontWeight.w700,
              activa ? _accent.withValues(alpha: 0.6) : _kMuted, height: 1)),
          Text('días', style: _rajdhani(9, FontWeight.w500, _kDim)),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  SEPARADOR DE ZONA
  // ═══════════════════════════════════════════════════════════

  Widget _buildZonaSeparador(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Container(height: 1,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [
              Colors.transparent, _accent.withValues(alpha: 0.2)])))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(label, style: _rajdhani(9, FontWeight.w700, _accent.withValues(alpha: 0.6), spacing: 3)),
        ),
        Expanded(child: Container(height: 1,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [
              _accent.withValues(alpha: 0.2), Colors.transparent])))),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  PANEL DE GUERRA — el más dramático visualmente
  // ═══════════════════════════════════════════════════════════

  Widget _buildGuerraPanel() {
    final total  = _ganados.length + _perdidos.length;
    final winPct = total > 0 ? _ganados.length / total : 0.0;
    final List<NotifItem> lista = _tabGuerraIndex == 0 ? _perdidos : _ganados;
    final Color  colTab = _tabGuerraIndex == 0 ? Colors.redAccent : _accent;

    String rivalTop = '--';
    if (lista.isNotEmpty) {
      final Map<String, int> freq = {};
      for (final item in lista) { final n = item.fromNickname ?? '?'; freq[n] = (freq[n] ?? 0) + 1; }
      rivalTop = freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(children: [

        // Header con win/loss grandes
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          child: Row(children: [

            // VICTORIAS
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _tabGuerraIndex = 1),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _tabGuerraIndex == 1 ? _accent.withValues(alpha: 0.05) : Colors.transparent,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
                  border: Border(bottom: BorderSide(
                      color: _tabGuerraIndex == 1 ? _accent : Colors.transparent, width: 2)),
                ),
                child: Column(children: [
                  Text('${_ganados.length}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 44, fontWeight: FontWeight.w700, height: 1,
                        color: _tabGuerraIndex == 1 ? _accent : _kMuted,
                        shadows: _tabGuerraIndex == 1
                            ? [Shadow(color: _accent.withValues(alpha: 0.3), blurRadius: 12)]
                            : [],
                      )),
                  Text('VICTORIAS', style: _rajdhani(9, FontWeight.w700,
                      _tabGuerraIndex == 1 ? _accent.withValues(alpha: 0.8) : _kDim, spacing: 2)),
                ]),
              ),
            )),

            // Divisor central con win rate
            Container(
              width: 1, height: 80,
              color: _kBorder2,
              child: null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // tiny win rate label
              ]),
            ),

            // DERROTAS
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _tabGuerraIndex = 0),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _tabGuerraIndex == 0 ? Colors.redAccent.withValues(alpha: 0.05) : Colors.transparent,
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(12)),
                  border: Border(bottom: BorderSide(
                      color: _tabGuerraIndex == 0 ? Colors.redAccent : Colors.transparent, width: 2)),
                ),
                child: Column(children: [
                  Text('${_perdidos.length}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 44, fontWeight: FontWeight.w700, height: 1,
                        color: _tabGuerraIndex == 0 ? Colors.redAccent : _kMuted,
                        shadows: _tabGuerraIndex == 0
                            ? [Shadow(color: Colors.redAccent.withValues(alpha: 0.3), blurRadius: 12)]
                            : [],
                      )),
                  Text('DERROTAS', style: _rajdhani(9, FontWeight.w700,
                      _tabGuerraIndex == 0 ? Colors.redAccent.withValues(alpha: 0.8) : _kDim, spacing: 2)),
                ]),
              ),
            )),
          ]),
        ),

        // Win rate bar — a sangre
        Stack(children: [
          Container(height: 3, color: Colors.redAccent.withValues(alpha: 0.25)),
          FractionallySizedBox(
            widthFactor: winPct,
            child: Container(height: 3, decoration: BoxDecoration(
              color: _accent,
              boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.5), blurRadius: 6)],
            )),
          ),
        ]),

        // Stats resumen
        if (total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _guerraKpi('${(winPct * 100).toStringAsFixed(0)}%', 'WIN RATE', _accent),
              _guerraDivider(),
              _guerraKpi('$total', 'TOTAL', _kText),
              _guerraDivider(),
              _guerraKpi(rivalTop, _tabGuerraIndex == 0 ? 'RIVAL TOP' : 'VÍCTIMA TOP', colTab),
            ]),
          ),

        // Lista de eventos
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: _loadingHistorial
              ? Center(child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: _accent, strokeWidth: 1.5)))
              : lista.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _tabGuerraIndex == 0 ? 'Sin territorios perdidos' : 'Sin conquistas',
                        style: _rajdhani(12, FontWeight.w500, _kDim),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(children: [
                      ...lista.take(3).map((item) => _guerraRow(item, colTab)),
                      if (lista.length > 3 && isOwnProfile)
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const HistorialGuerraScreen())),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('Ver ${lista.length - 3} más',
                                  style: _rajdhani(11, FontWeight.w700, colTab)),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, color: colTab, size: 12),
                            ]),
                          ),
                        ),
                    ]),
        ),
      ]),
    );
  }

  Widget _guerraKpi(String val, String label, Color color) {
    return Expanded(child: Column(children: [
      Text(val, style: _rajdhani(14, FontWeight.w700, color, height: 1),
          textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(label, style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1.5),
          textAlign: TextAlign.center),
    ]));
  }

  Widget _guerraDivider() => Container(width: 1, height: 28, color: _kBorder2,
      margin: const EdgeInsets.symmetric(horizontal: 8));

  Widget _guerraRow(NotifItem item, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color.withValues(alpha: 0.4), width: 2)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.mensaje,
              style: _rajdhani(12, FontWeight.w600, _kText),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            if (item.fromNickname != null) ...[
              Text(item.fromNickname!,
                  style: _rajdhani(9, FontWeight.w700, color.withValues(alpha: 0.9))),
              Container(width: 1, height: 8, color: _kBorder2,
                  margin: const EdgeInsets.symmetric(horizontal: 6)),
            ],
            Text(_formatearTiempoGuerra(item.timestamp),
                style: _rajdhani(9, FontWeight.w500, _kDim)),
          ]),
        ])),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  MISIONES RECIENTES
  // ═══════════════════════════════════════════════════════════

  Widget _buildMisionesRecientes() {
    return _Panel(
      accent: _accent,
      label: 'ÚLTIMAS MISIONES',
      icon: Icons.directions_run_rounded,
      child: _carrerasRecientes.isEmpty
          ? _emptyRow('Sin misiones registradas')
          : Column(children: _carrerasRecientes.asMap().entries.map((e) {
              final i = e.key; final d = e.value;
              final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
              final seg  = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
              final vel  = (d['velocidad_media'] as num?)?.toDouble() ??
                  (dist > 0 && seg > 0 ? dist / (seg / 3600) : 0.0);
              final fecha = _formatFechaCorta(d['timestamp']);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: i == 0 ? _accent.withValues(alpha: 0.04) : _kSurface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(left: BorderSide(
                      color: i == 0 ? _accent : _kBorder2, width: i == 0 ? 2 : 1)),
                ),
                child: Row(children: [
                  Text('${i + 1}', style: _rajdhani(11, FontWeight.w700,
                      i == 0 ? _accent : _kDim, spacing: 0)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${dist.toStringAsFixed(2)} km',
                        style: _rajdhani(16, FontWeight.w700,
                            i == 0 ? _kWhite : _kText, height: 1)),
                    Text('${_formatTiempo(Duration(seconds: seg))}  ·  ${vel.toStringAsFixed(1)} km/h',
                        style: _rajdhani(10, FontWeight.w500, _kDim)),
                  ])),
                  Text(fecha, style: _rajdhani(10, FontWeight.w600, _kMuted)),
                ]),
              );
            }).toList()),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  LOGROS
  // ═══════════════════════════════════════════════════════════

  Widget _buildLogrosPanel() {
    return _Panel(
      accent: _accent,
      label: 'LOGROS',
      icon: Icons.emoji_events_outlined,
      child: _logros.isEmpty
          ? _emptyRow('Sin logros todavía')
          : Wrap(spacing: 6, runSpacing: 6, children: _logros.map((logro) {
              final titulo = logro['titulo'] as String? ?? 'Logro';
              final recompensa = logro['recompensa'] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.15)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🏆', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 7),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo, style: _rajdhani(11, FontWeight.w700, _kWhite)),
                    Text('+$recompensa monedas',
                        style: _rajdhani(9, FontWeight.w600, Colors.amber)),
                  ]),
                ]),
              );
            }).toList()),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  MAPA
  // ═══════════════════════════════════════════════════════════

  Widget _buildMapaPanel() {
    List<Polygon> poligonos = [];
    LatLng centro = const LatLng(37.1350, -3.6330);
    if (!isOwnProfile && _territoriosDelUsuario.isNotEmpty) {
      double latSum = 0, lngSum = 0, total = 0;
      for (final t in _territoriosDelUsuario) {
        final puntos = t['puntos'] as List<LatLng>;
        for (final p in puntos) { latSum += p.latitude; lngSum += p.longitude; total++; }
        poligonos.add(Polygon(points: puntos,
            color: _accent.withValues(alpha: 0.35),
            borderColor: _accent, borderStrokeWidth: 2));
      }
      if (total > 0) centro = LatLng(latSum / total, lngSum / total);
    }

    return _Panel(
      accent: _accent,
      label: isOwnProfile ? 'MIS TERRITORIOS' : 'SUS TERRITORIOS',
      icon: Icons.map_outlined,
      child: Column(children: [
        GestureDetector(
          onTap: () {
            if (!_mapaTerritoriosExpandido && !isOwnProfile && _territoriosDelUsuario.isEmpty) {
              _cargarTerritoriosDelUsuario();
            } else {
              setState(() => _mapaTerritoriosExpandido = !_mapaTerritoriosExpandido);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorder)),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(
                  color: _accent, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.5), blurRadius: 6)])),
              const SizedBox(width: 10),
              _loadingTerritoriosMapa
                  ? SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(color: _accent, strokeWidth: 1.5))
                  : Text(_mapaTerritoriosExpandido ? 'Ocultar mapa' : 'Ver en el mapa',
                      style: _rajdhani(12, FontWeight.w500, _kDim)),
              const Spacer(),
              Icon(_mapaTerritoriosExpandido
                  ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: _accent, size: 18),
            ]),
          ),
        ),
        if (_mapaTerritoriosExpandido) ...[
          const SizedBox(height: 8),
          if (!isOwnProfile && _territoriosDelUsuario.isEmpty && !_loadingTerritoriosMapa)
            _emptyRow('Sin territorios aún')
          else if (!isOwnProfile && _territoriosDelUsuario.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(height: 240,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder)),
                child: Stack(children: [
                  FlutterMap(
                    options: MapOptions(initialCenter: centro, initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag)),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.runner_risk.app'),
                      PolygonLayer(polygons: poligonos),
                      MarkerLayer(markers: _territoriosDelUsuario.map((t) {
                        final pts  = t['puntos'] as List<LatLng>;
                        final latC = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
                        final lngC = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
                        return Marker(point: LatLng(latC, lngC), width: 70, height: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: _accent, width: 1)),
                            child: Text(nickname, textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: _rajdhani(8, FontWeight.w700, _accent, spacing: 0.5)),
                          ),
                        );
                      }).toList()),
                    ],
                  ),
                  Positioned(top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.flag_rounded, color: Colors.black, size: 9),
                        const SizedBox(width: 3),
                        Text('${_territoriosDelUsuario.length}',
                            style: _rajdhani(10, FontWeight.w700, Colors.black)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  COLOR PANEL
  // ═══════════════════════════════════════════════════════════

  Widget _buildColorPanel() {
    // Nombre del color actualmente seleccionado
    final _RiskColor? colorActual = _coloresDisponibles
        .where((c) => c.color.value == _colorTerritorio.value)
        .firstOrNull;
    final String nombreActual = colorActual?.nombre ?? 'Personalizado';

    return _Panel(
      accent: _accent,
      label: 'COLOR DE TERRITORIO',
      icon: Icons.palette_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Fila colapsada: muestra color actual + botón toggle ──
        GestureDetector(
          onTap: () => setState(() => _colorPanelExpandido = !_colorPanelExpandido),
          child: Row(children: [
            // Muestra del color actual con glow
            AnimatedBuilder(
              animation: _loopAnim,
              builder: (_, __) => Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(
                      color: _accent.withValues(alpha: 0.35 + 0.15 * _pulse.value),
                      blurRadius: 14 + 6 * _pulse.value)],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('COLOR ACTUAL', style: _rajdhani(8, FontWeight.w700, _kDim, spacing: 2)),
              const SizedBox(height: 2),
              Text(nombreActual, style: _rajdhani(14, FontWeight.w700, _accent)),
            ])),
            // Icono desplegable
            AnimatedRotation(
              turns: _colorPanelExpandido ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _accent.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: _accent, size: 18),
              ),
            ),
          ]),
        ),

        // ── Panel desplegable con AnimatedSize ──────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: _colorPanelExpandido
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 16),
                  // Divisor
                  Container(height: 1, color: _accent.withValues(alpha: 0.1),
                      margin: const EdgeInsets.only(bottom: 14)),
                  // Grid de colores — 4 por fila con nombre al hacer tap
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                    children: _coloresDisponibles.map((rc) {
                      final bool sel = _colorTerritorio.value == rc.color.value;
                      return GestureDetector(
                        onTap: () {
                          _guardarColorTerritorio(rc.color);
                          setState(() => _colorPanelExpandido = false);
                        },
                        child: Column(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: sel ? 42 : 38,
                            height: sel ? 42 : 38,
                            decoration: BoxDecoration(
                              color: rc.color,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: sel ? Colors.white : _kBorder,
                                  width: sel ? 2 : 1),
                              boxShadow: sel
                                  ? [BoxShadow(color: rc.color.withValues(alpha: 0.6),
                                      blurRadius: 10, spreadRadius: 1)]
                                  : [],
                            ),
                            child: sel
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                : null,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            rc.nombre.split(' ').last, // Solo segunda palabra: "Imperio", "Atlántico"...
                            style: _rajdhani(8, sel ? FontWeight.w700 : FontWeight.w500,
                                sel ? _accent : _kDim),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                      );
                    }).toList(),
                  ),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _popupItem(IconData icon, String label, Color color) {
    return Row(children: [
      Container(width: 26, height: 26,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Icon(icon, color: color, size: 13),
      ),
      const SizedBox(width: 12),
      Text(label, style: _rajdhani(13, FontWeight.w600, _kText)),
    ]);
  }

  Widget _divider() => Container(height: 1, color: _kBorder);

  // ═══════════════════════════════════════════════════════════
  //  FRIENDSHIP
  // ═══════════════════════════════════════════════════════════

  Widget _buildFriendshipButton() {
    if (_loadingFriendship) {
      return Center(child: SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(color: _accent, strokeWidth: 1.5)));
    }
    switch (_friendshipStatus) {
      case 'accepted':
        return _socialBtn('Amigos', Icons.people_rounded, Colors.greenAccent,
            () => _confirmarEliminarAmistad(), outlined: true);
      case 'pending_sent':
        return _socialBtn('Solicitud enviada', Icons.hourglass_top_rounded,
            _kMuted, () => _confirmarEliminarAmistad(), outlined: true);
      case 'pending_received':
        return Row(children: [
          Expanded(child: _socialBtn('Aceptar', Icons.check_rounded, Colors.greenAccent, _aceptarSolicitud)),
          const SizedBox(width: 8),
          Expanded(child: _socialBtn('Rechazar', Icons.close_rounded, Colors.redAccent,
              _eliminarAmistad, outlined: true)),
        ]);
      default:
        return _socialBtn('Añadir operativo', Icons.person_add_outlined, _accent, _enviarSolicitudAmistad);
    }
  }

  Widget _socialBtn(String label, IconData icon, Color color, VoidCallback onTap,
      {bool outlined = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: outlined ? 0.35 : 0.2)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Text(label, style: _rajdhani(12, FontWeight.w700, color, spacing: 0.5)),
        ]),
      ),
    );
  }

  void _confirmarEliminarAmistad() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _kSurface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _accent.withValues(alpha: 0.2))),
      title: Text('Eliminar amistad',
          style: _rajdhani(16, FontWeight.w700, _kWhite)),
      content: Text(
        _friendshipStatus == 'pending_sent'
            ? 'Se cancelará la solicitud enviada.'
            : 'Dejarás de ser aliado con $nickname.',
        style: _rajdhani(13, FontWeight.w500, _kSubtext)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: _rajdhani(12, FontWeight.w600, _kDim))),
        TextButton(onPressed: () { Navigator.pop(ctx); _eliminarAmistad(); },
            child: Text('Eliminar', style: _rajdhani(12, FontWeight.w700, Colors.redAccent))),
      ],
    ));
  }

  // ── Helpers UI ───────────────────────────────────────────
  Widget _glowBar(double val, {double height = 3, Color? color}) {
    return Stack(children: [
      Container(height: height, decoration: BoxDecoration(
          color: _kBorder2, borderRadius: BorderRadius.circular(2))),
      FractionallySizedBox(widthFactor: val.clamp(0.0, 1.0),
        child: Container(height: height, decoration: BoxDecoration(
          color: color ?? _accent, borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: (color ?? _accent).withValues(alpha: 0.6), blurRadius: 8)],
        )),
      ),
    ]);
  }

  Widget _emptyRow(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(text, style: _rajdhani(12, FontWeight.w500, _kDim)),
  );
}

// ═══════════════════════════════════════════════════════════
//  PANEL — contenedor de sección reutilizable
//  Header con línea accent, icono, label condensado
// ═══════════════════════════════════════════════════════════

class _Panel extends StatelessWidget {
  final Color accent;
  final String label;
  final IconData icon;
  final Widget child;

  const _Panel({required this.accent, required this.label,
      required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF161616)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.1))),
          ),
          child: Row(children: [
            Container(width: 2, height: 13,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(1),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8)]),
            ),
            const SizedBox(width: 9),
            Icon(icon, color: accent.withValues(alpha: 0.5), size: 11),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.rajdhani(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.75), letterSpacing: 2.5)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SAFE LEAGUE CARD
// ═══════════════════════════════════════════════════════════

class _SafeLeagueCard extends StatelessWidget {
  final String userId;
  const _SafeLeagueCard({required this.userId});
  @override
  Widget build(BuildContext context) => _LeagueCardBoundary(userId: userId);
}

class _LeagueCardBoundary extends StatefulWidget {
  final String userId;
  const _LeagueCardBoundary({required this.userId});
  @override
  State<_LeagueCardBoundary> createState() => _LeagueCardBoundaryState();
}
class _LeagueCardBoundaryState extends State<_LeagueCardBoundary> {
  bool _err = false;
  @override
  Widget build(BuildContext context) {
    if (_err) return const SizedBox.shrink();
    try {
      return LeagueCard(userId: widget.userId);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _err = true);
      });
      return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  PAINTERS
// ═══════════════════════════════════════════════════════════

/// Fondo de la zona de identidad: grid diagonal + radar + líneas HUD
class _DossierBgPainter extends CustomPainter {
  final Color accent;
  final double pulse, scan;
  _DossierBgPainter({required this.accent, required this.pulse, required this.scan});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid diagonal
    final gp = Paint()..color = accent.withValues(alpha: 0.022)
      ..strokeWidth = 0.5..style = PaintingStyle.stroke;
    for (double i = -size.height; i < size.width + size.height; i += 32)
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), gp);

    // Radar (centro)
    final cx = size.width * 0.5, cy = size.height * 0.38;
    for (int i = 1; i <= 5; i++) {
      canvas.drawCircle(Offset(cx, cy), i * 36.0,
        Paint()..color = accent.withValues(alpha: 0.03 + 0.005 * pulse)
          ..strokeWidth = 0.7..style = PaintingStyle.stroke);
    }
    // Cruz radar
    canvas.drawLine(Offset(cx - 180, cy), Offset(cx + 180, cy),
        Paint()..color = accent.withValues(alpha: 0.05)..strokeWidth = 0.5);
    canvas.drawLine(Offset(cx, cy - 180), Offset(cx, cy + 180),
        Paint()..color = accent.withValues(alpha: 0.05)..strokeWidth = 0.5);

    // Sweep scan
    final sweepAngle = scan * 2 * math.pi;
    final sweepRect = Rect.fromCircle(center: Offset(cx, cy), radius: 180);
    canvas.drawArc(sweepRect, sweepAngle - 0.7, 0.7, true,
      Paint()..shader = RadialGradient(colors: [
        accent.withValues(alpha: 0.12), Colors.transparent]).createShader(sweepRect)
      ..style = PaintingStyle.fill);
    canvas.drawLine(Offset(cx, cy),
      Offset(cx + 178 * math.cos(sweepAngle), cy + 178 * math.sin(sweepAngle)),
      Paint()..color = accent.withValues(alpha: 0.25)..strokeWidth = 1);

    // Punto central
    canvas.drawCircle(Offset(cx, cy), 3,
        Paint()..color = accent.withValues(alpha: 0.4 + 0.3 * pulse));

    // Línea horizontal de corte
    final lp = Paint()..color = accent.withValues(alpha: 0.08)..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height * 0.62), Offset(size.width, size.height * 0.62), lp);

    // Marcas laterales
    for (int i = 0; i < 6; i++) {
      final y = 60.0 + i * 24;
      canvas.drawLine(Offset(0, y), Offset(i % 2 == 0 ? 14 : 7, y),
          Paint()..color = accent.withValues(alpha: 0.12)..strokeWidth = 1);
      canvas.drawLine(Offset(size.width, y), Offset(size.width - (i % 2 == 0 ? 14 : 7), y),
          Paint()..color = accent.withValues(alpha: 0.12)..strokeWidth = 1);
    }

    // Franja izquierda
    canvas.drawRect(Rect.fromLTWH(0, 0, 2, size.height),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, accent.withValues(alpha: 0.45), Colors.transparent],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, 0, 2, size.height)));
  }

  @override
  bool shouldRepaint(_DossierBgPainter o) =>
      o.pulse != pulse || o.scan != scan || o.accent != accent;
}

/// Gauge circular de la racha
class _RachaGaugePainter extends CustomPainter {
  final double progress, pulse;
  final Color accent;
  final bool activa;
  _RachaGaugePainter({required this.progress, required this.pulse,
      required this.accent, required this.activa});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final startAngle = -math.pi * 0.75;
    final sweepTotal = math.pi * 1.5;

    // Track
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        startAngle, sweepTotal,
        false, Paint()
          ..color = const Color(0xFF1A1A1A)..strokeWidth = 6
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    // Fill
    if (progress > 0)
      canvas.drawArc(Rect.fromCircle(center: c, radius: r),
          startAngle, sweepTotal * progress,
          false, Paint()
            ..color = accent..strokeWidth = 6
            ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
            ..maskFilter = activa
                ? MaskFilter.blur(BlurStyle.normal, 3 + 2 * pulse)
                : null);

    // Puntos de inicio/fin
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.3)..style = PaintingStyle.fill;
    for (final angle in [startAngle, startAngle + sweepTotal]) {
      canvas.drawCircle(
          Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle)), 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_RachaGaugePainter o) =>
      o.progress != progress || o.pulse != pulse || o.accent != accent;
}

/// Loader circular
class _LoaderPainter extends CustomPainter {
  final Color accent;
  final double progress, pulse;
  _LoaderPainter({required this.accent, required this.progress, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // Anillos
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(c, 8.0 * i * 1.1,
        Paint()..color = accent.withValues(alpha: 0.04 + 0.02 * pulse * (4 - i))
          ..strokeWidth = 0.7..style = PaintingStyle.stroke);
    }
    // Arc giratorio
    canvas.drawArc(Rect.fromCircle(center: c, radius: 20),
        progress * 2 * math.pi, 1.2, false,
        Paint()..color = accent..strokeWidth = 2
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_LoaderPainter o) => o.progress != progress || o.pulse != pulse;
}

// ═══════════════════════════════════════════════════════════
//  RISK COLOR — modelo de color con nombre
// ═══════════════════════════════════════════════════════════

class _RiskColor {
  final Color color;
  final String nombre;
  const _RiskColor(this.color, this.nombre);
}

class _BotonFoto extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _BotonFoto({required this.icon, required this.label,
      required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: accent, size: 24),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.rajdhani(
              fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF888888))),
        ]),
      ),
    );
  }
}