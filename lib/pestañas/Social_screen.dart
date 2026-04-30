import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:RiskRunner/pesta%C3%B1as/clan_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'perfil_screen.dart';
import '../widgets/custom_navbar.dart';
import '../services/league_service.dart';

// =============================================================================
//  PALETA — fija (accent + tiers) + adaptativa (bg / text / surface)
// =============================================================================
// Fijos — no cambian entre temas
const Color _kAccent     = Color(0xFFE02020);
const Color _kAccentGlow = Color(0x33E02020);
const Color _kGreen      = Color(0xFF1A4A35);
const Color _kGreenFg    = Color(0xFF3DBF82);
const Color _kGold       = Color(0xFFFFD700);
const Color _kSilver2    = Color(0xFFC0C0C0);
const Color _kBronze2    = Color(0xFFCD7F32);
const Color _kBronze     = Color(0xFFCD7F32);
const Color _kSilver     = Color(0xFFA8C0D4);
const Color _kGoldTier   = Color(0xFFF0CC40);
const Color _kPlatinum   = Color(0xFF6CA8E0);
const Color _kDiamond    = Color(0xFF70E0F8);

// Paleta adaptativa dark / light
class _SP {
  final Color bg, surface, surface2, surface3;
  final Color line, line2, dim, subtext, text3, text2, text1;
  const _SP._({
    required this.bg,       required this.surface,
    required this.surface2, required this.surface3,
    required this.line,     required this.line2,
    required this.dim,      required this.subtext,
    required this.text3,    required this.text2,
    required this.text1,
  });
  static const light = _SP._(
    bg:       Color(0xFFE8E8ED),
    surface:  Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA),
    surface3: Color(0xFFF2F2F7),
    line:     Color(0xFFC6C6C8),
    line2:    Color(0xFFD1D1D6),
    dim:      Color(0xFFAEAEB2),
    subtext:  Color(0xFF8E8E93),
    text3:    Color(0xFF636366),
    text2:    Color(0xFF3C3C43),
    text1:    Color(0xFF1C1C1E),
  );
  static const dark = _SP._(
    bg:       Color(0xFF090807),
    surface:  Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    surface3: Color(0xFF38383A),
    line:     Color(0xFF38383A),
    line2:    Color(0xFF2C2C2E),
    dim:      Color(0xFF636366),
    subtext:  Color(0xFF8E8E93),
    text3:    Color(0xFF8E8E93),
    text2:    Color(0xFFD1D1D6),
    text1:    Color(0xFFEEEEEE),
  );
  static _SP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

// Compat getters – widgets que usan _kXxx directamente los resolverán vía _SP.of(context)
// (las constantes de texto/superficie se eliminaron; usar _SP.of(ctx).xxx en su lugar)

// =============================================================================
//  SHIMMER
// =============================================================================
class _Shimmer extends StatefulWidget {
  final double width, height, borderRadius;
  const _Shimmer({required this.width, required this.height, this.borderRadius = 4});
  @override State<_Shimmer> createState() => _ShimmerState();
}
class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0), end: Alignment(_anim.value, 0),
            colors: [_p.surface, _p.surface2, const Color(0xFF1E1E28), _p.surface2, _p.surface],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0]))));
  }
}

// =============================================================================
//  PULSE BADGE
// =============================================================================
class _PulseBadge extends StatefulWidget {
  final int count; final Color color;
  const _PulseBadge({required this.count, required this.color});
  @override State<_PulseBadge> createState() => _PulseBadgeState();
}
class _PulseBadgeState extends State<_PulseBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => ScaleTransition(
    scale: _scale,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(3)),
      child: Text(widget.count > 9 ? '9+' : '${widget.count}',
        style: TextStyle(
          color: widget.color.computeLuminance() > 0.4 ? Colors.black : Colors.white,
          fontSize: 8, fontWeight: FontWeight.w900))));
}

// =============================================================================
//  STAGGER ITEM
// =============================================================================
class _Stagger extends StatefulWidget {
  final Widget child; final int index;
  const _Stagger({required this.child, required this.index});
  @override State<_Stagger> createState() => _StaggerState();
}
class _StaggerState extends State<_Stagger> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  @override void initState() {
    super.initState();
    final delay = math.min(widget.index * 60, 400);
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _opacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: delay), () { if (mounted) _ctrl.forward(); });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => FadeTransition(
    opacity: _opacity, child: SlideTransition(position: _slide, child: widget.child));
}

// =============================================================================
//  PRESS SCALE
// =============================================================================
class _Press extends StatefulWidget {
  final Widget child; final VoidCallback? onTap;
  const _Press({required this.child, this.onTap});
  @override State<_Press> createState() => _PressState();
}
class _PressState extends State<_Press> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
    onTapCancel: () => _ctrl.reverse(),
    child: ScaleTransition(scale: _scale, child: widget.child));
}

// =============================================================================
//  AVATAR
// =============================================================================
class _Avatar extends StatelessWidget {
  final String? fotoBase64;
  final String? nickname;
  final double size;
  final Color? ringColor;
  final bool glow;
  const _Avatar({this.fotoBase64, this.nickname, this.size = 40, this.ringColor, this.glow = false});

  static Color _colorFromNick(String nick) {
    if (nick.isEmpty) return const Color(0xFF2A2A35);
    int hash = 0;
    for (final c in nick.codeUnits) hash = (hash * 31 + c) & 0xFFFFFFFF;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.26).toColor();
  }

  static Color _fgFromBg(Color bg) =>
      HSLColor.fromColor(bg).withLightness(0.78).toColor();

  @override
  Widget build(BuildContext ctx) {
    final p = _SP.of(ctx);
    final ring = ringColor ?? p.line2;
    final String nick = nickname ?? '';
    final String initials = nick.isNotEmpty
        ? nick.substring(0, math.min(2, nick.length)).toUpperCase() : '?';
    final Color bgColor = _colorFromNick(nick);
    final Color fgColor = _fgFromBg(bgColor);

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: p.surface3, shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
        boxShadow: glow ? [BoxShadow(color: ring.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)] : null),
      child: ClipOval(child: fotoBase64 != null
        ? Image.memory(base64Decode(fotoBase64!), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _Initials(initials: initials, bg: bgColor, fg: fgColor, size: size))
        : _Initials(initials: initials, bg: bgColor, fg: fgColor, size: size)));
  }
}

