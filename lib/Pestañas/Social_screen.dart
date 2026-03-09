import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Resumen_screen.dart';
import '../Widgets/custom_navbar.dart';
import '../services/league_service.dart';

// =============================================================================
//  PALETA
// =============================================================================
const Color _kBg       = Color(0xFF0A0A0A);
const Color _kSurface  = Color(0xFF141414);
const Color _kSurface2 = Color(0xFF1C1C1C);
const Color _kLine     = Color(0xFF242424);
const Color _kLine2    = Color(0xFF2E2E2E);
const Color _kText1    = Color(0xFFFFFFFF);
const Color _kText2    = Color(0xFFA0A0A0);
const Color _kText3    = Color(0xFF555555);
const Color _kRed      = Color(0xFFC8352A);
const Color _kGreen    = Color(0xFF36B060);
const Color _kBronze   = Color(0xFFE08840);
const Color _kSilver   = Color(0xFFA8C0D4);
const Color _kGoldTier = Color(0xFFF0CC40);
const Color _kPlatinum = Color(0xFF6CA8E0);
const Color _kDiamond  = Color(0xFF70E0F8);
const Color _kGold     = Color(0xFFFFD700);
const Color _kSilver2  = Color(0xFFC0C0C0);
const Color _kBronze2  = Color(0xFFCD7F32);

// =============================================================================
//  SHIMMER
// =============================================================================
class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const _Shimmer({required this.width, required this.height, this.borderRadius = 6});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(
          begin: Alignment(_anim.value - 1, 0), end: Alignment(_anim.value, 0),
          colors: const [_kSurface, _kSurface2, Color(0xFF2A2A2A), _kSurface2, _kSurface],
          stops: const [0.0, 0.3, 0.5, 0.7, 1.0]),
      ),
    ),
  );
}

// =============================================================================
//  BADGE PULSANTE
// =============================================================================
class _PulseBadge extends StatefulWidget {
  final int count;
  final Color color;
  const _PulseBadge({required this.count, required this.color});
  @override
  State<_PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<_PulseBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.18).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 6)],
      ),
      child: Text(widget.count > 9 ? '9+' : '${widget.count}',
        style: TextStyle(
          color: widget.color.computeLuminance() > 0.4 ? Colors.black : Colors.white,
          fontSize: 8, fontWeight: FontWeight.w900)),
    ),
  );
}

