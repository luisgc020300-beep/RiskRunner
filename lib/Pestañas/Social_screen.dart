import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Resumen_screen.dart';
import '../Widgets/custom_navbar.dart';
import '../services/league_service.dart';

// =============================================================================
//  PALETA DARK PERGAMINO — mismos acentos, fondos oscuros
// =============================================================================
const Color _kBg           = Color(0xFF0C0905);   // fondo global — negro tinta
const Color _kSurface      = Color(0xFF14100A);   // superficie cards
const Color _kSurface2     = Color(0xFF1C1610);   // superficie secundaria
const Color _kHeader       = Color(0xFF100D08);   // header/appbar
const Color _kBorder       = Color(0xFF2A2218);   // bordes sutiles
const Color _kBorder2      = Color(0xFF352B1E);   // bordes más visibles

// Acentos — idénticos al original
const Color _kGold         = Color(0xFFC8922A);
const Color _kGoldLight    = Color(0xFFE8B84B);
const Color _kTerracotta   = Color(0xFFB85C38);
const Color _kSage         = Color(0xFF6B7F5E);
const Color _kMapBlue      = Color(0xFF4A6FA5);

// Textos
const Color _kTextPrimary  = Color(0xFFE8D9B8);   // texto principal — pergamino claro
const Color _kTextMuted    = Color(0xFF7A6548);    // texto secundario
const Color _kTextDim      = Color(0xFF4A3820);    // texto muy apagado