class _Initials extends StatelessWidget {
  final String initials; final Color bg, fg; final double size;
  const _Initials({required this.initials, required this.bg, required this.fg, required this.size});
  @override Widget build(BuildContext ctx) => Container(
    width: size, height: size, color: bg,
    alignment: Alignment.center,
    child: Text(initials, style: TextStyle(
      color: fg, fontSize: size * 0.33,
      fontWeight: FontWeight.w800, letterSpacing: 0.5, height: 1)));
}

// =============================================================================
//  PILL TAG
// =============================================================================
class _Pill extends StatelessWidget {
  final String label; final Color color; final Widget? leading;
  const _Pill({required this.label, required this.color, this.leading});
  @override Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(4)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (leading != null) ...[
        leading!,
        const SizedBox(width: 3),
      ],
      Text(label, style: TextStyle(
        color: color.withValues(alpha: 0.9),
        fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))]));
}

// =============================================================================
//  SKELETON
// =============================================================================
class _Skel extends StatelessWidget {
  final double height;
  const _Skel({this.height = 68});
  @override Widget build(BuildContext ctx) {
    final p = _SP.of(ctx);
    return Container(
    height: height, margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.line2)),
    clipBehavior: Clip.hardEdge,
    child: Row(children: [
      _Shimmer(width: 58, height: height),
      const SizedBox(width: 14),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Shimmer(width: 110, height: 12), const SizedBox(height: 8), _Shimmer(width: 75, height: 9)])),
      _Shimmer(width: 56, height: 30, borderRadius: 6),
      const SizedBox(width: 14)]));
  }
}

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

  Color _accent = _kAccent;
  _SP get _p => _SP.of(context);
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
  bool _rankingModeLiga = true;
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
      final c   = (data['territorio_color'] as num?)?.toInt();
      final pts = (data['puntos_liga'] as num? ?? 0).toInt();
      final info = LeagueHelper.getLeague(pts);
      setState(() {
        if (c != null) _accent = Color(c);
        _misPuntosLiga = pts;
        _miLiga = info.name;
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
          .where('nickname', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get();
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
      final rankSnap = await FirebaseFirestore.instance
          .collection('players')
          .where('monedas', isGreaterThan: monedas)
          .count()
          .get();
      final int rango = ((rankSnap.count as num?)?.toInt() ?? 0) + 1;

      // Buscar relación: enviadas por mí hacia ese usuario
      String relacion = 'ninguna';
      final sentSnap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('senderId', isEqualTo: currentUserId)
          .where('receiverId', isEqualTo: doc.id)
          .limit(1)
          .get();
      if (sentSnap.docs.isNotEmpty) {
        relacion = sentSnap.docs.first.data()['status'] ?? 'ninguna';
      } else {
        // Buscar relación: enviadas por ese usuario hacia mí
        final recvSnap = await FirebaseFirestore.instance
            .collection('friendships')
            .where('senderId', isEqualTo: doc.id)
            .where('receiverId', isEqualTo: currentUserId)
            .limit(1)
            .get();
        if (recvSnap.docs.isNotEmpty) {
          relacion = recvSnap.docs.first.data()['status'] ?? 'ninguna';
        }
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
        side: BorderSide(color: error ? _kAccent.withValues(alpha: 0.5) : _kGreenFg.withValues(alpha: 0.5))),
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
        physics: const PageScrollPhysics(), // ← permite deslizar suavemente
        children: [
          _buildRankingTab(),
          _buildFriendsList(),
          _buildChatList(),
          _buildRequestsList(),
          const ClanScreen(),
        ])),
    ]),
    bottomNavigationBar: const CustomBottomNavbar(currentIndex: 3),
  );

  // ══════════════════════════════ HEADER ════════════════════════════════════════
  Widget _buildHeader() {
    final p = _SP.of(context);
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
    final p = _SP.of(context);
    final bool active = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), height: 44,
        decoration: BoxDecoration(
          color: active ? p.surface2 : p.surface,
          border: Border.all(color: active ? _kAccent.withValues(alpha: 0.5) : p.line2, width: active ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [const BoxShadow(color: _kAccentGlow, blurRadius: 12)] : null),
        child: Row(children: [
          Padding(padding: const EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded, color: active ? _kAccent : p.dim, size: 16)),
          Expanded(child: TextField(
            controller: _searchController,
            style: TextStyle(color: p.text1, fontSize: 13, letterSpacing: 0.3),
            decoration: InputDecoration(
              hintText: 'Buscar...', hintStyle: TextStyle(color: p.dim, fontSize: 13),
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)))),
          if (_buscando)
            Padding(padding: const EdgeInsets.only(right: 14),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5)))
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
    final p = _SP.of(context);
    return TabBar(
    controller: _tabController,
    indicatorColor: _kAccent, indicatorWeight: 2, indicatorSize: TabBarIndicatorSize.tab,
    labelColor: p.text1, unselectedLabelColor: p.subtext,
    labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 2),
    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 9, letterSpacing: 1.5),
    dividerColor: Colors.transparent,
    tabs: [
      const Tab(icon: Icon(Icons.emoji_events_rounded, size: 13), text: 'LIGAS', iconMargin: EdgeInsets.only(bottom: 2)),
      const Tab(icon: Icon(Icons.person_2_rounded, size: 13), text: 'AMIGOS', iconMargin: EdgeInsets.only(bottom: 2)),
      Tab(
        iconMargin: const EdgeInsets.only(bottom: 2),
        icon: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.chat_bubble_rounded, size: 13),
          if (_mensajesNoLeidos > 0) ...[const SizedBox(width: 3), _PulseBadge(count: _mensajesNoLeidos, color: _kAccent)],
        ]),
        text: 'CHAT',
      ),
      Tab(
        iconMargin: const EdgeInsets.only(bottom: 2),
        icon: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.person_add_rounded, size: 13),
          if (_solicitudesPendientes > 0) ...[const SizedBox(width: 3), _PulseBadge(count: _solicitudesPendientes, color: _kAccent)],
        ]),
        text: 'SOLICITUDES',
      ),
      const Tab(icon: Icon(Icons.shield_rounded, size: 13), text: 'CLAN', iconMargin: EdgeInsets.only(bottom: 2)),
    ]);
  }

  // ══════════════════════════ SEARCH RESULTS ════════════════════════════════════
  Widget _buildSearchResults() {
    if (_errorBusqueda) return _ErrorState(onRetry: () { setState(() { _buscando = true; _errorBusqueda = false; }); _buscar(); });
    if (_resultadosBusqueda.isEmpty && !_buscando) return _EmptyState(
      icon: Icons.search_off_rounded, titulo: 'Sin resultados',
      subtitulo: 'Nadie con nickname "$_searchQuery"',
      accionLabel: 'Limpiar', onAccion: () => _searchController.clear());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), itemCount: _resultadosBusqueda.length,
      itemBuilder: (ctx, i) {
        final u = _resultadosBusqueda[i];
        final bool yaEnviada = _solicitudesEnviadas.contains(u['id']);
        final String rel = yaEnviada ? 'pending' : (u['relacion'] as String? ?? 'ninguna');
        return _Stagger(index: i, child: _PlayerCard(
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

  // ═══════════════════════════ RANKING TAB ══════════════════════════════════════
  Widget _buildRankingTab() {
    final ligaInfo = LeagueHelper.getLeague(_misPuntosLiga);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Container(
          height: 40,
          decoration: BoxDecoration(color: _p.surface, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            _ToggleBtn(label: 'LIGAS', icon: ligaInfo.icon, active: _rankingModeLiga, activeColor: _kAccent,
              onTap: () => setState(() { _rankingModeLiga = true; _ligaSeleccionada = null; })),
            Container(width: 1, height: 22, color: _p.line2),
            _ToggleBtn(label: 'GLOBAL', icon: Icons.public_rounded, active: !_rankingModeLiga, activeColor: _kAccent,
              onTap: () => setState(() { _rankingModeLiga = false; _ligaSeleccionada = null; })),
          ]))),
      if (_rankingModeLiga) ...[
        if (_ligaSeleccionada != null) _buildBotonVolver(),
        Expanded(child: RefreshIndicator(
          key: _rkRanking, color: _kAccent, backgroundColor: _p.surface2,
          onRefresh: () async { await _cargarDatosPropios(); },
          child: _ligaSeleccionada != null
              ? _buildLeagueRankingById(_ligaSeleccionada!)
              : ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 32), children: [
                  _LeagueBanner(ligaInfo: ligaInfo, puntosLiga: _misPuntosLiga, accent: _accent),
                  const SizedBox(height: 20),
                  _buildTodasLasLigas(ligaInfo),
                ])))]
      else
        Expanded(child: RefreshIndicator(
          key: _rkRanking, color: _kAccent, backgroundColor: _p.surface2,
          onRefresh: () async { setState(() {}); },
          child: _buildGlobalRanking())),
    ]);
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
    final List<Color> tierColors = [_kBronze, _kSilver, _kGoldTier, _kPlatinum, _kDiamond];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(children: [
          Container(width: 16, height: 1, color: _kAccent.withValues(alpha: 0.6)),
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
        return _Stagger(index: idx, child: _Press(
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
                                color: _kAccent, borderRadius: BorderRadius.circular(4),
                                boxShadow: [BoxShadow(color: _kAccentGlow, blurRadius: 6)]),
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
        if (snapshot.hasError) return _ErrorState(onRetry: () => setState(() {}));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _EmptyState(icon: Icons.emoji_events_outlined, titulo: 'Liga vacía', subtitulo: 'Nadie en ${ligaInfo.name} aún');
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
              return _Stagger(index: i, child: GestureDetector(
                onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PerfilScreen(targetUserId: docs[i].id))),
                child: _RankCard(posicion: i + 1, nickname: data['nickname'] ?? '?',
                  nivel: (data['nivel'] as num? ?? 1).toInt(), monedas: (data['monedas'] as num? ?? 0).toInt(),
                  fotoBase64: data['foto_base64'] as String?, esYo: esYo,
                  puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), ligaInfo: ligaInfo, accent: _accent)));
            })),
        ]);
      });
  }

  Widget _buildGlobalRanking() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('players').orderBy('puntos_liga', descending: true).limit(100).snapshots(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) return _buildRankSkels();
        if (snapshot.hasError) return _ErrorState(onRetry: () => setState(() {}));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const _EmptyState(icon: Icons.public_rounded, titulo: 'Sin jugadores aún', subtitulo: 'Sé el primero en conquistar territorio');
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32), itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final bool esYo = docs[i].id == currentUserId;
            final int ptsLiga = (data['puntos_liga'] as num? ?? 0).toInt();
            return _Stagger(index: i, child: GestureDetector(
              onTap: esYo ? null : () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PerfilScreen(targetUserId: docs[i].id))),
              child: _RankCard(posicion: i + 1, nickname: data['nickname'] ?? '?',
                nivel: (data['nivel'] as num? ?? 1).toInt(), monedas: (data['monedas'] as num? ?? 0).toInt(),
                fotoBase64: data['foto_base64'] as String?, esYo: esYo, puntosLiga: ptsLiga,
                ligaInfo: LeagueHelper.getLeague(ptsLiga), accent: _accent)));
          });
      });
  }

  Widget _buildRankSkels() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), itemCount: 7,
    itemBuilder: (_, i) => _Skel(height: i < 3 ? 82 : 64));

  // ════════════════════════ AMIGOS TAB — FIX ═════════════════════════════════════
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
              return _ErrorState(onRetry: () { _perfilesCache.clear(); setState(() {}); });

            final amigos = [...sentSnap.data!.docs, ...recvSnap.data!.docs];

            if (amigos.isEmpty) return _EmptyState(
              icon: Icons.group_outlined,
              titulo: 'Sin aliados aún',
              subtitulo: 'Busca exploradores y forma\ntu equipo cartográfico',
              accionLabel: 'Buscar exploradores',
              onAccion: () => _searchController.clear());

            return RefreshIndicator(
              key: _rkAliados, color: _kAccent, backgroundColor: _p.surface2,
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
                    return _Stagger(index: i, child: _buildFriendCard(_perfilesCache[fid]!, fid));
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('players').doc(fid).get(),
                    builder: (ctx, s) {
                      if (!s.hasData) return const _Skel();
                      final data = s.data!.data() as Map<String, dynamic>? ?? {};
                      _perfilesCache[fid] = data;
                      return _Stagger(index: i, child: _buildFriendCard(data, fid));
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
    return _FriendCard(
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
        if (snapshot.hasError) return _ChatErrorState(error: snapshot.error);
        if (!snapshot.hasData) return _genSkels();
        final chats = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final tA = (a.data() as Map)['lastMessageTime'] as Timestamp?;
            final tB = (b.data() as Map)['lastMessageTime'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1; if (tB == null) return -1;
            return tB.compareTo(tA);
          });
        if (chats.isEmpty) return const _EmptyState(icon: Icons.forum_outlined, titulo: 'Sin mensajes aún', subtitulo: 'Ve a Aliados y abre un chat\ncon tus compañeros de ruta');
        return RefreshIndicator(
          key: _rkMensajes, color: _kAccent, backgroundColor: _p.surface2,
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
                return _Stagger(index: i, child: _ChatCard(
                  chatId: chatId, nickname: fd['nickname'] ?? '?', fotoBase64: fd['foto_base64'] as String?,
                  lastMessage: chatData['lastMessage'] as String? ?? '',
                  lastTime: chatData['lastMessageTime'] as Timestamp?,
                  unread: unread, accent: _accent,
                  onTap: () => _abrirChat(fid, fd['nickname'] ?? '?', fd['foto_base64'] as String?)));
              }
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(fid).get(),
                builder: (ctx, s) {
                  if (!s.hasData) return const _Skel();
                  final fd = s.data!.data() as Map<String, dynamic>? ?? {};
                  _perfilesCache[fid] = fd;
                  return _Stagger(index: i, child: _ChatCard(
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
        if (snapshot.hasError) return _ErrorState(onRetry: () => setState(() {}));
        final solicitudes = snapshot.data!.docs;
        if (solicitudes.isEmpty) return const _EmptyState(icon: Icons.inbox_outlined, titulo: 'Sin solicitudes', subtitulo: 'Las invitaciones de alianza\naparecerán aquí');
        return RefreshIndicator(
          key: _rkSolici, color: _kAccent, backgroundColor: _p.surface2,
          onRefresh: () async { setState(() {}); },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            itemCount: solicitudes.length,
            itemBuilder: (ctx, i) {
              final doc = solicitudes[i];
              final String senderId = doc['senderId'] as String;
              if (_perfilesCache.containsKey(senderId)) {
                final data = _perfilesCache[senderId]!;
                return _Stagger(index: i, child: _RequestCard(
                  nickname: data['nickname'] ?? '?', nivel: (data['nivel'] as num? ?? 1).toInt(),
                  fotoBase64: data['foto_base64'] as String?,
                  puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), accent: _accent,
                  onAceptar: () async {
                    await FirebaseFirestore.instance.collection('friendships').doc(doc.id).update({'status': 'accepted'});
                    _snack('¡${data['nickname']} ahora es tu aliado!');
                  },
                  onRechazar: () => _confirmarRechazo(context, doc.id, data['nickname'] ?? '?')));
              }
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('players').doc(senderId).get(),
                builder: (ctx, s) {
                  if (!s.hasData) return const _Skel();
                  final data = s.data!.data() as Map<String, dynamic>? ?? {};
                  _perfilesCache[senderId] = data;
                  return _Stagger(index: i, child: _RequestCard(
                    nickname: data['nickname'] ?? '?', nivel: (data['nivel'] as num? ?? 1).toInt(),
                    fotoBase64: data['foto_base64'] as String?,
                    puntosLiga: (data['puntos_liga'] as num? ?? 0).toInt(), accent: _accent,
                    onAceptar: () async {
                      await FirebaseFirestore.instance.collection('friendships').doc(doc.id).update({'status': 'accepted'});
                      _snack('¡${data['nickname']} ahora es tu aliado!');
                    },
                    onRechazar: () => _confirmarRechazo(context, doc.id, data['nickname'] ?? '?')));
                });
            }));
      });
  }

  void _confirmarRechazo(BuildContext ctx, String docId, String nickname) {
    final p = _SP.of(ctx);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: p.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line2)),
      title: Text('Rechazar solicitud', style: TextStyle(color: p.text1, fontSize: 14, fontWeight: FontWeight.w800)),
      content: Text('¿Rechazar la solicitud de $nickname?', style: TextStyle(color: p.text2, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: p.text2))),
        TextButton(onPressed: () { Navigator.pop(ctx); FirebaseFirestore.instance.collection('friendships').doc(docId).delete(); },
          child: const Text('Rechazar', style: TextStyle(color: _kAccent))),
      ]));
  }

  Widget _genSkels() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), itemCount: 6, itemBuilder: (_, __) => const _Skel());
}