// =============================================================================
//  ANIMATED LIST ITEM
// =============================================================================
class _AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;
  const _AnimatedListItem({required this.child, required this.index});
  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  @override
  void initState() {
    super.initState();
    final delay = math.min(widget.index * 60, 400);
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _opacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: delay), () { if (mounted) _ctrl.forward(); });
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// =============================================================================
//  SOCIAL SCREEN
// =============================================================================
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> with TickerProviderStateMixin {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  Color _accent = const Color(0xFF5BBCB8);
  String _searchQuery = '';
  Timer? _debounce;
  List<Map<String, dynamic>> _resultadosBusqueda = [];
  bool _buscando = false;
  bool _errorBusqueda = false;
  int _solicitudesPendientes = 0;
  int _mensajesNoLeidos = 0;
  final Map<String, Map<String, dynamic>> _perfilesAmigosCache = {};
  bool _navegandoAChat = false;
  int _misPuntosLiga = 0;
  String _miLiga = 'BRONCE';
  bool _rankingModeLiga = true;
  String? _ligaSeleccionada;
  StreamSubscription? _solicitudesStream;
  StreamSubscription? _mensajesStream;

  // ── Estado optimista solicitudes ─────────────────────────────────────────────
  final Set<String> _solicitudesEnviadas = {};

  // ── Keys para RefreshIndicator ───────────────────────────────────────────────
  final GlobalKey<RefreshIndicatorState> _refreshKeyRanking  = GlobalKey();
  final GlobalKey<RefreshIndicatorState> _refreshKeyAliados  = GlobalKey();
  final GlobalKey<RefreshIndicatorState> _refreshKeyMensajes = GlobalKey();
  final GlobalKey<RefreshIndicatorState> _refreshKeySolici   = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChange);
    _cargarColorAccent();
    _escucharSolicitudes();
    _escucharMensajesNoLeidos();
    _cargarMiLiga();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q == _searchQuery) return;
    _searchQuery = q;
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() { _resultadosBusqueda = []; _buscando = false; _errorBusqueda = false; });
      return;
    }
    setState(() { _buscando = true; _errorBusqueda = false; });
    _debounce = Timer(const Duration(milliseconds: 350), _buscarEnTiempoReal);
  }

  void _onTabChange() {
    if (_tabController.indexIsChanging) {
      _searchController.clear();
      setState(() { _resultadosBusqueda = []; _errorBusqueda = false; });
    }
  }

  Future<void> _cargarColorAccent() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('players').doc(currentUserId).get();
      if (!doc.exists || !mounted) return;
      final colorInt = (doc.data()?['territorio_color'] as num?)?.toInt();
      if (colorInt != null && mounted) setState(() => _accent = Color(colorInt));
    } catch (e) { debugPrint('Social: error color accent: $e'); }
  }

  Future<void> _cargarMiLiga() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('players').doc(currentUserId).get();
      if (!doc.exists || !mounted) return;
      final pts = (doc.data()?['puntos_liga'] as num? ?? 0).toInt();
      final info = LeagueHelper.getLeague(pts);
      setState(() { _misPuntosLiga = pts; _miLiga = info.name; _ligaSeleccionada = null; });
    } catch (e) { debugPrint('Error liga: $e'); }
  }

  // ── BÚSQUEDA con manejo de error ─────────────────────────────────────────────
  Future<void> _buscarEnTiempoReal() async {
    final q = _searchQuery;
    if (q.isEmpty) { setState(() { _resultadosBusqueda = []; _buscando = false; }); return; }
    try {
      final snap = await FirebaseFirestore.instance.collection('players')
          .where('nickname', isGreaterThanOrEqualTo: q)
          .where('nickname', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(15).get();
      if (!mounted || _searchQuery != q) return;
      final futures = snap.docs.where((doc) => doc.id != currentUserId).map(_procesarResultadoBusqueda).toList();
      final resultados = await Future.wait(futures);
      if (mounted && _searchQuery == q) {
        setState(() {
          _resultadosBusqueda = resultados.whereType<Map<String, dynamic>>().toList();
          _buscando = false;
          _errorBusqueda = false;
        });
      }
    } catch (e) {
      debugPrint('Error búsqueda: $e');
      if (mounted) setState(() { _buscando = false; _errorBusqueda = true; });
    }
  }

  Future<Map<String, dynamic>?> _procesarResultadoBusqueda(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final int monedas = (data['monedas'] as num? ?? 0).toInt();
      final rankSnap = await FirebaseFirestore.instance
          .collection('players').where('monedas', isGreaterThan: monedas).count().get();
      final friendSnap = await FirebaseFirestore.instance
          .collection('friendships').where('senderId', whereIn: [currentUserId, doc.id]).get();
      final int rango = ((rankSnap.count as num?)?.toInt() ?? 0) + 1;
      String relacion = 'ninguna';
      for (final f in friendSnap.docs) {
        final fd = f.data() as Map<String, dynamic>;
        if ((fd['senderId'] == currentUserId && fd['receiverId'] == doc.id) ||
            (fd['senderId'] == doc.id && fd['receiverId'] == currentUserId)) {
          relacion = fd['status'] ?? 'ninguna'; break;
        }
      }
      return {...data, 'id': doc.id, 'rango': rango, 'relacion': relacion};
    } catch (e) { return null; }
  }

  void _escucharSolicitudes() {
    _solicitudesStream = FirebaseFirestore.instance.collection('friendships')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snap) { if (mounted) setState(() => _solicitudesPendientes = snap.docs.length); },
          onError: (e) => debugPrint('Stream solicitudes error: $e'),
        );
  }

  void _escucharMensajesNoLeidos() {
    _mensajesStream = FirebaseFirestore.instance.collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen(
          (snap) {
            int total = 0;
            for (final doc in snap.docs) {
              final data = doc.data() as Map<String, dynamic>;
              total += (data['unread_$currentUserId'] as num? ?? 0).toInt();
            }
            if (mounted) setState(() => _mensajesNoLeidos = total);
          },
          onError: (e) => debugPrint('Stream mensajes error: $e'),
        );
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

  // ── ENVIAR SOLICITUD con estado optimista + rollback ─────────────────────────
  Future<void> _enviarSolicitud(String targetId) async {
    setState(() => _solicitudesEnviadas.add(targetId));
    try {
      await FirebaseFirestore.instance.collection('friendships').add({
        'senderId': currentUserId, 'receiverId': targetId,
        'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
      });
      _buscarEnTiempoReal();
    } catch (e) {
      if (mounted) {
        setState(() => _solicitudesEnviadas.remove(targetId));
        _mostrarSnackError('No se pudo enviar la solicitud. Inténtalo de nuevo.');
      }
    }
  }

  void _mostrarSnackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText1, fontSize: 13)),
      backgroundColor: _kSurface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _kRed.withValues(alpha: 0.4)),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  void _mostrarSnackExito(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText1, fontSize: 13)),
      backgroundColor: _kSurface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _kGreen.withValues(alpha: 0.4)),
      ),
      duration: const Duration(seconds: 2),
    ));
  }

  void _abrirChat(String friendId, String friendNickname, String? friendFoto) {
    if (_navegandoAChat) return;
    _navegandoAChat = true;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        currentUserId: currentUserId, friendId: friendId,
        friendNickname: friendNickname, friendFoto: friendFoto),
    )).whenComplete(() => _navegandoAChat = false);
  }

  // ── REFRESH handlers ─────────────────────────────────────────────────────────
  Future<void> _onRefreshRanking() async {
    await _cargarMiLiga();
    await Future.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _onRefreshAliados() async {
    _perfilesAmigosCache.clear();
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _onRefreshMensajes() async {
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _onRefreshSolicitudes() async {
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));
  }

  // ═══════════════════════════ BUILD ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: _searchQuery.isNotEmpty
            ? _buildSearchResults()
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildRankingTab(),
                  _buildFriendsList(),
                  _buildChatList(),
                  _buildRequestsList(),
                ],
              )),
      ]),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 3),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: _kBg,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: MediaQuery.of(context).padding.top),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('Social', style: TextStyle(color: _kText1, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(width: 10),
              const Text('territorio · ligas · aliados', style: TextStyle(color: _kText3, fontSize: 11, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        _buildSearchBar(),
        Container(height: 1, color: _kLine),
        _buildTabBar(),
      ]),
    );
  }

  Widget _buildSearchBar() {
    final bool active = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: active ? _accent.withValues(alpha: 0.5) : _kLine2),
          borderRadius: BorderRadius.circular(6),
          boxShadow: active ? [BoxShadow(color: _accent.withValues(alpha: 0.08), blurRadius: 12)] : [],
        ),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(Icons.search_rounded, color: active ? _accent : _kText3, size: 16)),
          Expanded(child: TextField(
            controller: _searchController,
            style: const TextStyle(color: _kText1, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Buscar explorador...',
              hintStyle: TextStyle(color: _kText3, fontSize: 13),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
          )),
          if (_buscando)
            Padding(padding: const EdgeInsets.only(right: 12),
              child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: _accent, strokeWidth: 1.5)))
          else if (active)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: const Padding(padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.close_rounded, color: _kText3, size: 16))),
        ]),
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorColor: _accent,
      indicatorWeight: 2,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: _accent,
      unselectedLabelColor: _kText3,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 2),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9, letterSpacing: 1.5),
      dividerColor: Colors.transparent,
      tabs: [
        const Tab(text: 'LIGAS'),
        const Tab(text: 'ALIADOS'),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('MENSAJES'),
          if (_mensajesNoLeidos > 0) ...[const SizedBox(width: 4), _PulseBadge(count: _mensajesNoLeidos, color: _kRed)],
        ])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('SOLICITUDES'),
          if (_solicitudesPendientes > 0) ...[const SizedBox(width: 4), _PulseBadge(count: _solicitudesPendientes, color: _accent)],
        ])),
      ],
    );
  }

  // ── SEARCH RESULTS ───────────────────────────────────────────────────────────
  Widget _buildSearchResults() {
    // Error en búsqueda
    if (_errorBusqueda) {
      return _ErrorState(
        onRetry: () {
          setState(() { _buscando = true; _errorBusqueda = false; });
          _buscarEnTiempoReal();
        },
      );
    }
    if (_resultadosBusqueda.isEmpty && !_buscando) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        titulo: 'Sin exploradores',
        subtitulo: 'Nadie encontrado para "$_searchQuery"\nRevisa la ortografía del nombre',
        accionLabel: 'Limpiar búsqueda',
        onAccion: () => _searchController.clear(),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _resultadosBusqueda.length,
      itemBuilder: (context, i) {
        final u = _resultadosBusqueda[i];
        final bool yaEnviada = _solicitudesEnviadas.contains(u['id']);
        final String relacionEfectiva = yaEnviada ? 'pending' : (u['relacion'] as String? ?? 'ninguna');
        return _AnimatedListItem(
          index: i,
          child: _PlayerCard(
            userId: u['id'],
            nickname: u['nickname'] ?? '?',
            nivel: (u['nivel'] as num? ?? 1).toInt(),
            monedas: (u['monedas'] as num? ?? 0).toInt(),
            rango: (u['rango'] as num? ?? 0).toInt(),
            relacion: relacionEfectiva,
            fotoBase64: u['foto_base64'] as String?,
            puntosLiga: (u['puntos_liga'] as num? ?? 0).toInt(),
            accent: _accent,
            onAgregar: () => _enviarSolicitud(u['id']),
            onVerPerfil: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ResumenScreen(
                targetUserId: u['id'], targetNickname: u['nickname'],
                distancia: 0, tiempo: Duration.zero, ruta: const []))),
          ),
        );
      },
    );
  }

  // ═══════════════════════ RANKING TAB ═════════════════════════════════════════
  Widget _buildRankingTab() {
    final ligaInfo = LeagueHelper.getLeague(_misPuntosLiga);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Container(
          decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            _ToggleBtn(label: 'MI LIGA', emoji: ligaInfo.emoji, active: _rankingModeLiga, activeColor: _accent,
              onTap: () => setState(() { _rankingModeLiga = true; _ligaSeleccionada = null; })),
            Container(width: 1, height: 38, color: _kLine2),
            _ToggleBtn(label: 'GLOBAL', icon: Icons.public_rounded, active: !_rankingModeLiga, activeColor: _accent,
              onTap: () => setState(() { _rankingModeLiga = false; _ligaSeleccionada = null; })),
          ]),
        ),
      ),
      if (_rankingModeLiga) ...[
        if (_ligaSeleccionada != null) _buildBotonVolverLigas(),
        Expanded(child: RefreshIndicator(
          key: _refreshKeyRanking,
          color: _accent,
          backgroundColor: _kSurface2,
          onRefresh: _onRefreshRanking,
          child: _ligaSeleccionada != null
              ? _buildLeagueRankingById(_ligaSeleccionada!)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _LeagueBannerWidget(ligaInfo: ligaInfo, puntosLiga: _misPuntosLiga, accent: _accent),
                    const SizedBox(height: 14),
                    _buildTodasLasLigas(ligaInfo),
                  ],
                ),
        )),
      ] else
        Expanded(child: RefreshIndicator(
          key: _refreshKeyRanking,
          color: _accent,
          backgroundColor: _kSurface2,
          onRefresh: _onRefreshRanking,
          child: _buildGlobalRanking(),
        )),
    ]);
  }

  Widget _buildBotonVolverLigas() {
    final liga = LeagueSystem.ligas.firstWhere((l) => l.id == _ligaSeleccionada, orElse: () => LeagueSystem.ligas.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: GestureDetector(
        onTap: () => setState(() => _ligaSeleccionada = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            const Icon(Icons.arrow_back_ios_rounded, color: _kText3, size: 13),
            const SizedBox(width: 8),
            const Text('Todas las ligas', style: TextStyle(color: _kText3, fontSize: 12, fontStyle: FontStyle.italic)),
            const Spacer(),
            Text(liga.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(liga.name.toUpperCase(), style: TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5)),
          ]),
        ),
      ),
    );
  }

  Widget _buildTodasLasLigas(LeagueInfo miLiga) {
    final List<Color> tierColors = [_kBronze, _kSilver, _kGoldTier, _kPlatinum, _kDiamond];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 10, left: 2),
        child: Text('TODAS LAS LIGAS', style: TextStyle(color: _kText3, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 4)),
      ),
      ...LeagueSystem.ligas.asMap().entries.map((entry) {
        final int idx = entry.key;
        final LeagueInfo liga = entry.value;
        final bool esMiLiga = liga.id == miLiga.id;
        final bool bloqueada = liga.minPts > _misPuntosLiga;
        final Color tierColor = idx < tierColors.length ? tierColors[idx] : _accent;
        return GestureDetector(
          onTap: () => setState(() => _ligaSeleccionada = liga.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: esMiLiga ? _accent.withValues(alpha: 0.08) : _kSurface,
              border: Border.all(color: esMiLiga ? _accent : _kLine2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Text(liga.emoji, style: TextStyle(fontSize: 14 + idx * 0.5)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(liga.name.toUpperCase(), style: TextStyle(
                    color: esMiLiga ? _accent : tierColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  if (esMiLiga) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
                      child: Text('TÚ', style: TextStyle(
                        color: _accent.computeLuminance() > 0.4 ? Colors.black : Colors.white,
                        fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1))),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(liga.maxPts != null ? '${liga.minPts} – ${liga.maxPts} pts' : '${liga.minPts}+ pts',
                  style: const TextStyle(color: _kText3, fontSize: 10, fontStyle: FontStyle.italic)),
              ])),
              if (bloqueada && !esMiLiga)
                const Icon(Icons.lock_outline_rounded, color: _kText3, size: 14)
              else
                Icon(Icons.chevron_right_rounded, color: esMiLiga ? _accent : tierColor.withValues(alpha: 0.6), size: 18),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _buildLeagueRankingById(String ligaId) {
    final liga = LeagueSystem.ligas.firstWhere((l) => l.id == ligaId, orElse: () => LeagueSystem.ligas.first);
    return _buildLeagueRanking(liga);
  }

  Widget _buildLeagueRanking(LeagueInfo ligaInfo) {
    final int minPts = ligaInfo.minPts;
    final int maxPts = ligaInfo.maxPts ?? 999999;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('players')
          .where('puntos_liga', isGreaterThanOrEqualTo: minPts)
          .where('puntos_liga', isLessThanOrEqualTo: maxPts)
          .orderBy('puntos_liga', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _buildRankingSkeletons();
        if (snapshot.hasError) return _ErrorState(onRetry: () => setState(() {}));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _EmptyState(
          icon: Icons.emoji_events_outlined,
          titulo: 'Liga vacía',
          subtitulo: 'Nadie en ${ligaInfo.name} aún.\n¡Sal a conquistar territorio!',
        );
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(children: [
              Text(ligaInfo.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('TOP 100 — ${ligaInfo.name.toUpperCase()}',
                style: TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const Spacer(),
              Text('${docs.length} exploradores',
                style: const TextStyle(color: _kText3, fontSize: 10, fontStyle: FontStyle.italic)),
            ]),
          ),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final bool esYo = docs[i].id == currentUserId;
              final int ptsLiga = (data['puntos_liga'] as num? ?? 0).toInt();
              return _AnimatedListItem(
                index: i,
                child: GestureDetector(
                  onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ResumenScreen(
                      targetUserId: docs[i].id, targetNickname: data['nickname'],
                      distancia: 0, tiempo: Duration.zero, ruta: const []))),
                  child: _RankCard(
                    posicion: i + 1, nickname: data['nickname'] ?? '?',
                    nivel: (data['nivel'] as num? ?? 1).toInt(),
                    monedas: (data['monedas'] as num? ?? 0).toInt(),
                    fotoBase64: data['foto_base64'] as String?,
                    esYo: esYo, puntosLiga: ptsLiga, ligaInfo: ligaInfo, accent: _accent),
                ),
              );
            },
          )),
        ]);
      },
    );
  }

  Widget _buildGlobalRanking() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('players')
          .orderBy('puntos_liga', descending: true).limit(100).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _buildRankingSkeletons();
        if (snapshot.hasError) return _ErrorState(onRetry: () => setState(() {}));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const _EmptyState(
          icon: Icons.public_rounded, titulo: 'Sin jugadores aún',
          subtitulo: 'Sé el primero en conquistar territorio');
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final bool esYo = docs[i].id == currentUserId;
            final int ptsLiga = (data['puntos_liga'] as num? ?? 0).toInt();
            final ligaInfo = LeagueHelper.getLeague(ptsLiga);
            return _AnimatedListItem(
              index: i,
              child: GestureDetector(
                onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ResumenScreen(
                    targetUserId: docs[i].id, targetNickname: data['nickname'],
                    distancia: 0, tiempo: Duration.zero, ruta: const []))),
                child: _RankCard(
                  posicion: i + 1, nickname: data['nickname'] ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(),
                  monedas: (data['monedas'] as num? ?? 0).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  esYo: esYo, puntosLiga: ptsLiga, ligaInfo: ligaInfo, accent: _accent),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRankingSkeletons() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: 8,
    itemBuilder: (_, i) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _CardSkeleton(height: i < 3 ? 88 : 62)),
  );

  // ═══════════════════════ ALIADOS TAB ═════════════════════════════════════════
  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('friendships')
          .where('status', isEqualTo: 'accepted').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _buildGenericSkeletons();
        if (snapshot.hasError) return _ErrorState(onRetry: () { _perfilesAmigosCache.clear(); setState(() {}); });
        final misAmigos = snapshot.data!.docs.where((doc) =>
          doc['senderId'] == currentUserId || doc['receiverId'] == currentUserId).toList();
        if (misAmigos.isEmpty) return _EmptyState(
          icon: Icons.group_outlined,
          titulo: 'Sin aliados aún',
          subtitulo: 'Busca exploradores y únete\na su aventura cartográfica',
          accionLabel: 'Buscar exploradores',
          onAccion: () => _searchController.clear(),
        );
        return RefreshIndicator(
          key: _refreshKeyAliados,
          color: _accent,
          backgroundColor: _kSurface2,
          onRefresh: _onRefreshAliados,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: misAmigos.length,
            itemBuilder: (context, i) {
              final friendId = misAmigos[i]['senderId'] == currentUserId
                  ? misAmigos[i]['receiverId'] : misAmigos[i]['senderId'];
              if (_perfilesAmigosCache.containsKey(friendId)) {
                final data = _perfilesAmigosCache[friendId]!;
                return _AnimatedListItem(index: i, child: _buildFriendCardFromData(data, friendId));
              }
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(friendId).get(),
                builder: (context, s) {
                  if (!s.hasData) return const _CardSkeleton();
                  if (s.hasError) return const _CardSkeleton();
                  final data = s.data!.data() as Map<String, dynamic>? ?? {};
                  _perfilesAmigosCache[friendId] = data;
                  return _AnimatedListItem(index: i, child: _buildFriendCardFromData(data, friendId));
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFriendCardFromData(Map<String, dynamic> data, String friendId) {
    return _FriendCard(
      nickname: data['nickname'] ?? '?',
      nivel: (data['nivel'] as num? ?? 1).toInt(),
      monedas: (data['monedas'] as num? ?? 0).toInt(),
      fotoBase64: data['foto_base64'] as String?,
      puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(),
      accent: _accent,
      onChat: () => _abrirChat(friendId, data['nickname'] ?? '?', data['foto_base64'] as String?),
      onPerfil: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ResumenScreen(targetUserId: friendId,
          targetNickname: data['nickname'], distancia: 0,
          tiempo: Duration.zero, ruta: const []))),
    );
  }

  // ═══════════════════════ MENSAJES TAB ════════════════════════════════════════
  Widget _buildChatList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chats')
          .where('participants', arrayContains: currentUserId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ChatErrorState(error: snapshot.error);
        if (!snapshot.hasData) return _buildGenericSkeletons();
        final chats = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final tA = (a.data() as Map)['lastMessageTime'] as Timestamp?;
            final tB = (b.data() as Map)['lastMessageTime'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });
        if (chats.isEmpty) return const _EmptyState(
          icon: Icons.mail_outline_rounded,
          titulo: 'Sin mensajes aún',
          subtitulo: 'Ve a Aliados y abre un chat\ncon tus compañeros de ruta',
        );
        return RefreshIndicator(
          key: _refreshKeyMensajes,
          color: _accent,
          backgroundColor: _kSurface2,
          onRefresh: _onRefreshMensajes,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final chatData = chats[i].data() as Map<String, dynamic>;
              final String chatId = chats[i].id;
              final List parts = chatData['participants'] as List? ?? [];
              final String friendId = parts.firstWhere((p) => p != currentUserId, orElse: () => '');
              if (friendId.isEmpty) return const SizedBox.shrink();
              final int unread = (chatData['unread_$currentUserId'] as num? ?? 0).toInt();
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(friendId).get(),
                builder: (context, s) {
                  if (!s.hasData) return const _CardSkeleton();
                  if (s.hasError) return const _CardSkeleton();
                  final fd = s.data!.data() as Map<String, dynamic>? ?? {};
                  return _AnimatedListItem(
                    index: i,
                    child: _ChatPreviewCard(
                      chatId: chatId, nickname: fd['nickname'] ?? '?',
                      fotoBase64: fd['foto_base64'] as String?,
                      lastMessage: chatData['lastMessage'] as String? ?? '',
                      lastTime: chatData['lastMessageTime'] as Timestamp?,
                      unread: unread, accent: _accent,
                      onTap: () => _abrirChat(friendId, fd['nickname'] ?? '?', fd['foto_base64'] as String?),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════ SOLICITUDES TAB ═════════════════════════════════════
  Widget _buildRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('friendships')
          .where('receiverId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _buildGenericSkeletons();
        if (snapshot.hasError) return _ErrorState(onRetry: () => setState(() {}));
        final solicitudes = snapshot.data!.docs;
        if (solicitudes.isEmpty) return const _EmptyState(
          icon: Icons.inbox_outlined,
          titulo: 'Sin solicitudes',
          subtitulo: 'Las invitaciones de alianza\naparecerán aquí',
        );
        return RefreshIndicator(
          key: _refreshKeySolici,
          color: _accent,
          backgroundColor: _kSurface2,
          onRefresh: _onRefreshSolicitudes,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: solicitudes.length,
            itemBuilder: (context, i) {
              final doc = solicitudes[i];
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(doc['senderId']).get(),
                builder: (context, s) {
                  if (!s.hasData) return const _CardSkeleton();
                  if (s.hasError) return const _CardSkeleton();
                  final data = s.data!.data() as Map<String, dynamic>? ?? {};
                  return _AnimatedListItem(
                    index: i,
                    child: _RequestCard(
                      nickname: data['nickname'] ?? '?',
                      nivel: (data['nivel'] as num? ?? 1).toInt(),
                      fotoBase64: data['foto_base64'] as String?,
                      puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(),
                      accent: _accent,
                      onAceptar: () async {
                        await FirebaseFirestore.instance
                            .collection('friendships').doc(doc.id).update({'status': 'accepted'});
                        _mostrarSnackExito('¡${data['nickname']} ahora es tu aliado!');
                      },
                      onRechazar: () => _confirmarRechazo(context, doc.id, data['nickname'] ?? '?'),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // ── CONFIRMAR RECHAZO ────────────────────────────────────────────────────────
  void _confirmarRechazo(BuildContext context, String docId, String nickname) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _kLine2)),
        title: const Text('Rechazar solicitud',
          style: TextStyle(color: _kText1, fontSize: 15, fontWeight: FontWeight.w800)),
        content: Text('¿Seguro que quieres rechazar la solicitud de $nickname?',
          style: const TextStyle(color: _kText2, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: _accent))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              FirebaseFirestore.instance.collection('friendships').doc(docId).delete();
            },
            child: const Text('Rechazar', style: TextStyle(color: _kRed))),
        ],
      ),
    );
  }

  Widget _buildGenericSkeletons() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: 6,
    itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 8), child: _CardSkeleton()),
  );
}

