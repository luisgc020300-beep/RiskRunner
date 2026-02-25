import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../Widgets/custom_navbar.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen>
    with TickerProviderStateMixin {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  final TextEditingController _nicknameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // Datos básicos
  String nickname = '';
  String email = '';
  int monedas = 0;
  int nivel = 1;
  int territorios = 0;
  String? fotoBase64;
  bool isLoading = true;
  bool isSaving = false;
  bool isUploadingPhoto = false;

  // Estadísticas de carrera acumuladas
  double _kmTotales = 0;
  double _velocidadMediaHistorica = 0;
  int _totalCarreras = 0;
  int _territoriosConquistados = 0;
  Duration _tiempoTotalActividad = Duration.zero;

  // Logros completados hoy
  List<Map<String, dynamic>> _logros = [];

  // Historial de carreras recientes
  List<Map<String, dynamic>> _carrerasRecientes = [];

  // Color de territorio
  Color _colorTerritorio = Colors.orange;
  static const List<Color> _coloresDisponibles = [
    Colors.orange,
    Colors.red,
    Color(0xFF00E5FF),   // cyan
    Color(0xFF76FF03),   // verde lima
    Colors.purple,
    Colors.pink,
    Color(0xFFFFD600),   // amarillo
    Colors.white,
  ];

  // Rango global
  int _rangoGlobal = 0;

  // Animaciones
  late AnimationController _headerAnim;
  late AnimationController _contentAnim;
  late Animation<double> _headerFade;
  late Animation<double> _contentSlide;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _contentAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _contentSlide = CurvedAnimation(parent: _contentAnim, curve: Curves.easeOutCubic);
    _cargarTodo();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _headerAnim.dispose();
    _contentAnim.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    if (userId == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _cargarPerfil(),
        _cargarEstadisticas(),
        _cargarLogros(),
        _cargarCarrerasRecientes(),
        _cargarRangoGlobal(),
      ]);
    } catch (e) {
      debugPrint("Error cargando perfil: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _headerAnim.forward();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _contentAnim.forward();
        });
      }
    }
  }

  Future<void> _cargarPerfil() async {
    final doc = await FirebaseFirestore.instance.collection('players').doc(userId).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data()!;

    final territoriosSnap = await FirebaseFirestore.instance
        .collection('territories')
        .where('userId', isEqualTo: userId)
        .get();

    final colorInt = (data['territorio_color'] as num?)?.toInt();

    setState(() {
      nickname = data['nickname'] ?? '';
      email = data['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '';
      monedas = data['monedas'] ?? 0;
      nivel = data['nivel'] ?? 1;
      territorios = territoriosSnap.docs.length;
      fotoBase64 = data['foto_base64'] as String?;
      _nicknameController.text = nickname;
      if (colorInt != null) _colorTerritorio = Color(colorInt);
    });
  }

  Future<void> _cargarEstadisticas() async {
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .get();

      double kmTotal = 0;
      double sumVelocidades = 0;
      int countVelocidades = 0;
      int totalSeg = 0;
      int conquistas = 0;

      for (final doc in logsSnap.docs) {
        final d = doc.data();
        final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
        final seg = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
        kmTotal += dist;
        totalSeg += seg;
        if (dist > 0 && seg > 0) {
          sumVelocidades += dist / (seg / 3600);
          countVelocidades++;
        }
        if (d['id_reto_completado'] != null) conquistas++;
      }

      // Territorios conquistados desde notifications
      final conqSnap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: userId)
          .where('type', isEqualTo: 'territory_conquered')
          .get();

      setState(() {
        _kmTotales = kmTotal;
        _velocidadMediaHistorica = countVelocidades > 0 ? sumVelocidades / countVelocidades : 0;
        _totalCarreras = logsSnap.docs.length;
        _tiempoTotalActividad = Duration(seconds: totalSeg);
        _territoriosConquistados = conqSnap.docs.length;
      });
    } catch (e) {
      debugPrint("Error stats: $e");
    }
  }

  Future<void> _cargarLogros() async {
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .where('id_reto_completado', isNull: false)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      setState(() {
        _logros = logsSnap.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .where((d) => d['titulo'] != null)
            .toList();
      });
    } catch (e) {
      debugPrint("Error logros: $e");
    }
  }

  Future<void> _cargarCarrerasRecientes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .where('distancia', isGreaterThan: 0)
          .orderBy('distancia')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      setState(() {
        _carrerasRecientes = snap.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .toList()
            .reversed
            .toList();
      });
    } catch (e) {
      // Fallback sin ordenación compuesta
      try {
        final snap2 = await FirebaseFirestore.instance
            .collection('activity_logs')
            .where('userId', isEqualTo: userId)
            .orderBy('timestamp', descending: true)
            .limit(5)
            .get();
        setState(() {
          _carrerasRecientes = snap2.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _cargarRangoGlobal() async {
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('players').doc(userId).get();
      if (!myDoc.exists) return;
      final myMonedas = myDoc.data()?['monedas'] ?? 0;
      final rankQ = await FirebaseFirestore.instance
          .collection('players')
          .where('monedas', isGreaterThan: myMonedas)
          .count()
          .get();
      setState(() => _rangoGlobal = (rankQ.count ?? 0) + 1);
    } catch (e) {
      debugPrint("Error rango: $e");
    }
  }

  // ── Selección foto ─────────────────────────────────────────────────────────
  Future<void> _seleccionarFoto() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Foto de perfil',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _BotonFoto(icon: Icons.camera_alt, label: 'Cámara',
                  onTap: () { Navigator.pop(context); _tomarFoto(ImageSource.camera); })),
              const SizedBox(width: 16),
              Expanded(child: _BotonFoto(icon: Icons.photo_library, label: 'Galería',
                  onTap: () { Navigator.pop(context); _tomarFoto(ImageSource.gallery); })),
            ]),
            if (fotoBase64 != null) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () { Navigator.pop(context); _eliminarFoto(); },
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    label: const Text('Eliminar foto', style: TextStyle(color: Colors.redAccent)),
                  )),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final XFile? imagen = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (imagen == null) return;
      setState(() => isUploadingPhoto = true);
      Uint8List? bytes;
      if (kIsWeb) {
        bytes = await imagen.readAsBytes();
      } else {
        bytes = await FlutterImageCompress.compressWithFile(
          imagen.path, minWidth: 256, minHeight: 256, quality: 70, format: CompressFormat.jpeg,
        );
      }
      if (bytes == null) { setState(() => isUploadingPhoto = false); return; }
      final String base64String = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('players').doc(userId).update({'foto_base64': base64String});
      if (mounted) {
        setState(() { fotoBase64 = base64String; isUploadingPhoto = false; });
        _mostrarSnackbar('¡Foto actualizada!');
      }
    } catch (e) {
      if (mounted) { setState(() => isUploadingPhoto = false); _mostrarSnackbar('Error al subir la foto', error: true); }
    }
  }

  Future<void> _eliminarFoto() async {
    try {
      await FirebaseFirestore.instance.collection('players').doc(userId)
          .update({'foto_base64': FieldValue.delete()});
      if (mounted) { setState(() => fotoBase64 = null); _mostrarSnackbar('Foto eliminada'); }
    } catch (_) { _mostrarSnackbar('Error al eliminar la foto', error: true); }
  }

  // ── Guardar nickname ───────────────────────────────────────────────────────
  Future<void> _guardarNickname() async {
    final nuevoNickname = _nicknameController.text.trim();
    if (nuevoNickname.isEmpty) { _mostrarSnackbar('El nickname no puede estar vacío', error: true); return; }
    if (nuevoNickname == nickname) { _mostrarSnackbar('El nickname no ha cambiado'); return; }
    if (nuevoNickname.length < 3) { _mostrarSnackbar('Mínimo 3 caracteres', error: true); return; }
    setState(() => isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('players').doc(userId)
          .update({'nickname': nuevoNickname});
      if (mounted) { setState(() { nickname = nuevoNickname; isSaving = false; }); _mostrarSnackbar('¡Nickname actualizado!'); }
    } catch (_) {
      if (mounted) { setState(() => isSaving = false); _mostrarSnackbar('Error al guardar', error: true); }
    }
  }

  // ── Guardar color de territorio ────────────────────────────────────────────
  Future<void> _guardarColorTerritorio(Color color) async {
    setState(() => _colorTerritorio = color);
    try {
      await FirebaseFirestore.instance.collection('players').doc(userId)
          .update({'territorio_color': color.value});
      _mostrarSnackbar('¡Color de territorio actualizado!');
    } catch (_) {
      _mostrarSnackbar('Error al guardar el color', error: true);
    }
  }

  void _mostrarSnackbar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: error ? Colors.redAccent : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _mostrarDialogoEditarNickname() {
    _nicknameController.text = nickname;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Editar nickname',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Se actualizará en toda la app',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: _nicknameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              maxLength: 20,
              decoration: InputDecoration(
                hintText: 'Tu nickname...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.person, color: Colors.orange),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                counterStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.orange.withValues(alpha: 0.6)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () { Navigator.pop(context); _guardarNickname(); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatTiempo(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  String _formatFechaCorta(dynamic ts) {
    if (ts == null) return '--';
    DateTime dt;
    if (ts is Timestamp) dt = ts.toDate();
    else return '--';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  String _nivelTitulo(int n) {
    if (n >= 50) return 'LEYENDA';
    if (n >= 30) return 'ÉLITE';
    if (n >= 20) return 'VETERANO';
    if (n >= 10) return 'EXPLORADOR';
    return 'ROOKIE';
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _cargarTodo,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.orange),
            onSelected: (v) async {
              if (v == 'logout') {
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, color: Colors.redAccent, size: 20),
                  SizedBox(width: 10),
                  Text('Cerrar sesión', style: TextStyle(color: Colors.white54)),
                ])),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── HERO HEADER ─────────────────────────────────────────
                  FadeTransition(
                    opacity: _headerFade,
                    child: _buildHeroHeader(screenH),
                  ),

                  // ── CONTENIDO ───────────────────────────────────────────
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(_contentSlide),
                    child: FadeTransition(
                      opacity: _contentSlide,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            _buildStatsGrid(),
                            const SizedBox(height: 28),
                            _buildCarreraStats(),
                            const SizedBox(height: 28),
                            _buildSelectorColor(),
                            const SizedBox(height: 28),
                            _buildCarrerasRecientes(),
                            const SizedBox(height: 28),
                            _buildLogros(),
                            const SizedBox(height: 28),
                            _buildAcciones(),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 4),
    );
  }

  // ── HERO HEADER ─────────────────────────────────────────────────────────────
  Widget _buildHeroHeader(double screenH) {
    return SizedBox(
      height: screenH * 0.42,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo con gradiente y patrón
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black,
                  _colorTerritorio.withValues(alpha: 0.25),
                  Colors.black,
                ],
              ),
            ),
          ),

          // Líneas decorativas tipo grid
          CustomPaint(painter: _GridPainter(color: _colorTerritorio)),

          // Gradiente de fade abajo
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.transparent, Colors.black],
                  stops: [0, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // Contenido del header
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rango
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _colorTerritorio.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _colorTerritorio.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.military_tech_rounded, color: _colorTerritorio, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _rangoGlobal > 0 ? 'RANGO #$_rangoGlobal · ${_nivelTitulo(nivel)}' : _nivelTitulo(nivel),
                        style: TextStyle(color: _colorTerritorio, fontSize: 11,
                            fontWeight: FontWeight.w800, letterSpacing: 1.5),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  // Avatar + nombre
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar
                      GestureDetector(
                        onTap: _seleccionarFoto,
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                                border: Border.all(color: _colorTerritorio, width: 2.5),
                                boxShadow: [
                                  BoxShadow(color: _colorTerritorio.withValues(alpha: 0.5),
                                      blurRadius: 20, spreadRadius: 2),
                                ],
                              ),
                              child: isUploadingPhoto
                                  ? const Center(child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2))
                                  : ClipOval(
                                      child: fotoBase64 != null
                                          ? Image.memory(base64Decode(fotoBase64!),
                                              fit: BoxFit.cover, width: 80, height: 80)
                                          : Icon(Icons.person, color: _colorTerritorio, size: 44),
                                    ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: _colorTerritorio,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.black, size: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),

                      // Nombre y nivel
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _mostrarDialogoEditarNickname,
                              child: Row(children: [
                                Flexible(
                                  child: Text(
                                    nickname.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.edit, color: Colors.white38, size: 14),
                              ]),
                            ),
                            const SizedBox(height: 6),
                            Text(email,
                                style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _colorTerritorio,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('NIV. $nivel',
                                    style: const TextStyle(color: Colors.black, fontSize: 11,
                                        fontWeight: FontWeight.w900, letterSpacing: 1)),
                              ),
                              const SizedBox(width: 8),
                              Text('$monedas 🪙',
                                  style: TextStyle(color: _colorTerritorio.withValues(alpha: 0.9),
                                      fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STATS GRID ──────────────────────────────────────────────────────────────
  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ESTADÍSTICAS', Icons.bar_chart_rounded),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildBigStat('$territorios', 'Territorios', Icons.flag_rounded, _colorTerritorio)),
          const SizedBox(width: 12),
          Expanded(child: _buildBigStat('$_territoriosConquistados', 'Conquistados', Icons.emoji_events_rounded, Colors.amber)),
          const SizedBox(width: 12),
          Expanded(child: _buildBigStat('#$_rangoGlobal', 'Ranking', Icons.leaderboard_rounded, Colors.lightBlueAccent)),
        ]),
      ],
    );
  }

  Widget _buildBigStat(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900,
            shadows: [Shadow(color: color.withValues(alpha: 0.4), blurRadius: 8)])),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10,
            fontWeight: FontWeight.w600, letterSpacing: 0.5), textAlign: TextAlign.center),
      ]),
    );
  }

  // ── ESTADÍSTICAS DE CARRERA ─────────────────────────────────────────────────
  Widget _buildCarreraStats() {
    final String tiempoStr = _formatTiempo(_tiempoTotalActividad);
    final String velStr = _velocidadMediaHistorica > 0
        ? '${_velocidadMediaHistorica.toStringAsFixed(1)} km/h'
        : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ACTIVIDAD TOTAL', Icons.directions_run_rounded),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _colorTerritorio.withValues(alpha: 0.15)),
          ),
          child: Column(children: [
            // Fila principal KM
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_kmTotales.toStringAsFixed(1),
                      style: TextStyle(color: _colorTerritorio, fontSize: 42,
                          fontWeight: FontWeight.w900, height: 1,
                          shadows: [Shadow(color: _colorTerritorio.withValues(alpha: 0.4), blurRadius: 10)])),
                  Text('KM TOTALES', style: const TextStyle(color: Colors.white38,
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _miniStatRow(Icons.speed_outlined, 'Vel. media', velStr, Colors.purpleAccent),
                const SizedBox(height: 10),
                _miniStatRow(Icons.timer_outlined, 'Tiempo total', tiempoStr, Colors.lightBlueAccent),
                const SizedBox(height: 10),
                _miniStatRow(Icons.map_outlined, 'Carreras', '$_totalCarreras', Colors.greenAccent),
              ]),
            ]),

            // Barra de progreso decorativa
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_kmTotales % 100) / 100,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(_colorTerritorio),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Siguiente hito: ${((_kmTotales ~/ 100) + 1) * 100} km',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
              Text('${((_kmTotales % 100)).toStringAsFixed(1)} / 100 km',
                  style: TextStyle(color: _colorTerritorio.withValues(alpha: 0.7), fontSize: 10)),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _miniStatRow(IconData icon, String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
    ]);
  }

  // ── SELECTOR COLOR TERRITORIO ───────────────────────────────────────────────
  Widget _buildSelectorColor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('COLOR DE TERRITORIO', Icons.palette_outlined),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _colorTerritorio.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _colorTerritorio,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: _colorTerritorio.withValues(alpha: 0.5), blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Color actual', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('Tus territorios en el mapa',
                      style: TextStyle(color: _colorTerritorio, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _coloresDisponibles.map((color) {
                  final bool isSelected = _colorTerritorio.value == color.value;
                  return GestureDetector(
                    onTap: () => _guardarColorTerritorio(color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10, spreadRadius: 2)]
                            : [],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.black, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── CARRERAS RECIENTES ──────────────────────────────────────────────────────
  Widget _buildCarrerasRecientes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('CARRERAS RECIENTES', Icons.history_rounded),
        const SizedBox(height: 12),
        if (_carrerasRecientes.isEmpty)
          _emptyState('Aún no has hecho ninguna carrera', Icons.directions_run_outlined)
        else
          Column(
            children: _carrerasRecientes.asMap().entries.map((entry) {
              final d = entry.value;
              final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
              final seg = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
              final vel = dist > 0 && seg > 0 ? dist / (seg / 3600) : 0.0;
              final ts = d['timestamp'];
              final fecha = _formatFechaCorta(ts);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _colorTerritorio.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _colorTerritorio.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.directions_run_rounded, color: _colorTerritorio, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${dist.toStringAsFixed(2)} km',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('${_formatTiempo(Duration(seconds: seg))}  ·  ${vel.toStringAsFixed(1)} km/h',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ])),
                  Text(fecha, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── LOGROS ──────────────────────────────────────────────────────────────────
  Widget _buildLogros() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('LOGROS', Icons.emoji_events_outlined),
        const SizedBox(height: 12),
        if (_logros.isEmpty)
          _emptyState('Completa misiones para ganar logros', Icons.emoji_events_outlined)
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _logros.map((logro) {
              final titulo = logro['titulo'] as String? ?? 'Logro';
              final recompensa = logro['recompensa'] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('+$recompensa 🪙', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                  ]),
                ]),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── ACCIONES ────────────────────────────────────────────────────────────────
  Widget _buildAcciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('OPCIONES', Icons.settings_outlined),
        const SizedBox(height: 12),
        _accionTile(
          icon: Icons.bar_chart_rounded,
          label: 'Ver mis estadísticas completas',
          color: _colorTerritorio,
          onTap: () => Navigator.pushNamed(context, '/resumen'),
        ),
        const SizedBox(height: 8),
        _accionTile(
          icon: Icons.logout_rounded,
          label: 'Cerrar sesión',
          color: Colors.redAccent,
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
          },
        ),
      ],
    );
  }

  Widget _accionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
          Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 20),
        ]),
      ),
    );
  }

  // ── HELPERS UI ───────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: _colorTerritorio, size: 18),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2)),
    ]);
  }

  Widget _emptyState(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(icon, color: Colors.white24, size: 16),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white38, fontSize: 13)),
      ]),
    );
  }
}

// ── CustomPainter para grid decorativo del header ────────────────────────────
class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Círculos de acento
    final paintCircle = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.3), 80, paintCircle);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.3), 120, paintCircle);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────
class _BotonFoto extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BotonFoto({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Icon(icon, color: Colors.orange, size: 28),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ),
    );
  }
}