// =============================================================================
//  LEAGUE BANNER
// =============================================================================
class _LeagueBanner extends StatelessWidget {
  final LeagueInfo ligaInfo; final int puntosLiga; final Color accent;
  const _LeagueBanner({required this.ligaInfo, required this.puntosLiga, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = _SP.of(context);
    final double progress = LeagueHelper.getProgress(puntosLiga);
    final int faltanPts = LeagueHelper.ptsParaSiguiente(puntosLiga);
    const int segs = 12;
    final int filled = (progress * segs).floor().clamp(0, segs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: p.surface, border: Border.all(color: ligaInfo.color.withValues(alpha: 0.25), width: 1.5),
            borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                color: ligaInfo.color.withValues(alpha: 0.05),
                border: Border(bottom: BorderSide(color: p.line2))),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: ligaInfo.color.withValues(alpha: 0.08),
                    border: Border.all(color: ligaInfo.color.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Icon(ligaInfo.icon, color: ligaInfo.color, size: 28))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    const Text('TEMPORADA ACTIVA',
                      style: TextStyle(color: _kAccent, fontSize: 8, letterSpacing: 2.5, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Text(ligaInfo.name.toUpperCase(),
                    style: TextStyle(
                      color: ligaInfo.color, fontSize: 22,
                      fontWeight: FontWeight.w900, letterSpacing: 1.5,
                      shadows: [Shadow(color: ligaInfo.color.withValues(alpha: 0.4), blurRadius: 12)])),
                  const SizedBox(height: 2),
                  Text('LIGA ACTUAL', style: TextStyle(color: p.subtext, fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w600)),
                ])),
              ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$puntosLiga',
                    style: TextStyle(color: p.text1, fontSize: 56, fontWeight: FontWeight.w900, height: 0.9, letterSpacing: -3)),
                  Padding(padding: const EdgeInsets.only(bottom: 8, left: 6),
                    child: Text('PTS', style: TextStyle(color: p.subtext, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2))),
                  const Spacer(),
                  if (faltanPts > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: p.surface3, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('$faltanPts', style: TextStyle(color: p.text1, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        Text('PARA ASCENDER', style: TextStyle(color: p.subtext, fontSize: 7, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                      ])),
                ]),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('PROGRESO', style: TextStyle(color: p.subtext, fontSize: 8, letterSpacing: 3, fontWeight: FontWeight.w700)),
                  Text('${(progress * 100).toInt()}%',
                    style: TextStyle(color: ligaInfo.color, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Row(children: List.generate(segs, (i) {
                  final bool active = i < filled;
                  final bool current = i == filled && progress < 1.0;
                  return Expanded(child: Container(
                    margin: EdgeInsets.only(right: i < segs - 1 ? 3 : 0), height: 5,
                    decoration: BoxDecoration(
                      color: active ? ligaInfo.color.withValues(alpha: 0.75) : current ? ligaInfo.color : p.line2,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: (active || current) ? [BoxShadow(color: ligaInfo.color.withValues(alpha: 0.3), blurRadius: 4)] : null)));
                })),
                const SizedBox(height: 10),
                Text(faltanPts > 0 ? 'Faltan $faltanPts pts para la siguiente liga' : ' Liga máxima alcanzada',
                  style: TextStyle(color: p.text3, fontSize: 10)),
              ])),
          ])),
        Positioned(left: 0, top: 0, bottom: 0,
          child: Container(width: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [ligaInfo.color, ligaInfo.color.withValues(alpha: 0.2)]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14))))),
      ]));
  }
}