// =============================================================================
//  LEAGUE BANNER
// =============================================================================
class _LeagueBannerWidget extends StatelessWidget {
  final LeagueInfo ligaInfo;
  final int puntosLiga;
  final Color accent;
  const _LeagueBannerWidget({required this.ligaInfo, required this.puntosLiga, required this.accent});

  @override
  Widget build(BuildContext context) {
    final double progress  = LeagueHelper.getProgress(puntosLiga);
    final int faltanPts    = LeagueHelper.ptsParaSiguiente(puntosLiga);
    const int totalSeg     = 10;
    final int conquistados = (progress * totalSeg).floor().clamp(0, totalSeg - 1);

    return Container(
      decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 2, decoration: BoxDecoration(
          color: accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(8)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 7, height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _kRed,
                  boxShadow: [BoxShadow(color: _kRed, blurRadius: 6)])),
              const SizedBox(width: 7),
              const Text('ACTIVO', style: TextStyle(color: _kRed, fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700)),
              Expanded(child: Container(margin: const EdgeInsets.only(left: 8), height: 1, color: _kRed.withValues(alpha: 0.2))),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(width: 52, height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.05),
                  border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 12)]),
                child: Center(child: Text(ligaInfo.emoji, style: const TextStyle(fontSize: 24)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIGA ACTUAL', style: TextStyle(color: _kText3, fontSize: 8, letterSpacing: 4, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(ligaInfo.name.toUpperCase(), style: const TextStyle(color: _kText1, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ])),
            ]),
            Container(margin: const EdgeInsets.symmetric(vertical: 14), height: 1, color: _kLine),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$puntosLiga', style: const TextStyle(color: _kText1, fontSize: 56, fontWeight: FontWeight.w900, height: 0.9, letterSpacing: -3)),
                const Text('puntos de liga', style: TextStyle(color: _kText2, fontSize: 11, fontStyle: FontStyle.italic)),
              ])),
              if (faltanPts > 0) ...[
                Container(width: 1, height: 52, color: _kLine, margin: const EdgeInsets.symmetric(horizontal: 14)),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$faltanPts', style: const TextStyle(color: _kText2, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  const Text('para ascender', style: TextStyle(color: _kText3, fontSize: 10, fontStyle: FontStyle.italic)),
                ]),
              ],
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Text('PROGRESO', style: TextStyle(color: _kText3, fontSize: 8, letterSpacing: 3, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(progress * 100).toInt()}%', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 7),
            Row(children: List.generate(totalSeg, (i) {
              final bool c = i < conquistados;
              final bool f = i == conquistados;
              return Expanded(child: Container(
                margin: const EdgeInsets.only(right: 3), height: 12,
                decoration: BoxDecoration(
                  color: c ? accent.withValues(alpha: 0.5) : f ? accent : accent.withValues(alpha: 0.05),
                  border: Border.all(color: c ? accent.withValues(alpha: 0.7) : f ? accent : _kLine2),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: f ? [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 8)] : [],
                ),
              ));
            })),
            const SizedBox(height: 8),
            Text(faltanPts > 0 ? 'Faltan $faltanPts pts para ascender' : '🏆 Liga máxima alcanzada',
              style: const TextStyle(color: _kText3, fontSize: 11, fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }
}