// =============================================================================
//  PAINTERS DE TEXTURA
// =============================================================================
class _ParchmentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Ruido de puntos dorados muy sutiles
    paint.color = _kGold.withValues(alpha: 0.025);
    for (int i = 0; i < 120; i++) {
      final x = (i * 137.5) % size.width;
      final y = (i * 89.3) % size.height;
      canvas.drawCircle(Offset(x, y), 1.0, paint);
    }

    // Líneas diagonales — pergamino envejecido
    paint.color = _kGold.withValues(alpha: 0.018);
    paint.strokeWidth = 0.5;
    paint.style = PaintingStyle.stroke;
    for (double d = -size.height; d < size.width + size.height; d += 28) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
    }

    // Viñeta oscura en bordes
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.15)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignette);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CardTexturePainter extends CustomPainter {
  final Color color;
  const _CardTexturePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.04)
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;

    for (double d = 0; d < size.width + size.height; d += 18) {
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// =============================================================================
//  SOCIAL SCREEN
// =============================================================================
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with TickerProviderStateMixin {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  late AnimationController _headerAnim;

  String _searchQuery = '';
  Timer? _debounce;

  List<Map<String, dynamic>> _resultadosBusqueda = [];
  bool _buscando = false;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChange);
    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _escucharSolicitudes();
    _escucharMensajesNoLeidos();
    _cargarMiLiga();

    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q == _searchQuery) return;
      _searchQuery = q;
      _debounce?.cancel();
      if (q.isEmpty) {
        setState(() { _resultadosBusqueda = []; _buscando = false; });
        return;
      }
      setState(() => _buscando = true);
      _debounce = Timer(const Duration(milliseconds: 350), _buscarEnTiempoReal);
    });
  }

  void _onTabChange() {
    if (_tabController.indexIsChanging) {
      _searchController.clear();
      setState(() => _resultadosBusqueda = []);
    }
  }

  Future<void> _cargarMiLiga() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(currentUserId).get();
      if (!doc.exists || !mounted) return;
      final pts = (doc.data()?['puntos_liga'] as num? ?? 0).toInt();
      final info = LeagueHelper.getLeague(pts);
      setState(() {
        _misPuntosLiga = pts;
        _miLiga = info.name;
        _ligaSeleccionada = null;
      });
    } catch (e) { debugPrint('Error cargando liga: $e'); }
  }

  Future<void> _buscarEnTiempoReal() async {
    final q = _searchQuery;
    if (q.isEmpty) {
      setState(() { _resultadosBusqueda = []; _buscando = false; });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('players')
          .where('nickname', isGreaterThanOrEqualTo: q)
          .where('nickname', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(15).get();

      if (!mounted || _searchQuery != q) return;

      final futures = snap.docs
          .where((doc) => doc.id != currentUserId)
          .map(_procesarResultadoBusqueda).toList();

      final resultados = await Future.wait(futures);
      if (mounted && _searchQuery == q) {
        setState(() {
          _resultadosBusqueda = resultados.whereType<Map<String, dynamic>>().toList();
          _buscando = false;
        });
      }
    } catch (e) {
      debugPrint('Error búsqueda: $e');
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<Map<String, dynamic>?> _procesarResultadoBusqueda(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final int monedas = (data['monedas'] as num? ?? 0).toInt();
      final rankSnap = await FirebaseFirestore.instance
          .collection('players').where('monedas', isGreaterThan: monedas).count().get();
      final friendSnap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('senderId', whereIn: [currentUserId, doc.id]).get();
      final int rango = ((rankSnap.count as num?)?.toInt() ?? 0) + 1;
      String relacion = 'ninguna';
      for (final f in friendSnap.docs) {
        final fd = f.data() as Map<String, dynamic>;
        if ((fd['senderId'] == currentUserId && fd['receiverId'] == doc.id) ||
            (fd['senderId'] == doc.id && fd['receiverId'] == currentUserId)) {
          relacion = fd['status'] ?? 'ninguna';
          break;
        }
      }
      return {...data, 'id': doc.id, 'rango': rango, 'relacion': relacion};
    } catch (e) { return null; }
  }

  void _escucharSolicitudes() {
    _solicitudesStream = FirebaseFirestore.instance
        .collection('friendships')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _solicitudesPendientes = snap.docs.length);
    });
  }

  void _escucharMensajesNoLeidos() {
    _mensajesStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen((snap) {
      int total = 0;
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        total += (data['unread_$currentUserId'] as num? ?? 0).toInt();
      }
      if (mounted) setState(() => _mensajesNoLeidos = total);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    _searchController.dispose();
    _headerAnim.dispose();
    _solicitudesStream?.cancel();
    _mensajesStream?.cancel();
    super.dispose();
  }

  Future<void> _enviarSolicitud(String targetId) async {
    await FirebaseFirestore.instance.collection('friendships').add({
      'senderId': currentUserId,
      'receiverId': targetId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    _buscarEnTiempoReal();
  }

  void _abrirChat(String friendId, String friendNickname, String? friendFoto) {
    if (_navegandoAChat) return;
    _navegandoAChat = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          currentUserId: currentUserId,
          friendId: friendId,
          friendNickname: friendNickname,
          friendFoto: friendFoto,
        ),
      ),
    ).whenComplete(() => _navegandoAChat = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ParchmentPainter())),
          NestedScrollView(
            headerSliverBuilder: (context, _) => [_buildSliverHeader()],
            body: Column(
              children: [
                if (_searchQuery.isNotEmpty) _buildSearchResults(),
                if (_searchQuery.isEmpty)
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRankingTab(),
                        _buildFriendsList(),
                        _buildChatList(),
                        _buildRequestsList(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 3),
    );
  }

  Widget _buildSliverHeader() {
    return SliverAppBar(
      backgroundColor: _kHeader,
      floating: true,
      snap: true,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: _kHeader,
          border: Border(
            bottom: BorderSide(color: _kGold.withValues(alpha: 0.2), width: 1),
          ),
        ),
      ),
      title: FadeTransition(
        opacity: _headerAnim,
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kGold.withValues(alpha: 0.1),
              border: Border.all(color: _kGold.withValues(alpha: 0.35), width: 1),
            ),
            child: const Icon(Icons.explore_rounded, color: _kGold, size: 16),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'TERRITORIO SOCIAL',
              style: TextStyle(
                color: _kTextPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 2.5,
              ),
            ),
            Text(
              'exploradores · ligas · mensajes',
              style: TextStyle(color: _kGold.withValues(alpha: 0.7), fontSize: 9, letterSpacing: 1.5),
            ),
          ]),
        ]),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(104),
        child: Container(
          color: _kHeader,
          child: Column(children: [
            _buildSearchBar(),
            _buildTabBar(),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final bool active = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: active ? _kSurface2 : _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? _kTerracotta.withValues(alpha: 0.5) : _kBorder2,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(
              Icons.search_rounded,
              color: active ? _kTerracotta : _kGold.withValues(alpha: 0.6),
              size: 18,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: _kTextPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Buscar explorador...',
                hintStyle: TextStyle(color: _kTextDim, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
            ),
          ),
          if (_buscando)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(color: _kTerracotta, strokeWidth: 1.5),
              ),
            )
          else if (active)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.close_rounded, color: _kTextMuted, size: 16),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorColor: _kTerracotta,
      indicatorWeight: 2,
      labelColor: _kTerracotta,
      unselectedLabelColor: _kTextDim,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.5),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 1),
      dividerColor: _kBorder,
      tabs: [
        const Tab(text: 'LIGAS'),
        const Tab(text: 'ALIADOS'),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('MENSAJES'),
          if (_mensajesNoLeidos > 0) ...[
            const SizedBox(width: 4),
            _InkDot(count: _mensajesNoLeidos, color: _kTerracotta),
          ],
        ])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('SOLICITUDES'),
          if (_solicitudesPendientes > 0) ...[
            const SizedBox(width: 4),
            _InkDot(count: _solicitudesPendientes, color: _kSage),
          ],
        ])),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_resultadosBusqueda.isEmpty && !_buscando) {
      return Expanded(child: _WatercolorEmpty(
        icon: Icons.search_off_rounded,
        titulo: 'Sin exploradores',
        subtitulo: 'Nadie encontrado para "$_searchQuery"',
      ));
    }
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _resultadosBusqueda.length,
        itemBuilder: (context, i) {
          final u = _resultadosBusqueda[i];
          return _PlayerCard(
            userId: u['id'],
            nickname: u['nickname'] ?? '?',
            nivel: (u['nivel'] as num? ?? 1).toInt(),
            monedas: (u['monedas'] as num? ?? 0).toInt(),
            rango: (u['rango'] as num? ?? 0).toInt(),
            relacion: u['relacion'] as String? ?? 'ninguna',
            fotoBase64: u['foto_base64'] as String?,
            puntosLiga: (u['puntos_liga'] as num? ?? 0).toInt(),
            onAgregar: () => _enviarSolicitud(u['id']),
            onVerPerfil: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ResumenScreen(
                targetUserId: u['id'], targetNickname: u['nickname'],
                distancia: 0, tiempo: Duration.zero, ruta: const [],
              ),
            )),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RANKING TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildRankingTab() {
    final ligaInfo = LeagueHelper.getLeague(_misPuntosLiga);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder2),
          ),
          child: Row(children: [
            _ToggleBtn(
              label: 'MI LIGA', emoji: ligaInfo.emoji,
              active: _rankingModeLiga, activeColor: ligaInfo.color,
              onTap: () => setState(() { _rankingModeLiga = true; _ligaSeleccionada = null; }),
            ),
            const SizedBox(width: 3),
            _ToggleBtn(
              label: 'GLOBAL', icon: Icons.public_rounded,
              active: !_rankingModeLiga, activeColor: _kMapBlue,
              onTap: () => setState(() { _rankingModeLiga = false; _ligaSeleccionada = null; }),
            ),
          ]),
        ),
      ),

      if (_rankingModeLiga) ...[
        if (_ligaSeleccionada != null)
          _buildBotonVolverLigas()
        else
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _LeagueBannerWidget(ligaInfo: ligaInfo, puntosLiga: _misPuntosLiga),
              const SizedBox(height: 14),
              _buildTodasLasLigas(ligaInfo),
            ],
          )),
      ],

      if (_rankingModeLiga && _ligaSeleccionada != null)
        Expanded(child: _buildLeagueRankingById(_ligaSeleccionada!))
      else if (!_rankingModeLiga)
        Expanded(child: _buildGlobalRanking()),
    ]);
  }

  Widget _buildBotonVolverLigas() {
    final liga = LeagueSystem.ligas.firstWhere(
      (l) => l.id == _ligaSeleccionada, orElse: () => LeagueSystem.ligas.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: () => setState(() => _ligaSeleccionada = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder2),
          ),
          child: Row(children: [
            Icon(Icons.arrow_back_ios_rounded, color: _kTextMuted, size: 13),
            const SizedBox(width: 8),
            Text('Todas las ligas', style: TextStyle(color: _kTextMuted, fontSize: 12)),
            const Spacer(),
            Text(liga.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(liga.name, style: TextStyle(
              color: liga.color, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _buildTodasLasLigas(LeagueInfo miLiga) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(children: [
          Container(width: 16, height: 1.5, color: _kGold.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text('TODAS LAS LIGAS', style: TextStyle(
            color: _kGold.withValues(alpha: 0.7),
            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2.5)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: _kBorder2)),
        ]),
      ),
      ...LeagueSystem.ligas.map((liga) {
        final bool esMiLiga = liga.id == miLiga.id;
        final bool bloqueada = liga.minPts > _misPuntosLiga;
        return GestureDetector(
          onTap: () => setState(() => _ligaSeleccionada = liga.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: esMiLiga ? liga.color.withValues(alpha: 0.08) : _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: esMiLiga ? liga.color.withValues(alpha: 0.4) : _kBorder,
                width: esMiLiga ? 1.5 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(
                  painter: _CardTexturePainter(esMiLiga ? liga.color : _kGold),
                )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(children: [
                    Text(liga.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(liga.name.toUpperCase(), style: TextStyle(
                          color: liga.color, fontSize: 12,
                          fontWeight: FontWeight.w900, letterSpacing: 1)),
                        if (esMiLiga) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: liga.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: liga.color.withValues(alpha: 0.35)),
                            ),
                            child: Text('TÚ ESTÁS AQUÍ', style: TextStyle(
                              color: _kTextPrimary, fontSize: 7,
                              fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        liga.maxPts != null
                            ? '${liga.minPts} – ${liga.maxPts} pts'
                            : '${liga.minPts}+ pts',
                        style: TextStyle(color: _kTextDim, fontSize: 10),
                      ),
                    ])),
                    Icon(
                      bloqueada && !esMiLiga
                          ? Icons.lock_outline_rounded
                          : Icons.chevron_right_rounded,
                      color: bloqueada && !esMiLiga
                          ? _kBorder2
                          : liga.color.withValues(alpha: 0.5),
                      size: 16,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }),
    ]);
  }

  Widget _buildLeagueRankingById(String ligaId) {
    final liga = LeagueSystem.ligas.firstWhere(
      (l) => l.id == ligaId, orElse: () => LeagueSystem.ligas.first);
    return _buildLeagueRanking(liga);
  }

  Widget _buildLeagueRanking(LeagueInfo ligaInfo) {
    final int minPts = ligaInfo.minPts;
    final int maxPts = ligaInfo.maxPts ?? 999999;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('players')
          .where('puntos_liga', isGreaterThanOrEqualTo: minPts)
          .where('puntos_liga', isLessThanOrEqualTo: maxPts)
          .orderBy('puntos_liga', descending: true)
          .limit(100).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: _InkLoader());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _WatercolorEmpty(
          icon: Icons.emoji_events_outlined,
          titulo: 'Liga vacía',
          subtitulo: 'Nadie en ${ligaInfo.name} aún.\n¡Sal a conquistar territorio!',
        );
        return Column(children: [
          if (_ligaSeleccionada != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Text(ligaInfo.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('TOP 100 — ${ligaInfo.name.toUpperCase()}',
                  style: TextStyle(color: ligaInfo.color, fontSize: 11,
                    fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const Spacer(),
                Text('${docs.length} exploradores',
                  style: TextStyle(color: _kTextDim, fontSize: 10)),
              ]),
            ),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final bool esYo = docs[i].id == currentUserId;
              final int pos = i + 1;
              final int ptsLiga = (data['puntos_liga'] as num? ?? 0).toInt();
              return GestureDetector(
                onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ResumenScreen(
                    targetUserId: docs[i].id,
                    targetNickname: data['nickname'],
                    distancia: 0, tiempo: Duration.zero, ruta: const []))),
                child: _RankCard(
                  posicion: pos, nickname: data['nickname'] ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(),
                  monedas: (data['monedas'] as num? ?? 0).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  esYo: esYo, puntosLiga: ptsLiga, ligaInfo: ligaInfo,
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
      stream: FirebaseFirestore.instance
          .collection('players')
          .orderBy('puntos_liga', descending: true)
          .limit(100).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: _InkLoader());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final bool esYo = docs[i].id == currentUserId;
            final int pos = i + 1;
            final int ptsLiga = (data['puntos_liga'] as num? ?? 0).toInt();
            final ligaInfo = LeagueHelper.getLeague(ptsLiga);
            return GestureDetector(
              onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ResumenScreen(
                  targetUserId: docs[i].id,
                  targetNickname: data['nickname'],
                  distancia: 0, tiempo: Duration.zero, ruta: const []))),
              child: _RankCard(
                posicion: pos, nickname: data['nickname'] ?? '?',
                nivel: (data['nivel'] as num? ?? 1).toInt(),
                monedas: (data['monedas'] as num? ?? 0).toInt(),
                fotoBase64: data['foto_base64'] as String?,
                esYo: esYo, puntosLiga: ptsLiga, ligaInfo: ligaInfo,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendships')
          .where('status', isEqualTo: 'accepted').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: _InkLoader());
        final misAmigos = snapshot.data!.docs.where((doc) =>
          doc['senderId'] == currentUserId ||
          doc['receiverId'] == currentUserId).toList();
        if (misAmigos.isEmpty) return _WatercolorEmpty(
          icon: Icons.group_outlined,
          titulo: 'Sin aliados aún',
          subtitulo: 'Busca exploradores y únete\na su aventura cartográfica',
        );
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: misAmigos.length,
          itemBuilder: (context, i) {
            final friendId = misAmigos[i]['senderId'] == currentUserId
                ? misAmigos[i]['receiverId']
                : misAmigos[i]['senderId'];
            if (_perfilesAmigosCache.containsKey(friendId)) {
              final data = _perfilesAmigosCache[friendId]!;
              return _FriendCard(
                nickname: data['nickname'] ?? '?',
                nivel: (data['nivel'] as num? ?? 1).toInt(),
                monedas: (data['monedas'] as num? ?? 0).toInt(),
                fotoBase64: data['foto_base64'] as String?,
                onChat: () => _abrirChat(friendId, data['nickname'] ?? '?',
                    data['foto_base64'] as String?),
                onPerfil: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ResumenScreen(
                    targetUserId: friendId, targetNickname: data['nickname'],
                    distancia: 0, tiempo: Duration.zero, ruta: const []))),
              );
            }
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('players').doc(friendId).get(),
              builder: (context, s) {
                if (!s.hasData) return const _CardSkeleton();
                final data = s.data!.data() as Map<String, dynamic>;
                _perfilesAmigosCache[friendId] = data;
                return _FriendCard(
                  nickname: data['nickname'] ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(),
                  monedas: (data['monedas'] as num? ?? 0).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  onChat: () => _abrirChat(friendId, data['nickname'] ?? '?',
                      data['foto_base64'] as String?),
                  onPerfil: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ResumenScreen(
                      targetUserId: friendId, targetNickname: data['nickname'],
                      distancia: 0, tiempo: Duration.zero, ruta: const []))),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChatList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUserId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ChatErrorState(error: snapshot.error);
        if (!snapshot.hasData) return Center(child: _InkLoader());
        final chats = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final tA = (a.data() as Map)['lastMessageTime'] as Timestamp?;
            final tB = (b.data() as Map)['lastMessageTime'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });
        if (chats.isEmpty) return _WatercolorEmpty(
          icon: Icons.mail_outline_rounded,
          titulo: 'Sin mensajes aún',
          subtitulo: 'Ve a Aliados y abre un chat\ncon tus compañeros de ruta',
        );
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: chats.length,
          itemBuilder: (context, i) {
            final chatData = chats[i].data() as Map<String, dynamic>;
            final String chatId = chats[i].id;
            final List parts = chatData['participants'] as List? ?? [];
            final String friendId = parts.firstWhere(
                (p) => p != currentUserId, orElse: () => '');
            if (friendId.isEmpty) return const SizedBox.shrink();
            final int unread =
                (chatData['unread_$currentUserId'] as num? ?? 0).toInt();
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('players').doc(friendId).get(),
              builder: (context, s) {
                if (!s.hasData) return const _CardSkeleton();
                final fd = s.data!.data() as Map<String, dynamic>? ?? {};
                return _ChatPreviewCard(
                  chatId: chatId,
                  nickname: fd['nickname'] ?? '?',
                  fotoBase64: fd['foto_base64'] as String?,
                  lastMessage: chatData['lastMessage'] as String? ?? '',
                  lastTime: chatData['lastMessageTime'] as Timestamp?,
                  unread: unread,
                  onTap: () => _abrirChat(friendId, fd['nickname'] ?? '?',
                      fd['foto_base64'] as String?),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendships')
          .where('receiverId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: _InkLoader());
        final solicitudes = snapshot.data!.docs;
        if (solicitudes.isEmpty) return _WatercolorEmpty(
          icon: Icons.inbox_outlined,
          titulo: 'Sin solicitudes',
          subtitulo: 'Las invitaciones de alianza\naparecerán aquí',
        );
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: solicitudes.length,
          itemBuilder: (context, i) {
            final doc = solicitudes[i];
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('players').doc(doc['senderId']).get(),
              builder: (context, s) {
                if (!s.hasData) return const _CardSkeleton();
                final data = s.data!.data() as Map<String, dynamic>? ?? {};
                return _RequestCard(
                  nickname: data['nickname'] ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  onAceptar: () => FirebaseFirestore.instance
                      .collection('friendships')
                      .doc(doc.id).update({'status': 'accepted'}),
                  onRechazar: () => FirebaseFirestore.instance
                      .collection('friendships').doc(doc.id).delete(),
                );
              },
            );
          },
        );
      },
    );
  }
}

// =============================================================================
//  LEAGUE BANNER
// =============================================================================
class _LeagueBannerWidget extends StatelessWidget {
  final LeagueInfo ligaInfo;
  final int puntosLiga;
  const _LeagueBannerWidget({required this.ligaInfo, required this.puntosLiga});

  @override
  Widget build(BuildContext context) {
    final double progress = LeagueHelper.getProgress(puntosLiga);
    final int faltanPts = LeagueHelper.ptsParaSiguiente(puntosLiga);

    return Container(
      decoration: BoxDecoration(
        color: ligaInfo.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ligaInfo.color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          Positioned.fill(
              child: CustomPaint(painter: _CardTexturePainter(ligaInfo.color))),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ligaInfo.color.withValues(alpha: 0.1),
                  border: Border.all(
                      color: ligaInfo.color.withValues(alpha: 0.35), width: 2),
                ),
                child: Center(
                    child: Text(ligaInfo.emoji,
                        style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Text(ligaInfo.name.toUpperCase(),
                          style: TextStyle(
                              color: ligaInfo.color,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5)),
                      const SizedBox(width: 8),
                      Text('$puntosLiga pts',
                          style: TextStyle(
                              color: ligaInfo.color.withValues(alpha: 0.55),
                              fontSize: 11)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: _kBorder2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(ligaInfo.color),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      faltanPts > 0
                          ? 'Faltan $faltanPts pts para ascender'
                          : '🏆 Liga máxima',
                      style: TextStyle(color: _kTextDim, fontSize: 10),
                    ),
                  ])),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  CHAT SCREEN
// =============================================================================
class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String friendId;
  final String friendNickname;
  final String? friendFoto;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.friendId,
    required this.friendNickname,
    this.friendFoto,
  });

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
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _marcarLeido() async {
    await _chatRef
        .set({'unread_${widget.currentUserId}': 0}, SetOptions(merge: true));
  }

  Future<void> _enviarMensaje() async {
    final texto = _msgController.text.trim();
    if (texto.isEmpty) return;
    _msgController.clear();
    final now = FieldValue.serverTimestamp();
    await _messagesRef
        .add({'senderId': widget.currentUserId, 'text': texto, 'timestamp': now});
    await _chatRef.set({
      'participants': [widget.currentUserId, widget.friendId],
      'lastMessage': texto,
      'lastMessageTime': now,
      'lastSenderId': widget.currentUserId,
      'unread_${widget.currentUserId}': 0,
      'unread_${widget.friendId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kHeader,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder2),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: _kTextPrimary, size: 17),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          _InkAvatar(fotoBase64: widget.friendFoto, size: 34),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.friendNickname,
                style: TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
            Text('En ruta',
                style:
                    TextStyle(color: _kSage, fontSize: 9, letterSpacing: 1)),
          ]),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(Icons.more_horiz, color: _kTextDim, size: 20),
          ),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _ParchmentPainter())),
        Column(children: [
          Expanded(
              child: StreamBuilder<QuerySnapshot>(
            stream:
                _messagesRef.orderBy('timestamp', descending: false).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return Center(child: _InkLoader());
              final msgs = snapshot.data!.docs;
              if (msgs.length > _ultimoConteoMensajes) {
                _ultimoConteoMensajes = msgs.length;
                if (msgs.isNotEmpty) {
                  final last = msgs.last.data() as Map<String, dynamic>;
                  if (last['senderId'] != widget.currentUserId) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _marcarLeido());
                  }
                }
              }
              if (msgs.isEmpty)
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kGold.withValues(alpha: 0.08),
                      border: Border.all(
                          color: _kGold.withValues(alpha: 0.25)),
                    ),
                    child: const Text('✉️',
                        style: TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(height: 12),
                  Text('¡Saluda a ${widget.friendNickname}!',
                      style: TextStyle(color: _kTextMuted, fontSize: 13)),
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
                    texto: m['text'] ?? '',
                    esMio: esMio,
                    hora: fecha != null
                        ? '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}'
                        : '',
                  );
                },
              );
            },
          )),
          _buildInputBar(),
        ]),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _kHeader,
        border: Border(top: BorderSide(color: _kBorder2)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kBorder2),
              ),
              child: TextField(
                controller: _msgController,
                style: TextStyle(color: _kTextPrimary, fontSize: 13),
                maxLines: null,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  hintStyle: TextStyle(color: _kTextDim, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _enviarMensaje,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [_kTerracotta, _kGold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: _kTerracotta.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 1)
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 17),
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  WIDGETS REUTILIZABLES
// =============================================================================

class _ToggleBtn extends StatelessWidget {
  final String label;
  final String? emoji;
  final IconData? icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.label,
    this.emoji,
    this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active
                    ? activeColor.withValues(alpha: 0.35)
                    : Colors.transparent),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 13)),
            if (icon != null)
              Icon(icon,
                  color: active ? activeColor : _kTextDim, size: 13),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? activeColor : _kTextDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ]),
        ),
      ),
    );
  }
}