// =============================================================================
//  RANK CARD
// =============================================================================
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

  @override
  Widget build(BuildContext ctx) {
    final p = _SP.of(ctx);
    final Color medal = posicion == 1 ? _kGold : posicion == 2 ? _kSilver2 : posicion == 3 ? _kBronze2 : p.line2;
    final bool top3 = posicion <= 3;
    final bool dest = esYo || top3;
    final Color bar = esYo ? _kAccent : (top3 ? medal : p.line2);
    final double aSize = top3 ? 42.0 : 35.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: top3 ? 14 : 10),
            decoration: BoxDecoration(
              color: top3 ? p.surface2 : esYo ? _kAccent.withValues(alpha: 0.06) : p.surface,
              border: Border.all(color: top3 ? medal.withValues(alpha: 0.2) : esYo ? _kAccent.withValues(alpha: 0.3) : p.line2),
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 38, child: top3
                ? Text(['','',''][posicion-1], style: TextStyle(fontSize: posicion==1?26:22), textAlign: TextAlign.center)
                : Text('#$posicion', style: TextStyle(color: esYo ? _kAccent : p.text3, fontWeight: FontWeight.w900, fontSize: 12), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              _Avatar(fotoBase64: fotoBase64, nickname: nickname, size: aSize,
                ringColor: top3 ? medal.withValues(alpha: 0.5) : esYo ? _kAccent.withValues(alpha: 0.6) : ligaInfo.color.withValues(alpha: 0.35),
                glow: top3 || esYo),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname + (esYo ? ' (Tú)' : ''),
                  style: TextStyle(color: p.text1, fontWeight: top3 ? FontWeight.w900 : FontWeight.w600, fontSize: top3 ? 14 : 13),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text('Niv. $nivel', style: TextStyle(color: p.subtext, fontSize: 10)),
                  const SizedBox(width: 6),
                  _Pill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$puntosLiga',
                  style: TextStyle(color: top3 ? medal : esYo ? _kAccent : p.text2,
                    fontWeight: FontWeight.w900, fontSize: top3 ? 20 : 15, letterSpacing: -0.5)),
                Text('pts', style: TextStyle(color: p.dim, fontSize: 9)),
              ]),
            ])),
          if (dest)
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(
                width: top3 ? 3 : 2,
                decoration: BoxDecoration(
                  color: bar,
                  boxShadow: top3 ? [BoxShadow(color: bar.withValues(alpha: 0.5), blurRadius: 8)] : null,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))))),
        ])));
  }
}