// =============================================================================
//  CHAT SCREEN
// =============================================================================
class ChatScreen extends StatefulWidget {
  final String currentUserId, friendId, friendNickname;
  final String? friendFoto;
  const ChatScreen({super.key, required this.currentUserId, required this.friendId,
    required this.friendNickname, this.friendFoto});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final String _chatId;
  late final CollectionReference _messagesRef;
  late final DocumentReference _chatRef;
  int _ultimoConteoMensajes = 0;

  @override
  void initState() {
    super.initState();
    final sorted = [widget.currentUserId, widget.friendId]..sort();
    _chatId = sorted.join('_');
    _chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    _messagesRef = _chatRef.collection('messages');
    _marcarLeido();
  }

  @override
  void dispose() { _msgController.dispose(); _scrollController.dispose(); super.dispose(); }

  Future<void> _marcarLeido() async {
    await _chatRef.set({'unread_${widget.currentUserId}': 0}, SetOptions(merge: true));
  }

  Future<void> _enviarMensaje() async {
    final texto = _msgController.text.trim();
    if (texto.isEmpty) return;
    _msgController.clear();
    final now = FieldValue.serverTimestamp();
    await _messagesRef.add({'senderId': widget.currentUserId, 'text': texto, 'timestamp': now});
    await _chatRef.set({
      'participants': [widget.currentUserId, widget.friendId],
      'lastMessage': texto, 'lastMessageTime': now,
      'lastSenderId': widget.currentUserId,
      'unread_${widget.currentUserId}': 0,
      'unread_${widget.friendId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg, elevation: 0, surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kLine)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _kText1, size: 17),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          _InkAvatar(fotoBase64: widget.friendFoto, size: 34),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.friendNickname, style: const TextStyle(color: _kText1, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
            const Text('EN LÍNEA', style: TextStyle(color: _kText3, fontSize: 8, letterSpacing: 2)),
          ]),
        ]),
        actions: [Padding(padding: const EdgeInsets.only(right: 14),
          child: Icon(Icons.more_horiz, color: _kText3, size: 20))],
      ),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _messagesRef.orderBy('timestamp', descending: false).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: _kText3, strokeWidth: 1.5)));
            final msgs = snapshot.data!.docs;
            if (msgs.length > _ultimoConteoMensajes) {
              _ultimoConteoMensajes = msgs.length;
              if (msgs.isNotEmpty) {
                final last = msgs.last.data() as Map<String, dynamic>;
                if (last['senderId'] != widget.currentUserId) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLeido());
                }
              }
            }
            if (msgs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 56, height: 56,
                decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kLine2)),
                child: const Icon(Icons.mail_outline_rounded, color: _kText3, size: 22)),
              const SizedBox(height: 12),
              Text('¡Saluda a ${widget.friendNickname}!',
                style: const TextStyle(color: _kText2, fontSize: 13, fontStyle: FontStyle.italic)),
            ]));
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: msgs.length,
              itemBuilder: (context, i) {
                final m = msgs[i].data() as Map<String, dynamic>;
                final bool esMio = m['senderId'] == widget.currentUserId;
                final Timestamp? ts = m['timestamp'] as Timestamp?;
                final DateTime? fecha = ts?.toDate();
                return _BubbleMensaje(
                  texto: m['text'] ?? '', esMio: esMio,
                  hora: fecha != null ? '${fecha.hour.toString().padLeft(2,'0')}:${fecha.minute.toString().padLeft(2,'0')}' : '');
              },
            );
          },
        )),
        _buildInputBar(),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(color: _kBg, border: Border(top: BorderSide(color: _kLine))),
      child: SafeArea(top: false, child: Row(children: [
        Expanded(child: Container(
          decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(6)),
          child: TextField(
            controller: _msgController,
            style: const TextStyle(color: _kText1, fontSize: 13),
            maxLines: null, textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'Escribe un mensaje...',
              hintStyle: TextStyle(color: _kText3, fontSize: 13),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10))))),
        const SizedBox(width: 8),
        GestureDetector(onTap: _enviarMensaje,
          child: Container(width: 42, height: 42,
            decoration: BoxDecoration(color: _kText1, borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.send_rounded, color: _kBg, size: 17))),
      ])),
    );
  }
}

