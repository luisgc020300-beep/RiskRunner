import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:RiskRunner/pestañas/clan_screen.dart';
import 'package:RiskRunner/pestañas/settings_screen.dart';
import '../widgets/custom_navbar.dart';
import '../shell/app_shell.dart';
import '../services/league_service.dart';
import '../services/ranking_service.dart';
import '../screens/rutas_explorador_screen.dart';
import 'perfil_screen.dart';
import 'chat_screen.dart';
import '../widgets/social/social_theme.dart';
import '../widgets/social/social_shared.dart';
import '../widgets/social/social_states.dart';
import '../widgets/social/social_cards.dart';

// =============================================================================
//  SOCIAL SCREEN
// =============================================================================
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});
  @override State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> with TickerProviderStateMixin {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  Color _accent = kSocAccent;
  SocialPalette get _p => SocialPalette.of(context);
  String _searchQuery = '';
  Timer? _debounce;
  List<Map<String, dynamic>> _resultadosBusqueda = [];
  bool _buscando = false;
  bool _errorBusqueda = false;
  int _solicitudesPendientes = 0;
  int _mensajesNoLeidos = 0;
  final Map<String, Map<String, dynamic>> _perfilesCache = {};
  bool _navegandoAChat = false;
  int _misPuntosLiga = 0;
  String _miLiga = 'BRONCE';
  String _rankingModo = 'competitivo';
  String? _ligaSeleccionada;
  StreamSubscription? _solicitudesStream;
  StreamSubscription? _mensajesStream;
  final Set<String> _solicitudesEnviadas = {};

  final GlobalKey<RefreshIndicatorState> _rkRanking  = GlobalKey();
  final GlobalKey<RefreshIndicatorState> _rkAliados  = GlobalKey();
  final GlobalKey<RefreshIndicatorState> _rkMensajes = GlobalKey();
  final GlobalKey<RefreshIndicatorState> _rkSolici   = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChange);
    _cargarDatosPropios();
    _escucharSolicitudes();
    _escucharMensajesNoLeidos();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q == _searchQuery) return;
    _searchQuery = q;
    _debounce?.cancel();
    if (q.isEmpty) { setState(() { _resultadosBusqueda = []; _buscando = false; _errorBusqueda = false; }); return; }
    setState(() { _buscando = true; _errorBusqueda = false; });
    _debounce = Timer(const Duration(milliseconds: 350), _buscar);
  }

  void _onTabChange() {
    if (_tabController.indexIsChanging) {
      _searchController.clear();
      setState(() { _resultadosBusqueda = []; _errorBusqueda = false; });
    }
  }

  Future<void> _cargarDatosPropios() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('players').doc(currentUserId).get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      final c    = (data['territorio_color'] as num?)?.toInt();
      final pts  = (data['puntos_liga'] as num? ?? 0).toInt();
      final info = LeagueHelper.getLeague(pts);
      setState(() {
        if (c != null) _accent = Color(c);
        _misPuntosLiga    = pts;
        _miLiga           = info.name;
        _ligaSeleccionada = null;
      });
    } catch (e) { debugPrint('Error cargando datos propios: $e'); }
  }

  Future<void> _buscar() async {
    final q = _searchQuery;
    if (q.isEmpty) { setState(() { _resultadosBusqueda = []; _buscando = false; }); return; }
    try {
      final snap = await FirebaseFirestore.instance.collection('players')
          .where('nickname', isGreaterThanOrEqualTo: q)
          .where('nickname', isLessThanOrEqualTo: '$q').limit(15).get();
      if (!mounted || _searchQuery != q) return;
      final futures = snap.docs.where((d) => d.id != currentUserId).map(_procesarResultado).toList();
      final results = await Future.wait(futures);
      if (mounted && _searchQuery == q) {
        setState(() { _resultadosBusqueda = results.whereType<Map<String, dynamic>>().toList(); _buscando = false; _errorBusqueda = false; });
      }
    } catch (e) {
      debugPrint('Error búsqueda: $e');
      if (mounted) setState(() { _buscando = false; _errorBusqueda = true; });
    }
  }

  Future<Map<String, dynamic>?> _procesarResultado(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final int monedas = (data['monedas'] as num? ?? 0).toInt();
      final db = FirebaseFirestore.instance;

      final results = await Future.wait([
        db.collection('players')
            .where('monedas', isGreaterThan: monedas)
            .count()
            .get(),
        db.collection('friendships')
            .where('senderId', isEqualTo: currentUserId)
            .where('receiverId', isEqualTo: doc.id)
            .limit(1)
            .get(),
        db.collection('friendships')
            .where('senderId', isEqualTo: doc.id)
            .where('receiverId', isEqualTo: currentUserId)
            .limit(1)
            .get(),
      ]);

      final rankSnap = results[0] as AggregateQuerySnapshot;
      final sentSnap = results[1] as QuerySnapshot;
      final recvSnap = results[2] as QuerySnapshot;

      final int rango = ((rankSnap.count as num?)?.toInt() ?? 0) + 1;
      String relacion = 'ninguna';
      if (sentSnap.docs.isNotEmpty) {
        relacion = (sentSnap.docs.first.data() as Map<String, dynamic>)['status'] ?? 'ninguna';
      } else if (recvSnap.docs.isNotEmpty) {
        relacion = (recvSnap.docs.first.data() as Map<String, dynamic>)['status'] ?? 'ninguna';
      }

      return {...data, 'id': doc.id, 'rango': rango, 'relacion': relacion};
    } catch (e) {
      debugPrint('Error procesarResultado: $e');
      return null;
    }
  }

  void _escucharSolicitudes() {
    _solicitudesStream = FirebaseFirestore.instance.collection('friendships')
        .where('receiverId', isEqualTo: currentUserId).where('status', isEqualTo: 'pending').snapshots()
        .listen((snap) { if (mounted) setState(() => _solicitudesPendientes = snap.docs.length); },
          onError: (e) => debugPrint('Stream solicitudes: $e'));
  }

  void _escucharMensajesNoLeidos() {
    _mensajesStream = FirebaseFirestore.instance.collection('chats')
        .where('participants', arrayContains: currentUserId).snapshots()
        .listen((snap) {
          int total = 0;
          for (final d in snap.docs) { final data = d.data(); total += (data['unread_$currentUserId'] as num? ?? 0).toInt(); }
          if (mounted) setState(() => _mensajesNoLeidos = total);
        }, onError: (e) => debugPrint('Stream mensajes: $e'));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _solicitudesStream?.cancel();
    _mensajesStream?.cancel();
    super.dispose();
  }

  Future<void> _enviarSolicitud(String targetId) async {
    setState(() => _solicitudesEnviadas.add(targetId));
    try {
      await FirebaseFirestore.instance.collection('friendships').add({
        'senderId': currentUserId, 'receiverId': targetId, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp()});
      _buscar();
    } catch (e) {
      if (mounted) { setState(() => _solicitudesEnviadas.remove(targetId)); _snack('No se pudo enviar la solicitud.', error: true); }
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: _p.text1, fontSize: 13)),
      backgroundColor: _p.surface3, behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: error ? kSocAccent.withValues(alpha: 0.5) : kSocGreenFg.withValues(alpha: 0.5))),
      duration: Duration(seconds: error ? 3 : 2)));
  }

  void _abrirChat(String friendId, String nick, String? foto) {
    if (_navegandoAChat) return;
    _navegandoAChat = true;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(currentUserId: currentUserId, friendId: friendId, friendNickname: nick, friendFoto: foto),
    )).whenComplete(() => _navegandoAChat = false);
  }

  // ══════════════════════════════ BUILD ════════════════════════════════════════
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: Column(children: [
      _buildHeader(),
      Expanded(child: _searchQuery.isNotEmpty ? _buildSearchResults() : TabBarView(
        controller: _tabController,
        physics: const PageScrollPhysics(),
        children: [
          _buildRankingTab(),
          _buildFriendsList(),
          _buildChatList(),
          _buildRequestsList(),
          const ClanScreen(),
        ])),
    ]),
    bottomNavigationBar: AppShell.isActive(context) ? null : const CustomBottomNavbar(currentIndex: 3),
  );

  // ══════════════════════════════ HEADER ════════════════════════════════════════
  Widget _buildHeader() {
    final p = SocialPalette.of(context);
    return Container(
    color: p.bg,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: MediaQuery.of(context).padding.top),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text('SOCIAL',
                style: TextStyle(color: p.text1, fontSize: 22,
                  fontWeight: FontWeight.w900, letterSpacing: 3, height: 1.0)),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Text(
                _miLiga.toUpperCase(),
                style: TextStyle(color: p.subtext,
                  fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w600)),
            ]),
          ])),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.line2),
                borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$_misPuntosLiga',
                  style: TextStyle(color: p.text1,
                    fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1)),
                Text('PTS LIGA', style: TextStyle(
                  color: p.subtext, fontSize: 7, letterSpacing: 2, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => SettingsScreen.mostrar(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.line2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.settings_outlined, color: p.text1, size: 18),
              ),
            ),
          ]),
        ])),
      _buildSearchBar(),
      Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))), child: _buildTabBar()),
    ]));
  }

  Widget _buildSearchBar() {
    final p = SocialPalette.of(context);
    final bool active = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), height: 44,
        decoration: BoxDecoration(
          color: active ? p.surface2 : p.surface,
          border: Border.all(color: active ? kSocAccent.withValues(alpha: 0.5) : p.line2, width: active ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [const BoxShadow(color: kSocAccentGlow, blurRadius: 12)] : null),
        child: Row(children: [
          Padding(padding: const EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded, color: active ? kSocAccent : p.dim, size: 16)),
          Expanded(child: TextField(
            controller: _searchController,
            style: TextStyle(color: p.text1, fontSize: 13, letterSpacing: 0.3),
            decoration: InputDecoration(
              hintText: 'Buscar...', hintStyle: TextStyle(color: p.dim, fontSize: 13),
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)))),
          if (_buscando)
            Padding(padding: const EdgeInsets.only(right: 14),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: kSocAccent, strokeWidth: 1.5)))
          else if (active)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: Padding(padding: const EdgeInsets.only(right: 14),
                child: Container(width: 18, height: 18,
                  decoration: BoxDecoration(color: p.dim, shape: BoxShape.circle),
                  child: Icon(Icons.close_rounded, color: p.bg, size: 11)))),
        ])));
  }

  Widget _buildTabBar() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (_, __) => Row(children: [
        _iosTab(0, Icons.emoji_events_outlined,       'LIGAS',       kSocAccent),
        _iosTab(1, Icons.people_outline,              'AMIGOS',      kSocAccent),
        _iosTab(2, Icons.chat_bubble_outline_rounded, 'CHAT',        kSocAccent, badge: _mensajesNoLeidos),
        _iosTab(3, Icons.person_add_outlined,         'SOLICITUDES', kSocAccent, badge: _solicitudesPendientes),
        _iosTab(4, Icons.groups_outlined,             'CLUB',        kSocAccent),
      ]),
    );
  }

  Widget _iosTab(int idx, IconData icon, String label, Color color, {int badge = 0}) {
    final active = _tabController.index == idx;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _tabController.animateTo(idx);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                Icon(icon, size: 17, color: active ? color : _p.subtext),
                if (badge > 0)
                  Positioned(
                    top: -4, right: -4,
                    child: SocialPulseBadge(count: badge, color: color),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 7,
                letterSpacing: active ? 1.5 : 1.0,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: active ? color : _p.subtext,
              )),
          ]),
        ),
      ),
    );
  }

  // ══════════════════════════ SEARCH RESULTS ════════════════════════════════════
  Widget _buildSearchResults() {
    if (_errorBusqueda) return SocialErrorState(onRetry: () { setState(() { _buscando = true; _errorBusqueda = false; }); _buscar(); });
    if (_resultadosBusqueda.isEmpty && !_buscando) return SocialEmptyState(
      icon: Icons.search_off_rounded, titulo: 'Sin resultados',
      subtitulo: 'Nadie con nickname "$_searchQuery"',
      accionLabel: 'Limpiar', onAccion: () => _searchController.clear());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), itemCount: _resultadosBusqueda.length,
      itemBuilder: (ctx, i) {
        final u = _resultadosBusqueda[i];
        final bool yaEnviada = _solicitudesEnviadas.contains(u['id']);
        final String rel = yaEnviada ? 'pending' : (u['relacion'] as String? ?? 'ninguna');
        return SocialStagger(index: i, child: SocialPlayerCard(
          userId: u['id'], nickname: u['nickname'] ?? '?',
          nivel: (u['nivel'] as num? ?? 1).toInt(), monedas: (u['monedas'] as num? ?? 0).toInt(),
          rango: (u['rango'] as num? ?? 0).toInt(), relacion: rel, fotoBase64: u['foto_base64'] as String?,
          puntosLiga: (u['puntos_liga'] as num? ?? 0).toInt(), accent: _accent,
          currentUserId: currentUserId,
          onAgregar: () => _enviarSolicitud(u['id']),
          onVerPerfil: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => PerfilScreen(targetUserId: u['id'])))));
      });
  }

  Widget _rankingPill(String label, IconData icon, String modo) {
    final isActive = _rankingModo == modo;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    return GestureDetector(
      onTap: isActive ? null : () => setState(() { _rankingModo = modo; _ligaSeleccionada = null; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isActive ? activeColor.withValues(alpha: 0.45) : _p.line2,
            width: 1,
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 11, color: isActive ? activeColor : _p.dim),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                fontFamily: 'Rajdhani', fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? activeColor : _p.dim,
                letterSpacing: 0.8,
              )),
            ]),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════ RANKING TAB ══════════════════════════════════════
  Widget _buildRankingTab() {
    final ligaInfo = LeagueHelper.getLeague(_misPuntosLiga);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(children: [
          Expanded(child: _rankingPill('COMPETITIVO', Icons.leaderboard_rounded, 'competitivo')),
          const SizedBox(width: 8),
          Expanded(child: _rankingPill('SEMANAL', Icons.public_rounded, 'semanal')),
          const SizedBox(width: 8),
          Expanded(child: _rankingPill('RUTAS', Icons.route_rounded, 'rutas')),
        ])),
      if (_rankingModo == 'competitivo') ...[
        if (_ligaSeleccionada != null) _buildBotonVolver(),
        Expanded(child: RefreshIndicator(
          key: _rkRanking, color: kSocAccent, backgroundColor: _p.surface2,
          onRefresh: () async { await _cargarDatosPropios(); },
          child: _ligaSeleccionada != null
              ? _buildLeagueRankingById(_ligaSeleccionada!)
              : ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 32), children: [
                  _buildTodasLasLigas(ligaInfo),
                ])))
      ] else if (_rankingModo == 'semanal')
        Expanded(child: RefreshIndicator(
          key: _rkRanking, color: const Color(0xFF30A0FF), backgroundColor: _p.surface2,
          onRefresh: () async { await _cargarDatosPropios(); setState(() {}); },
          child: _buildSemanalRanking()))
      else
        Expanded(child: RefreshIndicator(
          key: _rkRanking, color: const Color(0xFFAF52DE), backgroundColor: _p.surface2,
          onRefresh: () async { await _cargarDatosPropios(); setState(() {}); },
          child: _buildRutasRanking())),
    ]);
  }

  Widget _buildSemanalRanking() {
    final semana = RankingService.getSemanaActual();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: RankingService.rankingSemanalStream(),
      builder: (ctx, snap) {
        if (!snap.hasData) return _buildRankSkels();
        if (snap.hasError) return SocialErrorState(onRetry: () => setState(() {}));
        final docs = snap.data!;
        if (docs.isEmpty) return SocialEmptyState(
          icon: Icons.public_rounded,
          titulo: 'Sin actividad esta semana',
          subtitulo: 'Corre en modo Global para aparecer\nen el ranking de la semana $semana');
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(children: [
              const Icon(Icons.public_rounded, color: Color(0xFF30A0FF), size: 14),
              const SizedBox(width: 8),
              Text('SEMANA $semana',
                style: const TextStyle(color: Color(0xFF30A0FF), fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 2.5)),
              const Spacer(),
              Text('${docs.length} corredores',
                style: TextStyle(color: _p.subtext, fontSize: 10)),
            ])),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i];
              final uid  = data['id'] as String? ?? '';
              final esYo = uid == currentUserId;
              final pts  = (data['puntos_semana_global'] as num? ?? 0).toInt();
              return SocialStagger(index: i, child: GestureDetector(
                onTap: esYo ? null : () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PerfilScreen(targetUserId: uid))),
                child: SocialSimpleRankCard(
                  posicion: i + 1, nickname: data['nickname'] as String? ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  esYo: esYo, valor: '$pts', unidad: 'PTS',
                  color: const Color(0xFF30A0FF), accent: _accent, p: _p)));
            })),
        ]);
      });
  }

  Widget _buildRutasRanking() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: RankingService.rankingRutasStream(),
      builder: (ctx, snap) {
        if (!snap.hasData) return _buildRankSkels();
        if (snap.hasError) return SocialErrorState(onRetry: () => setState(() {}));
        final docs = snap.data!;
        if (docs.isEmpty) return const SocialEmptyState(
          icon: Icons.route_rounded,
          titulo: 'Nadie ha corrido rutas aún',
          subtitulo: 'Completa carreras en modo Rutas\npara aparecer en este ranking');
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(children: [
              const Icon(Icons.route_rounded, color: Color(0xFFAF52DE), size: 14),
              const SizedBox(width: 8),
              const Text('TOP EXPLORADORES · KM TOTALES',
                style: TextStyle(color: Color(0xFFAF52DE), fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 2.5)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => RutasExploradorScreen(accent: _accent))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFAF52DE).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFAF52DE).withValues(alpha: 0.4))),
                  child: const Row(children: [
                    Icon(Icons.explore_rounded, color: Color(0xFFAF52DE), size: 11),
                    SizedBox(width: 4),
                    Text('Explorar', style: TextStyle(color: Color(0xFFAF52DE),
                      fontSize: 10, fontWeight: FontWeight.w700)),
                  ]))),
            ])),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i];
              final uid  = data['id'] as String? ?? '';
              final esYo = uid == currentUserId;
              final km   = (data['km_totales_rutas'] as num? ?? 0).toDouble();
              return SocialStagger(index: i, child: GestureDetector(
                onTap: esYo ? null : () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PerfilScreen(targetUserId: uid))),
                child: SocialSimpleRankCard(
                  posicion: i + 1, nickname: data['nickname'] as String? ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  esYo: esYo, valor: km.toStringAsFixed(1), unidad: 'KM',
                  color: const Color(0xFFAF52DE), accent: _accent, p: _p)));
            })),
        ]);
      });
  }

  Widget _buildBotonVolver() {
    final liga = LeagueSystem.ligas.firstWhere((l) => l.id == _ligaSeleccionada, orElse: () => LeagueSystem.ligas.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: GestureDetector(
        onTap: () => setState(() => _ligaSeleccionada = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: _p.surface, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.arrow_back_ios_rounded, color: _p.dim, size: 12),
            const SizedBox(width: 8),
            Text('Todas las ligas', style: TextStyle(color: _p.text3, fontSize: 12, fontStyle: FontStyle.italic)),
            const Spacer(),
            Icon(liga.icon, size: 13, color: _accent),
            const SizedBox(width: 6),
            Text(liga.name.toUpperCase(), style: TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.5)),
          ]))));
  }

  Widget _buildTodasLasLigas(LeagueInfo miLiga) {
    final List<Color> tierColors = [kSocBronze, kSocSilver, kSocGoldTier, kSocPlatinum, kSocDiamond];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(children: [
          Container(width: 16, height: 1, color: kSocAccent.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text('TODAS LAS LIGAS', style: TextStyle(color: _p.subtext, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 4)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: _p.line2)),
        ])),
      ...LeagueSystem.ligas.asMap().entries.map((entry) {
        final int idx = entry.key;
        final LeagueInfo liga = entry.value;
        final bool esMiLiga = liga.id == miLiga.id;
        final bool bloqueada = liga.minPts > _misPuntosLiga;
        final Color tierColor = idx < tierColors.length ? tierColors[idx] : _accent;
        return SocialStagger(index: idx, child: SocialPress(
          onTap: () => setState(() => _ligaSeleccionada = liga.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: esMiLiga ? _p.surface3 : _p.surface,
                    border: Border.all(color: esMiLiga ? tierColor.withValues(alpha: 0.4) : _p.line2, width: esMiLiga ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: tierColor.withValues(alpha: 0.06),
                          border: Border.all(color: tierColor.withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(8)),
                        child: Center(child: Icon(liga.icon, color: tierColor, size: 22))),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(liga.name.toUpperCase(),
                            style: TextStyle(color: esMiLiga ? _p.text1 : _p.text2, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                          if (esMiLiga) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kSocAccent, borderRadius: BorderRadius.circular(4),
                                boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 6)]),
                              child: const Text('TÚ', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(liga.maxPts != null ? '${liga.minPts} – ${liga.maxPts} pts' : '${liga.minPts}+ pts',
                          style: TextStyle(color: tierColor.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                      ])),
                      bloqueada && !esMiLiga
                          ? Container(width: 30, height: 30,
                              decoration: BoxDecoration(color: _p.surface3, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(6)),
                              child: Icon(Icons.lock_outline_rounded, color: _p.dim, size: 13))
                          : Icon(Icons.chevron_right_rounded, color: esMiLiga ? tierColor : _p.dim, size: 20),
                    ]))),
                Positioned(left: 0, top: 0, bottom: 0,
                  child: Container(
                    width: esMiLiga ? 3 : 2,
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: esMiLiga ? 1.0 : 0.4),
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))))),
              ])))));
      }),
    ]);
  }

  Widget _buildLeagueRankingById(String ligaId) => _buildLeagueRankingWidget(
    LeagueSystem.ligas.firstWhere((l) => l.id == ligaId, orElse: () => LeagueSystem.ligas.first));

  Widget _buildLeagueRankingWidget(LeagueInfo ligaInfo) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('players')
          .where('puntos_liga', isGreaterThanOrEqualTo: ligaInfo.minPts)
          .where('puntos_liga', isLessThanOrEqualTo: ligaInfo.maxPts ?? 999999)
          .orderBy('puntos_liga', descending: true).limit(100).snapshots(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) return _buildRankSkels();
        if (snapshot.hasError) return SocialErrorState(onRetry: () => setState(() {}));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return SocialEmptyState(icon: Icons.emoji_events_outlined, titulo: 'Liga vacía', subtitulo: 'Nadie en ${ligaInfo.name} aún');
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Row(children: [
              Icon(ligaInfo.icon, color: ligaInfo.color, size: 16), const SizedBox(width: 8),
              Text('TOP 100 · ${ligaInfo.name.toUpperCase()}', style: TextStyle(color: _accent, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2.5)),
              const Spacer(),
              Text('${docs.length} personas', style: TextStyle(color: _p.subtext, fontSize: 10))])),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final bool esYo = docs[i].id == currentUserId;
              return SocialStagger(index: i, child: GestureDetector(
                onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PerfilScreen(targetUserId: docs[i].id))),
                child: SocialRankCard(posicion: i + 1, nickname: data['nickname'] ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(), monedas: (data['monedas'] as num? ?? 0).toInt(),
                  fotoBase64: data['foto_base64'] as String?, esYo: esYo,
                  puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), ligaInfo: ligaInfo, accent: _accent)));
            })),
        ]);
      });
  }

  Widget _buildRankSkels() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), itemCount: 7,
    itemBuilder: (_, i) => SocialSkel(height: i < 3 ? 82 : 64));

  // ════════════════════════ AMIGOS TAB ═════════════════════════════════════════
  Widget _buildFriendsList() {
    final sentStream = FirebaseFirestore.instance.collection('friendships')
        .where('senderId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'accepted').snapshots();

    final recvStream = FirebaseFirestore.instance.collection('friendships')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'accepted').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: sentStream,
      builder: (ctx, sentSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: recvStream,
          builder: (ctx, recvSnap) {
            if (!sentSnap.hasData || !recvSnap.hasData) return _genSkels();
            if (sentSnap.hasError || recvSnap.hasError)
              return SocialErrorState(onRetry: () { _perfilesCache.clear(); setState(() {}); });

            final amigos = [...sentSnap.data!.docs, ...recvSnap.data!.docs];

            if (amigos.isEmpty) return SocialEmptyState(
              icon: Icons.group_outlined,
              titulo: 'Sin aliados aún',
              subtitulo: 'Busca exploradores y forma\ntu equipo cartográfico',
              accionLabel: 'Buscar exploradores',
              onAccion: () => _searchController.clear());

            return RefreshIndicator(
              key: _rkAliados, color: kSocAccent, backgroundColor: _p.surface2,
              onRefresh: () async { _perfilesCache.clear(); setState(() {}); },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                itemCount: amigos.length,
                itemBuilder: (ctx, i) {
                  final doc = amigos[i];
                  final fid = doc['senderId'] == currentUserId
                      ? doc['receiverId']
                      : doc['senderId'];
                  if (_perfilesCache.containsKey(fid))
                    return SocialStagger(index: i, child: _buildFriendCard(_perfilesCache[fid]!, fid));
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('players').doc(fid).get(),
                    builder: (ctx, s) {
                      if (!s.hasData) return const SocialSkel();
                      final data = s.data!.data() as Map<String, dynamic>? ?? {};
                      _perfilesCache[fid] = data;
                      return SocialStagger(index: i, child: _buildFriendCard(data, fid));
                    });
                }));
          });
      });
  }

  Widget _buildFriendCard(Map<String, dynamic> data, String fid) {
    final colorInt = (data['territorio_color'] as num?)?.toInt();
    final Color territorioColor = colorInt != null ? Color(colorInt) : _p.line2;
    final lastActive = data['ultima_fecha_actividad'] as dynamic;
    bool activo = false;
    if (lastActive != null) {
      try {
        final dt = (lastActive as dynamic).toDate() as DateTime;
        activo = DateTime.now().difference(dt).inDays <= 1;
      } catch (_) {}
    }
    return SocialFriendCard(
      nickname: data['nickname'] ?? '?', nivel: (data['nivel'] as num? ?? 1).toInt(),
      monedas: (data['monedas'] as num? ?? 0).toInt(), fotoBase64: data['foto_base64'] as String?,
      puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), accent: _accent,
      territorioColor: territorioColor, activo: activo,
      onChat: () => _abrirChat(fid, data['nickname'] ?? '?', data['foto_base64'] as String?),
      onPerfil: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PerfilScreen(targetUserId: fid))));
  }

  // ════════════════════════ MENSAJES TAB ═════════════════════════════════════════
  Widget _buildChatList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: currentUserId).snapshots(),
      builder: (ctx, snapshot) {
        if (snapshot.hasError) return SocialChatErrorState(error: snapshot.error);
        if (!snapshot.hasData) return _genSkels();
        final chats = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final tA = (a.data() as Map)['lastMessageTime'] as Timestamp?;
            final tB = (b.data() as Map)['lastMessageTime'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1; if (tB == null) return -1;
            return tB.compareTo(tA);
          });
        if (chats.isEmpty) return const SocialEmptyState(icon: Icons.forum_outlined, titulo: 'Sin mensajes aún', subtitulo: 'Ve a Aliados y abre un chat\ncon tus compañeros de ruta');
        return RefreshIndicator(
          key: _rkMensajes, color: kSocAccent, backgroundColor: _p.surface2,
          onRefresh: () async { setState(() {}); },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            itemCount: chats.length,
            itemBuilder: (ctx, i) {
              final chatData = chats[i].data() as Map<String, dynamic>;
              final String chatId = chats[i].id;
              final List parts = chatData['participants'] as List? ?? [];
              final String fid = parts.firstWhere((p) => p != currentUserId, orElse: () => '');
              if (fid.isEmpty) return const SizedBox.shrink();
              final int unread = (chatData['unread_$currentUserId'] as num? ?? 0).toInt();
              if (_perfilesCache.containsKey(fid)) {
                final fd = _perfilesCache[fid]!;
                return SocialStagger(index: i, child: SocialChatCard(
                  chatId: chatId, nickname: fd['nickname'] ?? '?', fotoBase64: fd['foto_base64'] as String?,
                  lastMessage: chatData['lastMessage'] as String? ?? '',
                  lastTime: chatData['lastMessageTime'] as Timestamp?,
                  unread: unread, accent: _accent,
                  onTap: () => _abrirChat(fid, fd['nickname'] ?? '?', fd['foto_base64'] as String?)));
              }
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(fid).get(),
                builder: (ctx, s) {
                  if (!s.hasData) return const SocialSkel();
                  final fd = s.data!.data() as Map<String, dynamic>? ?? {};
                  _perfilesCache[fid] = fd;
                  return SocialStagger(index: i, child: SocialChatCard(
                    chatId: chatId, nickname: fd['nickname'] ?? '?', fotoBase64: fd['foto_base64'] as String?,
                    lastMessage: chatData['lastMessage'] as String? ?? '',
                    lastTime: chatData['lastMessageTime'] as Timestamp?,
                    unread: unread, accent: _accent,
                    onTap: () => _abrirChat(fid, fd['nickname'] ?? '?', fd['foto_base64'] as String?)));
                });
            }));
      });
  }

  // ════════════════════════ SOLICITUDES TAB ══════════════════════════════════════
  Widget _buildRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('friendships')
          .where('receiverId', isEqualTo: currentUserId).where('status', isEqualTo: 'pending').snapshots(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) return _genSkels();
        if (snapshot.hasError) return SocialErrorState(onRetry: () => setState(() {}));
        final solicitudes = snapshot.data!.docs;
        if (solicitudes.isEmpty) return const SocialEmptyState(icon: Icons.inbox_outlined, titulo: 'Sin solicitudes', subtitulo: 'Cuando alguien empiece a seguirte\naparecerá aquí');
        return RefreshIndicator(
          key: _rkSolici, color: kSocAccent, backgroundColor: _p.surface2,
          onRefresh: () async { setState(() {}); },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            itemCount: solicitudes.length,
            itemBuilder: (ctx, i) {
              final doc = solicitudes[i];
              final String senderId = doc['senderId'] as String;
              if (_perfilesCache.containsKey(senderId)) {
                final data = _perfilesCache[senderId]!;
                return SocialStagger(index: i, child: SocialRequestCard(
                  nickname: data['nickname'] ?? '?', nivel: (data['nivel'] as num? ?? 1).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), accent: _accent,
                  onAceptar: () async {
                    await FirebaseFirestore.instance.collection('friendships').doc(doc.id).update({'status': 'accepted'});
                    final isFollowReq = (doc['type'] as String?) == 'follow_request';
                    await FirebaseFirestore.instance.collection('follows').add({
                      'followerId':  isFollowReq ? senderId       : currentUserId,
                      'followingId': isFollowReq ? currentUserId  : senderId,
                      'timestamp':   FieldValue.serverTimestamp(),
                    });
                    _snack('¡${data['nickname']} ahora es tu operativo!');
                  },
                  onRechazar: () => _confirmarRechazo(context, doc.id, data['nickname'] ?? '?')));
              }
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(senderId).get(),
                builder: (ctx, s) {
                  if (!s.hasData) return const SocialSkel();
                  final data = s.data!.data() as Map<String, dynamic>? ?? {};
                  _perfilesCache[senderId] = data;
                  return SocialStagger(index: i, child: SocialRequestCard(
                    nickname: data['nickname'] ?? '?', nivel: (data['nivel'] as num? ?? 1).toInt(),
                    fotoBase64: data['foto_base64'] as String?,
                    puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), accent: _accent,
                    onAceptar: () async {
                      await FirebaseFirestore.instance.collection('friendships').doc(doc.id).update({'status': 'accepted'});
                      final isFollowReq = (doc['type'] as String?) == 'follow_request';
                      await FirebaseFirestore.instance.collection('follows').add({
                        'followerId':  isFollowReq ? senderId      : currentUserId,
                        'followingId': isFollowReq ? currentUserId : senderId,
                        'timestamp':   FieldValue.serverTimestamp(),
                      });
                      _snack('¡${data['nickname']} ahora es tu aliado!');
                    },
                    onRechazar: () => _confirmarRechazo(context, doc.id, data['nickname'] ?? '?')));
                });
            }));
      });
  }

  void _confirmarRechazo(BuildContext ctx, String docId, String nickname) {
    final p = SocialPalette.of(ctx);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: p.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line2)),
      title: Text('Rechazar solicitud', style: TextStyle(color: p.text1, fontSize: 14, fontWeight: FontWeight.w800)),
      content: Text('¿Rechazar la solicitud de $nickname?', style: TextStyle(color: p.text2, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: p.text2))),
        TextButton(onPressed: () { Navigator.pop(ctx); FirebaseFirestore.instance.collection('friendships').doc(docId).delete(); },
          child: const Text('Rechazar', style: TextStyle(color: kSocAccent))),
      ]));
  }

  Widget _genSkels() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), itemCount: 6, itemBuilder: (_, __) => const SocialSkel());
}