// =============================================================================
//  FRIEND CARD
// =============================================================================
class _FriendCard extends StatelessWidget {
  final String nickname; final int nivel, monedas, puntosLiga;
  final String? fotoBase64; final Color accent, territorioColor;
  final bool activo;
  final VoidCallback onChat, onPerfil;
  const _FriendCard({required this.nickname, required this.nivel, required this.monedas,
    required this.puntosLiga, this.fotoBase64, required this.accent,
    required this.territorioColor, required this.activo,
    required this.onChat, required this.onPerfil});

  @override
  Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    final Color tc = territorioColor == _p.line2 ? _p.dim : territorioColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            decoration: BoxDecoration(
              color: _p.surface,
              border: Border.all(color: _p.line2),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Stack(alignment: Alignment.bottomRight, children: [
                _Avatar(fotoBase64: fotoBase64, nickname: nickname, size: 46,
                  ringColor: tc.withValues(alpha: 0.55)),
                Container(
                  width: 11, height: 11,
                  decoration: BoxDecoration(
                    color: _p.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: _p.bg, width: 1.5)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: activo ? _kGreenFg : _p.dim,
                      shape: BoxShape.circle)),
                ),
              ]),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname, style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    activo ? 'ACTIVO' : 'INACTIVO',
                    style: TextStyle(
                      color: activo ? _kGreenFg.withValues(alpha: 0.7) : _p.dim,
                      fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  Container(width: 1, height: 8, color: _p.line2,
                    margin: const EdgeInsets.symmetric(horizontal: 6)),
                  _Pill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
                ]),
              ])),
              _Press(onTap: onPerfil, child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _p.surface3,
                  border: Border.all(color: _p.line2),
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.person_outline_rounded, color: _p.text3, size: 15))),
              const SizedBox(width: 6),
              _Press(onTap: onChat, child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _kAccent, borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: _kAccentGlow, blurRadius: 10)]),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 15))),
            ])),
          Positioned(left: 0, top: 0, bottom: 0,
            child: Container(width: 3,
              decoration: BoxDecoration(
                color: tc.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
        ])));
  }
}