// =============================================================================
//  WIDGETS REUTILIZABLES
// =============================================================================

class _InkAvatar extends StatelessWidget {
  final String? fotoBase64;
  final double size;
  final Color? borderColor;
  const _InkAvatar({this.fotoBase64, this.size = 40, this.borderColor});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: _kSurface2, shape: BoxShape.circle,
      border: Border.all(color: borderColor ?? _kLine2, width: 1.5)),
    child: ClipOval(child: fotoBase64 != null
      ? Image.memory(base64Decode(fotoBase64!), fit: BoxFit.cover)
      : Icon(Icons.person_rounded, color: _kText3, size: size * 0.45)));
}

class _CardSkeleton extends StatelessWidget {
  final double height;
  const _CardSkeleton({this.height = 64});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _kLine2)),
      clipBehavior: Clip.hardEdge,
      child: Row(children: [
        _Shimmer(width: 56, height: height),
        const SizedBox(width: 12),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Shimmer(width: 120, height: 12),
          const SizedBox(height: 8),
          _Shimmer(width: 80, height: 9),
        ])),
        const SizedBox(width: 12),
        _Shimmer(width: 48, height: 28, borderRadius: 6),
        const SizedBox(width: 12),
      ]),
    ),
  );
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final String? emoji;
  final IconData? icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _ToggleBtn({required this.label, this.emoji, this.icon,
    required this.active, required this.activeColor, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 13)),
        if (icon  != null) Icon(icon, color: active ? activeColor : _kText3, size: 13),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: active ? activeColor : _kText3,
          fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
      ]),
    )));
}