class _InkDot extends StatelessWidget {
  final int count;
  final Color color;
  const _InkDot({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(count > 9 ? '9+' : '$count',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w900)),
    );
  }
}

class _InkAvatar extends StatelessWidget {
  final String? fotoBase64;
  final double size;
  const _InkAvatar({this.fotoBase64, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kGold.withValues(alpha: 0.08),
        border: Border.all(color: _kGold.withValues(alpha: 0.35), width: 1.5),
      ),
      child: ClipOval(
        child: fotoBase64 != null
            ? Image.memory(base64Decode(fotoBase64!), fit: BoxFit.cover)
            : Icon(Icons.person_rounded,
                color: _kGold.withValues(alpha: 0.6), size: size * 0.45),
      ),
    );
  }
}

class _InkLoader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24, height: 24,
      child: CircularProgressIndicator(
        color: _kTerracotta,
        strokeWidth: 1.5,
        backgroundColor: _kBorder2,
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 64,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final String userId;
  final String nickname;
  final int nivel;
  final int monedas;
  final int rango;
  final String relacion;
  final String? fotoBase64;
  final int puntosLiga;
  final VoidCallback onAgregar;
  final VoidCallback onVerPerfil;

  const _PlayerCard({
    required this.userId, required this.nickname, required this.nivel,
    required this.monedas, required this.rango, required this.relacion,
    this.fotoBase64, required this.puntosLiga,
    required this.onAgregar, required this.onVerPerfil,
  });

  @override
  Widget build(BuildContext context) {
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    return GestureDetector(
      onTap: onVerPerfil,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            Positioned.fill(
                child: CustomPaint(painter: _CardTexturePainter(_kGold))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                _InkAvatar(fotoBase64: fotoBase64, size: 44),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Row(children: [
                    Text(nickname,
                        style: TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(width: 6),
                    _PillTag(label: 'Niv. $nivel', color: _kMapBlue),
                    const SizedBox(width: 5),
                    _PillTag(
                        label: '${ligaInfo.emoji} ${ligaInfo.name}',
                        color: ligaInfo.color),
                  ]),
                  const SizedBox(height: 3),
                  Text('$monedas 🪙  ·  Rango #$rango',
                      style: TextStyle(color: _kTextDim, fontSize: 11)),
                ])),
                const SizedBox(width: 8),
                _RelacionBtn(relacion: relacion, onAgregar: onAgregar),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PillTag extends StatelessWidget {
  final String label;
  final Color color;
  const _PillTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

class _RelacionBtn extends StatelessWidget {
  final String relacion;
  final VoidCallback onAgregar;
  const _RelacionBtn({required this.relacion, required this.onAgregar});

  @override
  Widget build(BuildContext context) {
    if (relacion == 'accepted') {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _kSage.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kSage.withValues(alpha: 0.4)),
        ),
        child: Text('Aliado',
            style: TextStyle(
                color: _kSage,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
    }
    if (relacion == 'pending') {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _kGold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kGold.withValues(alpha: 0.3)),
        ),
        child: Text('Pendiente',
            style: TextStyle(
                color: _kGold,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
    }
    return GestureDetector(
      onTap: onAgregar,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient:
              LinearGradient(colors: [_kTerracotta, _kGold]),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: _kTerracotta.withValues(alpha: 0.25),
                blurRadius: 6)
          ],
        ),
        child: const Text('+ Unirse',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  final int posicion;
  final String nickname;
  final int nivel;
  final int monedas;
  final String? fotoBase64;
  final bool esYo;
  final int puntosLiga;
  final LeagueInfo ligaInfo;

  const _RankCard({
    required this.posicion, required this.nickname, required this.nivel,
    required this.monedas, this.fotoBase64, required this.esYo,
    required this.puntosLiga, required this.ligaInfo,
  });

  @override
  Widget build(BuildContext context) {
    Color posColor;
    if (posicion == 1) posColor = const Color(0xFFFFD700);
    else if (posicion == 2) posColor = const Color(0xFFC0C0C0);
    else if (posicion == 3) posColor = const Color(0xFFCD7F32);
    else posColor = _kTextDim;

    final bool top3 = posicion <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: esYo
            ? _kTerracotta.withValues(alpha: 0.08)
            : top3
                ? posColor.withValues(alpha: 0.05)
                : _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: esYo
              ? _kTerracotta.withValues(alpha: 0.35)
              : top3
                  ? posColor.withValues(alpha: 0.25)
                  : _kBorder,
          width: esYo || top3 ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(
              painter: _CardTexturePainter(
                  esYo ? _kTerracotta : _kGold))),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              SizedBox(
                width: 36,
                child: Text(
                  top3 ? ['🥇', '🥈', '🥉'][posicion - 1] : '#$posicion',
                  style: TextStyle(
                      color: posColor,
                      fontWeight: FontWeight.w900,
                      fontSize: top3 ? 18 : 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              _InkAvatar(fotoBase64: fotoBase64, size: 34),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text(
                  nickname + (esYo ? ' (Tú)' : ''),
                  style: TextStyle(
                      color: esYo ? _kTerracotta : _kTextPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Text('Niv. $nivel',
                      style: TextStyle(color: _kTextDim, fontSize: 10)),
                  const SizedBox(width: 8),
                  _PillTag(
                      label: '${ligaInfo.emoji} ${ligaInfo.name}',
                      color: ligaInfo.color),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$puntosLiga',
                    style: TextStyle(
                        color: ligaInfo.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
                Text('pts',
                    style: TextStyle(
                        color: ligaInfo.color.withValues(alpha: 0.5),
                        fontSize: 9)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final String nickname;
  final int nivel;
  final int monedas;
  final String? fotoBase64;
  final VoidCallback onChat;
  final VoidCallback onPerfil;

  const _FriendCard({
    required this.nickname, required this.nivel, required this.monedas,
    this.fotoBase64, required this.onChat, required this.onPerfil,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Positioned.fill(
              child: CustomPaint(painter: _CardTexturePainter(_kGold))),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              _InkAvatar(fotoBase64: fotoBase64, size: 40),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text(nickname,
                    style: TextStyle(
                        color: _kTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text('Nivel $nivel · $monedas 🪙',
                    style: TextStyle(color: _kTextDim, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: onPerfil,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: _kGold.withValues(alpha: 0.25)),
                  ),
                  child: Icon(Icons.map_outlined, color: _kGold, size: 15),
                ),
              ),
              const SizedBox(width: 7),
              GestureDetector(
                onTap: onChat,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_kTerracotta, _kGold.withValues(alpha: 0.8)]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: _kTerracotta.withValues(alpha: 0.2),
                          blurRadius: 6)
                    ],
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white, size: 15),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ChatPreviewCard extends StatelessWidget {
  final String chatId;
  final String nickname;
  final String? fotoBase64;
  final String lastMessage;
  final Timestamp? lastTime;
  final int unread;
  final VoidCallback onTap;

  const _ChatPreviewCard({
    required this.chatId, required this.nickname, this.fotoBase64,
    required this.lastMessage, this.lastTime,
    required this.unread, required this.onTap,
  });

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final now = DateTime.now();
    final dif = now.difference(d);
    if (dif.inDays == 0)
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (dif.inDays == 1) return 'Ayer';
    if (dif.inDays < 7) return '${dif.inDays}d';
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final bool hayNoLeidos = unread > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: hayNoLeidos
              ? _kTerracotta.withValues(alpha: 0.06)
              : _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hayNoLeidos
                ? _kTerracotta.withValues(alpha: 0.3)
                : _kBorder,
            width: hayNoLeidos ? 1.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(
                painter: _CardTexturePainter(
                    hayNoLeidos ? _kTerracotta : _kGold))),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                _InkAvatar(fotoBase64: fotoBase64, size: 42),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text(nickname,
                      style: TextStyle(
                          color: _kTextPrimary,
                          fontWeight: hayNoLeidos
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    lastMessage.isEmpty
                        ? 'Inicia la conversación'
                        : lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: hayNoLeidos
                            ? _kTextMuted
                            : _kTextDim,
                        fontSize: 11),
                  ),
                ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_formatTime(lastTime),
                      style: TextStyle(
                          color: hayNoLeidos ? _kTerracotta : _kTextDim,
                          fontSize: 10)),
                  const SizedBox(height: 4),
                  if (hayNoLeidos)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: _kTerracotta,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900)),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String nickname;
  final int nivel;
  final String? fotoBase64;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;

  const _RequestCard({
    required this.nickname, required this.nivel, this.fotoBase64,
    required this.onAceptar, required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Positioned.fill(
              child: CustomPaint(painter: _CardTexturePainter(_kGold))),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _InkAvatar(fotoBase64: fotoBase64, size: 44),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text(nickname,
                    style: TextStyle(
                        color: _kTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text('Explorador · Nivel $nivel',
                    style: TextStyle(color: _kTextDim, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: onRechazar,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.redAccent, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAceptar,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_kSage, _kSage.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: _kSage.withValues(alpha: 0.3),
                          blurRadius: 8)
                    ],
                  ),
                  child: const Text('Aceptar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BubbleMensaje extends StatelessWidget {
  final String texto;
  final bool esMio;
  final String hora;
  const _BubbleMensaje(
      {required this.texto, required this.esMio, required this.hora});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: 7, left: esMio ? 56 : 0, right: esMio ? 0 : 56),
      child: Align(
        alignment:
            esMio ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: esMio
                ? LinearGradient(
                    colors: [_kTerracotta, _kGold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                : null,
            color: esMio ? null : _kSurface2,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(esMio ? 16 : 4),
              bottomRight: Radius.circular(esMio ? 4 : 16),
            ),
            border: esMio
                ? null
                : Border.all(color: _kBorder2),
            boxShadow: [
              BoxShadow(
                  color: (esMio ? _kTerracotta : Colors.black)
                      .withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: esMio
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(texto,
                  style: TextStyle(
                      color: esMio ? Colors.white : _kTextPrimary,
                      fontSize: 13)),
              const SizedBox(height: 3),
              Text(hora,
                  style: TextStyle(
                      color: esMio
                          ? Colors.white.withValues(alpha: 0.55)
                          : _kTextDim,
                      fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatErrorState extends StatelessWidget {
  final Object? error;
  const _ChatErrorState({this.error});

  @override
  Widget build(BuildContext context) {
    final String detalle = error?.toString() ?? 'Error desconocido';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kTerracotta.withValues(alpha: 0.07),
              border: Border.all(
                  color: _kTerracotta.withValues(alpha: 0.25),
                  width: 1.5),
            ),
            child: Icon(Icons.wifi_off_rounded,
                color: _kTerracotta.withValues(alpha: 0.5), size: 30),
          ),
          const SizedBox(height: 14),
          Text('Error de conexión',
              style: TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Text(
              'No se pudieron cargar los mensajes.\nComprueba tu conexión e inténtalo de nuevo.',
              style: TextStyle(color: _kTextMuted, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kTerracotta.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _kTerracotta.withValues(alpha: 0.2)),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Icon(Icons.info_outline_rounded,
                  color: _kTerracotta.withValues(alpha: 0.5), size: 13),
              const SizedBox(width: 8),
              Expanded(
                child: Text(detalle,
                    style: TextStyle(
                        color: _kTerracotta.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontFamily: 'monospace'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _WatercolorEmpty extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  const _WatercolorEmpty(
      {required this.icon,
      required this.titulo,
      required this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kGold.withValues(alpha: 0.07),
            border: Border.all(
                color: _kGold.withValues(alpha: 0.2), width: 1.5),
          ),
          child: Icon(icon,
              color: _kGold.withValues(alpha: 0.45), size: 30),
        ),
        const SizedBox(height: 14),
        Text(titulo,
            style: TextStyle(
                color: _kTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        const SizedBox(height: 6),
        Text(subtitulo,
            style: TextStyle(color: _kTextMuted, fontSize: 12),
            textAlign: TextAlign.center),
      ]),
    );
  }
}