// =============================================================================
//  CHAT CARD
// =============================================================================
class _ChatCard extends StatelessWidget {
  final String chatId, nickname; final String? fotoBase64;
  final String lastMessage; final Timestamp? lastTime;
  final int unread; final Color accent; final VoidCallback onTap;
  const _ChatCard({required this.chatId, required this.nickname, this.fotoBase64,
    required this.lastMessage, this.lastTime, required this.unread, required this.accent, required this.onTap});

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate(); final now = DateTime.now(); final dif = now.difference(d);
    if (dif.inDays == 0) return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    if (dif.inDays == 1) return 'Ayer';
    if (dif.inDays < 7) return '${dif.inDays}d';
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    final bool h = unread > 0;
    return _Press(onTap: onTap, child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: h ? _p.surface2 : _p.surface,
              border: Border.all(color: h ? _kAccent.withValues(alpha: 0.3) : _p.line2),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              _Avatar(fotoBase64: fotoBase64, nickname: nickname, size: 46,
                ringColor: h ? _kAccent.withValues(alpha: 0.5) : _p.line2, glow: h),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname, style: TextStyle(color: h ? _p.text1 : _p.text2,
                  fontWeight: h ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                const SizedBox(height: 4),
                Text(lastMessage.isEmpty ? 'Inicia la conversación' : lastMessage,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: h ? _p.text3 : _p.subtext, fontSize: 12, fontStyle: FontStyle.italic)),
              ])),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_fmt(lastTime), style: TextStyle(color: h ? _kAccent.withValues(alpha: 0.8) : _p.dim,
                  fontSize: 10, fontWeight: h ? FontWeight.w600 : FontWeight.w400)),
                if (h) ...[const SizedBox(height: 6), _PulseBadge(count: unread, color: _kAccent)],
              ]),
            ])),
          if (h) Positioned(left: 0, top: 0, bottom: 0,
            child: Container(width: 3, decoration: BoxDecoration(
              color: _kAccent,
              boxShadow: [BoxShadow(color: _kAccentGlow, blurRadius: 8)],
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
        ]))));
  }
}