class _PillTag extends StatelessWidget {
  final String label;
  final Color color;
  const _PillTag({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(3)),
    child: Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)));
}

// ── PLAYER CARD ───────────────────────────────────────────────────────────────
class _PlayerCard extends StatelessWidget {
  final String userId, nickname, relacion;
  final int nivel, monedas, rango, puntosLiga;
  final String? fotoBase64;
  final Color accent;
  final VoidCallback onAgregar, onVerPerfil;
  const _PlayerCard({required this.userId, required this.nickname, required this.nivel,
    required this.monedas, required this.rango, required this.relacion, this.fotoBase64,
    required this.puntosLiga, required this.accent, required this.onAgregar, required this.onVerPerfil});
  @override
  Widget build(BuildContext context) {
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    return GestureDetector(onTap: onVerPerfil,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          _InkAvatar(fotoBase64: fotoBase64, size: 44, borderColor: ligaInfo.color.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(nickname, style: const TextStyle(color: _kText1, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              _PillTag(label: 'NIV. $nivel', color: accent),
              const SizedBox(width: 5),
              _PillTag(label: '${ligaInfo.emoji} ${ligaInfo.name}', color: ligaInfo.color),
            ]),
            const SizedBox(height: 4),
            Text('$monedas 🪙  ·  Rango #$rango',
              style: const TextStyle(color: _kText3, fontSize: 11, fontStyle: FontStyle.italic)),
          ])),
          const SizedBox(width: 8),
          _RelacionBtn(relacion: relacion, accent: accent, onAgregar: onAgregar),
        ]),
      ));
  }
}

class _RelacionBtn extends StatelessWidget {
  final String relacion;
  final Color accent;
  final VoidCallback onAgregar;
  const _RelacionBtn({required this.relacion, required this.accent, required this.onAgregar});
  @override
  Widget build(BuildContext context) {
    if (relacion == 'accepted') return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.08), border: Border.all(color: _kGreen.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6)),
      child: const Text('ALIADO', style: TextStyle(color: _kGreen, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)));
    if (relacion == 'pending') return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08), border: Border.all(color: accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6)),
      child: Text('PENDIENTE', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)));
    return GestureDetector(onTap: onAgregar,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
        child: Text('+ UNIRSE', style: TextStyle(
          color: accent.computeLuminance() > 0.4 ? Colors.black : Colors.white,
          fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5))));
  }
}

// ── RANK CARD ─────────────────────────────────────────────────────────────────
class _RankCard extends StatelessWidget {
  final int posicion, nivel, monedas, puntosLiga;
  final String nickname;
  final String? fotoBase64;
  final bool esYo;
  final LeagueInfo ligaInfo;
  final Color accent;
  const _RankCard({required this.posicion, required this.nickname, required this.nivel,
    required this.monedas, this.fotoBase64, required this.esYo,
    required this.puntosLiga, required this.ligaInfo, required this.accent});

  Color get _medalColor {
    if (posicion == 1) return _kGold;
    if (posicion == 2) return _kSilver2;
    if (posicion == 3) return _kBronze2;
    return _kText3;
  }

  @override
  Widget build(BuildContext context) {
    final bool top3 = posicion <= 3;
    final bool destacado = esYo || top3;
    final Color barColor = esYo ? accent : _medalColor;
    final double vertPad = top3 ? 14.0 : 10.0;
    final double avatarSize = top3 ? 40.0 : 34.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: vertPad),
            decoration: BoxDecoration(
              color: top3
                  ? Color.lerp(_kSurface, barColor.withValues(alpha: 0.12), 0.6)
                  : esYo ? accent.withValues(alpha: 0.06) : _kSurface,
              border: Border.all(color: destacado ? barColor.withValues(alpha: 0.35) : _kLine2),
              borderRadius: BorderRadius.circular(6),
              boxShadow: top3 ? [BoxShadow(color: barColor.withValues(alpha: 0.12), blurRadius: 16)] : [],
            ),
            child: Row(children: [
              SizedBox(width: 40, child: top3
                ? Text(['🥇','🥈','🥉'][posicion - 1],
                    style: TextStyle(fontSize: posicion == 1 ? 26 : 22), textAlign: TextAlign.center)
                : Text('#$posicion', style: const TextStyle(color: _kText3, fontWeight: FontWeight.w900, fontSize: 11), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              _InkAvatar(fotoBase64: fotoBase64, size: avatarSize,
                borderColor: top3 ? barColor.withValues(alpha: 0.7) : ligaInfo.color.withValues(alpha: 0.5)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname + (esYo ? '  (Tú)' : ''), style: TextStyle(
                  color: esYo ? accent : _kText1,
                  fontWeight: top3 ? FontWeight.w900 : FontWeight.w700,
                  fontSize: top3 ? 14 : 13)),
                const SizedBox(height: 3),
                Row(children: [
                  Text('Niv. $nivel', style: const TextStyle(color: _kText3, fontSize: 10)),
                  const SizedBox(width: 8),
                  _PillTag(label: '${ligaInfo.emoji} ${ligaInfo.name}', color: ligaInfo.color),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$puntosLiga', style: TextStyle(
                  color: top3 ? barColor : accent,
                  fontWeight: FontWeight.w900,
                  fontSize: top3 ? 18 : 14,
                  letterSpacing: -0.5)),
                const Text('pts', style: TextStyle(color: _kText3, fontSize: 9)),
              ]),
            ]),
          ),
          if (destacado)
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 3, decoration: BoxDecoration(
                color: barColor,
                boxShadow: top3 ? [BoxShadow(color: barColor.withValues(alpha: 0.6), blurRadius: 8)] : []))),
        ]),
      ),
    );
  }
}

// ── FRIEND CARD ───────────────────────────────────────────────────────────────
class _FriendCard extends StatelessWidget {
  final String nickname;
  final int nivel, monedas, puntosLiga;
  final String? fotoBase64;
  final Color accent;
  final VoidCallback onChat, onPerfil;
  const _FriendCard({required this.nickname, required this.nivel, required this.monedas,
    required this.puntosLiga, this.fotoBase64, required this.accent, required this.onChat, required this.onPerfil});
  @override
  Widget build(BuildContext context) {
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        _InkAvatar(fotoBase64: fotoBase64, size: 42, borderColor: ligaInfo.color.withValues(alpha: 0.6)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nickname, style: const TextStyle(color: _kText1, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 3),
          Row(children: [
            Text('Nivel $nivel', style: const TextStyle(color: _kText2, fontSize: 11)),
            const SizedBox(width: 6),
            _PillTag(label: '${ligaInfo.emoji} ${ligaInfo.name}', color: ligaInfo.color),
          ]),
        ])),
        GestureDetector(onTap: onPerfil,
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: _kSurface2, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.map_outlined, color: _kText3, size: 15))),
        const SizedBox(width: 6),
        GestureDetector(onTap: onChat,
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 8)]),
            child: Icon(Icons.chat_bubble_outline_rounded,
              color: accent.computeLuminance() > 0.4 ? Colors.black : Colors.white, size: 15))),
      ]),
    );
  }
}