// =============================================================================
//  PLAYER CARD
// =============================================================================
class _PlayerCard extends StatefulWidget {
  final String userId, nickname, relacion, currentUserId;
  final int nivel, monedas, rango, puntosLiga;
  final String? fotoBase64;
  final Color accent;
  final VoidCallback onAgregar, onVerPerfil;
  const _PlayerCard({
    required this.userId, required this.nickname, required this.nivel,
    required this.monedas, required this.rango, required this.relacion,
    this.fotoBase64, required this.puntosLiga, required this.accent,
    required this.onAgregar, required this.onVerPerfil,
    required this.currentUserId,
  });
  @override State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  bool _siguiendo = false;
  bool _loadingFollow = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('follows')
          .where('followerId',  isEqualTo: widget.currentUserId)
          .where('followingId', isEqualTo: widget.userId)
          .limit(1).get();
      if (mounted) setState(() => _siguiendo = snap.docs.isNotEmpty);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    setState(() => _loadingFollow = true);
    try {
      if (_siguiendo) {
        final snap = await FirebaseFirestore.instance.collection('follows')
            .where('followerId',  isEqualTo: widget.currentUserId)
            .where('followingId', isEqualTo: widget.userId)
            .limit(1).get();
        for (final d in snap.docs) await d.reference.delete();
        if (mounted) setState(() => _siguiendo = false);
      } else {
        await FirebaseFirestore.instance.collection('follows').add({
          'followerId':  widget.currentUserId,
          'followingId': widget.userId,
          'timestamp':   FieldValue.serverTimestamp(),
        });
        final myDoc = await FirebaseFirestore.instance
            .collection('players').doc(widget.currentUserId).get();
        final nick = myDoc.data()?['nickname'] as String? ?? 'Runner';
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUserId':     widget.userId,
          'type':         'follow',
          'fromUserId':   widget.currentUserId,
          'fromNickname': nick,
          'message':      'ha empezado a seguirte',
          'read':         false,
          'timestamp':    FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() => _siguiendo = true);
      }
    } catch (e) {
      debugPrint('Error follow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          backgroundColor: Colors.redAccent.withValues(alpha: 0.95),
          content: const Row(children: [
            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
            SizedBox(width: 10),
            Text('No se pudo completar la acción',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        ));
      }
    }
    finally { if (mounted) setState(() => _loadingFollow = false); }
  }

  @override
  Widget build(BuildContext ctx) {
    final p = _SP.of(ctx);
    final ligaInfo = LeagueHelper.getLeague(widget.puntosLiga);
    return _Press(onTap: widget.onVerPerfil, child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        _Avatar(fotoBase64: widget.fotoBase64, nickname: widget.nickname, size: 44, ringColor: ligaInfo.color.withValues(alpha: 0.5)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.nickname, style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 5),
          Row(children: [
            _Pill(label: 'NIV.${widget.nivel}', color: widget.accent),
            const SizedBox(width: 5),
            _Pill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
          ]),
          const SizedBox(height: 4),
          Text('${widget.monedas}   ·  Rango #${widget.rango}', style: TextStyle(color: p.subtext, fontSize: 10)),
        ])),
        const SizedBox(width: 8),
        // Botón seguir
        _Press(
          onTap: _loadingFollow ? null : _toggleFollow,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _siguiendo ? p.surface3 : _kAccent.withValues(alpha: 0.10),
              border: Border.all(color: _siguiendo ? p.line2 : _kAccent.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _loadingFollow
                ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: _kAccent))
                : Text(_siguiendo ? 'SIGUIENDO' : 'SEGUIR',
                    style: TextStyle(
                      color: _siguiendo ? p.subtext : _kAccent,
                      fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
        ),
        const SizedBox(width: 6),
        _RelBtn(relacion: widget.relacion, accent: widget.accent, onAgregar: widget.onAgregar),
      ])));
  }
}

class _RelBtn extends StatelessWidget {
  final String relacion; final Color accent; final VoidCallback onAgregar;
  const _RelBtn({required this.relacion, required this.accent, required this.onAgregar});
  @override Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    if (relacion == 'accepted') return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.3), border: Border.all(color: _kGreenFg.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(6)),
      child: const Text('ALIADO', style: TextStyle(color: _kGreenFg, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)));
    if (relacion == 'pending') return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: _p.surface3, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(6)),
      child: Text('PENDIENTE', style: TextStyle(color: _p.subtext, fontSize: 9, fontWeight: FontWeight.w700)));
    return _Press(onTap: onAgregar, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: _kAccentGlow, blurRadius: 8)]),
      child: const Text('+ UNIRSE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5))));
  }
}

// =============================================================================
//  REQUEST CARD
// =============================================================================
class _RequestCard extends StatelessWidget {
  final String nickname; final int nivel, puntosLiga;
  final String? fotoBase64; final Color accent; final VoidCallback onAceptar, onRechazar;
  const _RequestCard({required this.nickname, required this.nivel, this.fotoBase64,
    required this.puntosLiga, required this.accent, required this.onAceptar, required this.onRechazar});

  @override
  Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(color: _p.surface, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        _Avatar(fotoBase64: fotoBase64, nickname: nickname, size: 44, ringColor: ligaInfo.color.withValues(alpha: 0.5)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nickname, style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 5),
          Row(children: [
            Text('Nivel $nivel', style: TextStyle(color: _p.text3, fontSize: 11)),
            const SizedBox(width: 6),
            _Pill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
          ]),
        ])),
        _Press(onTap: onRechazar, child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: _p.surface3, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.close_rounded, color: _p.text3, size: 16))),
        const SizedBox(width: 8),
        _Press(onTap: onAceptar, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: _kAccentGlow, blurRadius: 10)]),
          child: const Text('ACEPTAR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)))),
      ]));
  }
}