// ── CHAT PREVIEW CARD ─────────────────────────────────────────────────────────
class _ChatPreviewCard extends StatelessWidget {
  final String chatId, nickname;
  final String? fotoBase64;
  final String lastMessage;
  final Timestamp? lastTime;
  final int unread;
  final Color accent;
  final VoidCallback onTap;
  const _ChatPreviewCard({required this.chatId, required this.nickname, this.fotoBase64,
    required this.lastMessage, this.lastTime, required this.unread,
    required this.accent, required this.onTap});

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate(); final now = DateTime.now(); final dif = now.difference(d);
    if (dif.inDays == 0) return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    if (dif.inDays == 1) return 'Ayer';
    if (dif.inDays < 7)  return '${dif.inDays}d';
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final bool h = unread > 0;
    return GestureDetector(onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(children: [
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: h ? _kSurface2 : _kSurface,
              border: Border.all(color: h ? accent.withValues(alpha: 0.4) : _kLine2),
              borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              _InkAvatar(fotoBase64: fotoBase64, size: 42),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname, style: TextStyle(
                  color: h ? _kText1 : _kText2,
                  fontWeight: h ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                const SizedBox(height: 3),
                Text(lastMessage.isEmpty ? 'Inicia la conversación' : lastMessage,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: h ? _kText2 : _kText3, fontSize: 11,
                    fontStyle: FontStyle.italic, fontWeight: h ? FontWeight.w500 : FontWeight.w400)),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_formatTime(lastTime), style: TextStyle(
                  color: h ? accent.withValues(alpha: 0.8) : _kText3, fontSize: 10)),
                if (h) ...[const SizedBox(height: 5), _PulseBadge(count: unread, color: accent)],
              ]),
            ]),
          ),
          if (h)
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: accent)),
        ]),
      ));
  }
}

// ── REQUEST CARD ──────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  final String nickname;
  final int nivel, puntosLiga;
  final String? fotoBase64;
  final Color accent;
  final VoidCallback onAceptar, onRechazar;
  const _RequestCard({required this.nickname, required this.nivel, this.fotoBase64,
    required this.puntosLiga, required this.accent, required this.onAceptar, required this.onRechazar});
  @override
  Widget build(BuildContext context) {
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        _InkAvatar(fotoBase64: fotoBase64, size: 44, borderColor: ligaInfo.color.withValues(alpha: 0.6)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nickname, style: const TextStyle(color: _kText1, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 3),
          Row(children: [
            Text('Nivel $nivel', style: const TextStyle(color: _kText2, fontSize: 11)),
            const SizedBox(width: 6),
            _PillTag(label: '${ligaInfo.emoji} ${ligaInfo.name}', color: ligaInfo.color),
          ]),
        ])),
        GestureDetector(onTap: onRechazar,
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.1),
              border: Border.all(color: _kRed.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.close_rounded, color: _kRed, size: 16))),
        const SizedBox(width: 8),
        GestureDetector(onTap: onAceptar,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 8)]),
            child: Text('ACEPTAR', style: TextStyle(
              color: accent.computeLuminance() > 0.4 ? Colors.black : Colors.white,
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)))),
      ]),
    );
  }
}

// ── BUBBLE MENSAJE ────────────────────────────────────────────────────────────
class _BubbleMensaje extends StatelessWidget {
  final String texto, hora;
  final bool esMio;
  const _BubbleMensaje({required this.texto, required this.esMio, required this.hora});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 7, left: esMio ? 56 : 0, right: esMio ? 0 : 56),
    child: Align(
      alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: esMio ? _kText1 : _kSurface2,
          border: esMio ? null : Border.all(color: _kLine2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(
          crossAxisAlignment: esMio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(texto, style: TextStyle(color: esMio ? _kBg : _kText1, fontSize: 13)),
            const SizedBox(height: 3),
            Text(hora, style: TextStyle(color: esMio ? _kBg.withValues(alpha: 0.4) : _kText3, fontSize: 9)),
          ]))));
}

// ── CHAT ERROR ────────────────────────────────────────────────────────────────
class _ChatErrorState extends StatelessWidget {
  final Object? error;
  const _ChatErrorState({this.error});
  @override
  Widget build(BuildContext context) {
    final String detalle = error?.toString() ?? 'Error desconocido';
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: _kRed.withValues(alpha: 0.3)),
            color: _kRed.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.wifi_off_rounded, color: _kRed.withValues(alpha: 0.5), size: 28)),
        const SizedBox(height: 14),
        const Text('Error de conexión', style: TextStyle(color: _kText1, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('No se pudieron cargar los mensajes.\nComprueba tu conexión e inténtalo de nuevo.',
          style: TextStyle(color: _kText2, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _kSurface,
            border: Border.all(color: _kRed.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(6)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: _kRed.withValues(alpha: 0.5), size: 13),
            const SizedBox(width: 8),
            Expanded(child: Text(detalle,
              style: const TextStyle(color: _kText3, fontSize: 10, fontFamily: 'monospace'),
              maxLines: 3, overflow: TextOverflow.ellipsis)),
          ])),
      ])));
  }
}

// ── ERROR STATE genérico con reintentar ───────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 56, height: 56,
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.05),
        border: Border.all(color: _kRed.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12)),
      child: Icon(Icons.wifi_off_rounded, color: _kRed.withValues(alpha: 0.5), size: 24)),
    const SizedBox(height: 14),
    const Text('Error de conexión', style: TextStyle(color: _kText1, fontWeight: FontWeight.w700, fontSize: 15)),
    const SizedBox(height: 6),
    const Text('No se pudo cargar la información',
      style: TextStyle(color: _kText2, fontSize: 12, fontStyle: FontStyle.italic)),
    const SizedBox(height: 16),
    GestureDetector(onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: _kSurface2, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(6)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.refresh_rounded, color: _kText2, size: 14),
          SizedBox(width: 6),
          Text('Reintentar', style: TextStyle(color: _kText2, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      )),
  ]));
}

// ── EMPTY STATE con acción opcional ──────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String titulo, subtitulo;
  final String? accionLabel;
  final VoidCallback? onAccion;
  const _EmptyState({required this.icon, required this.titulo, required this.subtitulo,
    this.accionLabel, this.onAccion});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
        decoration: BoxDecoration(color: _kSurface2, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: _kText3, size: 24)),
      const SizedBox(height: 14),
      Text(titulo, style: const TextStyle(color: _kText1, fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 6),
      Text(subtitulo, style: const TextStyle(color: _kText2, fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
      if (accionLabel != null && onAccion != null) ...[
        const SizedBox(height: 18),
        GestureDetector(onTap: onAccion,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(color: _kSurface2, border: Border.all(color: _kLine2), borderRadius: BorderRadius.circular(6)),
            child: Text(accionLabel!, style: const TextStyle(color: _kText2, fontSize: 12, fontWeight: FontWeight.w700)))),
      ],
    ]),
  ));
}