// =============================================================================
//  TOGGLE BUTTON
// =============================================================================
class _ToggleBtn extends StatelessWidget {
  final String label; final IconData? icon;
  final bool active; final Color activeColor; final VoidCallback onTap;
  const _ToggleBtn({required this.label, this.icon, required this.active, required this.activeColor, required this.onTap});
  @override Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: active ? activeColor.withValues(alpha: 0.08) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) Icon(icon, color: active ? activeColor : _p.subtext, size: 13),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: active ? activeColor : _p.subtext, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ]))));
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
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  _SP get _p => _SP.of(context);
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final String _chatId;
  late final CollectionReference _msgsRef;
  late final DocumentReference _chatRef;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    final sorted = [widget.currentUserId, widget.friendId]..sort();
    _chatId = sorted.join('_');
    _chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    _msgsRef = _chatRef.collection('messages');
    _marcarLeido();
  }
  @override void dispose() { _msgCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _marcarLeido() async =>
    _chatRef.set({'unread_${widget.currentUserId}': 0}, SetOptions(merge: true));

  Future<void> _send() async {
    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;
    _msgCtrl.clear();
    final now = FieldValue.serverTimestamp();
    await _msgsRef.add({'senderId': widget.currentUserId, 'text': texto, 'timestamp': now});
    await _chatRef.set({
      'participants': [widget.currentUserId, widget.friendId],
      'lastMessage': texto, 'lastMessageTime': now,
      'lastSenderId': widget.currentUserId,
      'unread_${widget.currentUserId}': 0,
      'unread_${widget.friendId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      backgroundColor: const Color(0xFF0D0D0D), elevation: 0, surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: _kAccent)),
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 16), onPressed: () => Navigator.pop(context)),
      title: Row(children: [
        _Avatar(fotoBase64: widget.friendFoto, nickname: widget.friendNickname, size: 34),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.friendNickname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
          Row(children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kGreenFg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            const Text('EN LÍNEA', style: TextStyle(color: _kGreenFg, fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ]),
      actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Icon(Icons.more_horiz, color: _p.dim, size: 20))]),
    body: Column(children: [
      Expanded(child: StreamBuilder<QuerySnapshot>(
        stream: _msgsRef.orderBy('timestamp', descending: false).snapshots(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) return Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _p.dim, strokeWidth: 1.5)));
          final msgs = snapshot.data!.docs;
          if (msgs.length > _count) {
            _count = msgs.length;
            if (msgs.isNotEmpty) {
              final last = msgs.last.data() as Map<String, dynamic>;
              if (last['senderId'] != widget.currentUserId)
                WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLeido());
            }
          }
          if (msgs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 56, height: 56,
              decoration: BoxDecoration(color: _p.surface3, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.chat_bubble_outline_rounded, color: _p.dim, size: 22)),
            const SizedBox(height: 14),
            Text('¡Saluda a ${widget.friendNickname}!',
              style: TextStyle(color: _p.subtext, fontSize: 13, fontStyle: FontStyle.italic)),
          ]));
          return ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            itemCount: msgs.length,
            itemBuilder: (ctx, i) {
              final m = msgs[i].data() as Map<String, dynamic>;
              final bool esMio = m['senderId'] == widget.currentUserId;
              final Timestamp? ts = m['timestamp'] as Timestamp?;
              final DateTime? d = ts?.toDate();
              return _Bubble(texto: m['text'] ?? '', esMio: esMio,
                hora: d != null ? '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}' : '');
            });
        })),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(color: _p.bg, border: Border(top: BorderSide(color: _p.line))),
        child: SafeArea(top: false, child: Row(children: [
          Expanded(child: Container(
            decoration: BoxDecoration(color: _p.surface, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(10)),
            child: TextField(controller: _msgCtrl,
              style: TextStyle(color: _p.text1, fontSize: 13),
              maxLines: null, textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...', hintStyle: TextStyle(color: _p.dim, fontSize: 13),
                border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11))))),
          const SizedBox(width: 8),
          _Press(onTap: _send, child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: _kAccentGlow, blurRadius: 10)]),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 17))),
        ]))),
    ]));
}

// =============================================================================
//  BUBBLE
// =============================================================================
class _Bubble extends StatelessWidget {
  final String texto, hora; final bool esMio;
  const _Bubble({required this.texto, required this.esMio, required this.hora});
  @override Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: esMio ? 60 : 0, right: esMio ? 0 : 60),
      child: Align(
        alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: esMio ? _p.text1 : _p.surface3,
            border: esMio ? null : Border.all(color: _p.line2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(esMio ? 14 : 3), bottomRight: Radius.circular(esMio ? 3 : 14))),
          child: Column(
            crossAxisAlignment: esMio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(texto, style: TextStyle(color: esMio ? _p.bg : _p.text1, fontSize: 13)),
              const SizedBox(height: 4),
              Text(hora, style: TextStyle(color: esMio ? _p.bg.withValues(alpha: 0.4) : _p.subtext, fontSize: 9)),
            ]))));
  }
}

// =============================================================================
//  ESTADOS
// =============================================================================
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
        decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.05),
          border: Border.all(color: _kAccent.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(14)),
        child: Icon(Icons.wifi_off_rounded, color: _kAccent.withValues(alpha: 0.5), size: 24)),
      const SizedBox(height: 16),
      Text('Error de conexión', style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      Text('No se pudo cargar la información', style: TextStyle(color: _p.text2, fontSize: 12, fontStyle: FontStyle.italic)),
      const SizedBox(height: 20),
      _Press(onTap: onRetry, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(color: _p.surface3, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.refresh_rounded, color: _p.text2, size: 14), const SizedBox(width: 7),
          Text('Reintentar', style: TextStyle(color: _p.text2, fontSize: 12, fontWeight: FontWeight.w700)),
        ]))),
    ]));
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon; final String titulo, subtitulo;
  final String? accionLabel; final VoidCallback? onAccion;
  const _EmptyState({required this.icon, required this.titulo, required this.subtitulo, this.accionLabel, this.onAccion});
  @override
  Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: _p.surface2,
                border: Border.all(color: _p.line2),
                borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: _p.dim, size: 24)),
            const SizedBox(height: 16),
            Text(titulo, style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            Text(subtitulo,
              style: TextStyle(color: _p.text2, fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center),
            if (accionLabel != null && onAccion != null) ...[
              const SizedBox(height: 20),
              _Press(
                onTap: onAccion,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: _p.surface3,
                    border: Border.all(color: _p.line2),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(accionLabel!,
                    style: TextStyle(color: _p.text2, fontSize: 12, fontWeight: FontWeight.w700)))),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatErrorState extends StatelessWidget {
  final Object? error;
  const _ChatErrorState({this.error});
  @override Widget build(BuildContext ctx) {
    final _SP _p = _SP.of(ctx);
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 60, height: 60,
          decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.04),
            border: Border.all(color: _kAccent.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.wifi_off_rounded, color: _kAccent.withValues(alpha: 0.5), size: 26)),
        const SizedBox(height: 16),
        Text('Error de conexión', style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        Text('No se pudieron cargar los mensajes.', style: TextStyle(color: _p.text2, fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _p.surface, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: _p.dim, size: 12), const SizedBox(width: 8),
            Expanded(child: Text(error?.toString() ?? 'Error desconocido',
              style: TextStyle(color: _p.subtext, fontSize: 10), maxLines: 3, overflow: TextOverflow.ellipsis)),
          ])),
      ])));
  }
}