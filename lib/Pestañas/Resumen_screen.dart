import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../Widgets/custom_navbar.dart';
import '../services/territory_service.dart';
import 'fullscreen_map_screen.dart';

class ResumenScreen extends StatefulWidget {
  final String? targetUserId;
  final String? targetNickname;
  final double distancia;
  final Duration tiempo;
  final List<LatLng> ruta;
  final List<Map<String, dynamic>> logrosCompletados;
  final int? timestamp;

  /// true  → viene de carrera: guarda territorio nuevo, muestra solo ese polígono
  /// false → viene de home/social: muestra TODOS los territorios de Firestore
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

class _ResumenScreenState extends State<ResumenScreen> {
  final MapController _mapController = MapController();
  String userId = '';
  bool isLoading = true;
  LatLng? _centroMapa;

  int monedasTotalesHistorial = 0;
  int retosTotalesHistorial = 0;
  List<Map<String, dynamic>> todosLosLogros = [];

  bool _verTodosLosLogros = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _logrosFiltrados = [];

  List<TerritoryData> _territoriosEnMapa = [];
  Color _colorTerritorio = Colors.orange;

  int _territoriosConquistados = 0;

  @override
  void initState() {
    super.initState();
    userId =
        widget.targetUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    _inicializarPantalla();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Flujo principal ───────────────────────────────────────────────────────
  Future<void> _inicializarPantalla() async {
    await _cargarUbicacionInicial();
    await _cargarColorUsuario();

    if (widget.esDesdeCarrera) {
      await _guardarYMostrarTerritorioActual();
    } else {
      await _cargarTodosLosTerritorios();
    }

    await Future.delayed(const Duration(seconds: 1));
    await _cargarHistorialTotal();

    if (widget.esDesdeCarrera && mounted) {
      final args = ModalRoute.of(context)?.settings.arguments
          as Map<String, dynamic>?;
      final int conquistados =
          (args?['territoriosConquistados'] as int?) ?? 0;
      if (conquistados > 0) {
        setState(() => _territoriosConquistados = conquistados);
        _mostrarBannerConquista(conquistados);
      }
    }
  }

  void _mostrarBannerConquista(int cantidad) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B00), Color(0xFFFF0000)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.5),
                    blurRadius: 12),
              ],
            ),
            child: Row(
              children: [
                const Text('⚔️', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '¡Territorio conquistado!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        cantidad == 1
                            ? 'Has conquistado 1 territorio de un rival'
                            : 'Has conquistado $cantidad territorios de rivales',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Future<void> _cargarColorUsuario() async {
    if (userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(userId)
          .get();
      if (doc.exists) {
        final colorInt =
            (doc.data()?['territorio_color'] as num?)?.toInt();
        if (colorInt != null && mounted) {
          setState(() => _colorTerritorio = Color(colorInt));
        }
      }
    } catch (e) {
      debugPrint("Error cargando color: $e");
    }
  }

  Future<void> _cargarUbicacionInicial() async {
    if (widget.ruta.isNotEmpty) {
      _centroMapa = widget.ruta.first;
    } else {
      _centroMapa = const LatLng(37.1350, -3.6330);
    }
    if (mounted) setState(() {});
  }

  Future<void> _guardarYMostrarTerritorioActual() async {
    if (widget.ruta.length < 2) return;

    final List<Map<String, double>> puntos = widget.ruta
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('territories').add({
        'userId': user.uid,
        'puntos': puntos,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final double latC =
          widget.ruta.map((p) => p.latitude).reduce((a, b) => a + b) /
              widget.ruta.length;
      final double lngC =
          widget.ruta.map((p) => p.longitude).reduce((a, b) => a + b) /
              widget.ruta.length;

      if (mounted) {
        setState(() {
          _territoriosEnMapa = [
            TerritoryData(
              docId: 'nuevo',
              ownerId: user.uid,
              ownerNickname: 'YO',
              color: _colorTerritorio,
              puntos: widget.ruta,
              centro: LatLng(latC, lngC),
              esMio: true,
              ultimaVisita: DateTime.now(),
            ),
          ];
        });
      }
    } catch (e) {
      debugPrint("Error guardando territorio: $e");
    }
  }

  Future<void> _cargarTodosLosTerritorios() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 6));

      final List<TerritoryData> resultado = [];

      for (var doc in snap.docs) {
        final data = doc.data();
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;

        final List<LatLng> puntos = rawPuntos.map((p) {
          final map = p as Map<String, dynamic>;
          return LatLng(
            (map['lat'] as num).toDouble(),
            (map['lng'] as num).toDouble(),
          );
        }).toList();

        final double latC =
            puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                puntos.length;
        final double lngC =
            puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                puntos.length;

        DateTime? ultimaVisita;
        final tsRaw = data['ultima_visita'];
        if (tsRaw is Timestamp) ultimaVisita = tsRaw.toDate();

        resultado.add(TerritoryData(
          docId: doc.id,
          ownerId: userId,
          ownerNickname: 'YO',
          color: _colorTerritorio,
          puntos: puntos,
          centro: LatLng(latC, lngC),
          esMio: true,
          ultimaVisita: ultimaVisita,
        ));
      }

      if (mounted) {
        setState(() => _territoriosEnMapa = resultado);
      }
    } catch (e) {
      debugPrint("Error cargando territorios: $e");
    }
  }

  Future<void> _guardarColorUsuario(Color nuevoColor) async {
    if (userId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(userId)
          .update({'territorio_color': nuevoColor.value});

      if (mounted) {
        setState(() {
          _colorTerritorio = nuevoColor;
          _territoriosEnMapa = _territoriosEnMapa.map((t) {
            return TerritoryData(
              docId: t.docId,
              ownerId: t.ownerId,
              ownerNickname: t.ownerNickname,
              color: nuevoColor,
              puntos: t.puntos,
              centro: t.centro,
              esMio: t.esMio,
              ultimaVisita: t.ultimaVisita,
            );
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Error guardando color: $e");
    }
  }

  Future<void> _cargarHistorialTotal() async {
    if (userId.isEmpty) return;
    if (mounted) setState(() => isLoading = true);

    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 5));

      List<Map<String, dynamic>> listaTemporal = [];
      int sumaMonedas = 0;

      for (var doc in logsSnap.docs) {
        final data = doc.data();
        listaTemporal.add({
          'titulo': data['titulo'] ?? 'Carrera completada',
          'recompensa': (data['recompensa'] as num? ?? 0).toInt(),
          'fecha': data['fecha_dia'] ?? 'Reciente',
          'timestamp': data['timestamp'],
        });
        sumaMonedas += (data['recompensa'] as num? ?? 0).toInt();
      }

      listaTemporal.sort((a, b) {
        Timestamp? tA = a['timestamp'] as Timestamp?;
        Timestamp? tB = b['timestamp'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });

      if (mounted) {
        setState(() {
          todosLosLogros = listaTemporal;
          _logrosFiltrados = listaTemporal;
          retosTotalesHistorial = listaTemporal.length;
          monedasTotalesHistorial = sumaMonedas;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error cargando historial: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filtrarBusqueda(String query) {
    setState(() {
      _logrosFiltrados = todosLosLogros
          .where((logro) => logro['titulo']
              .toString()
              .toLowerCase()
              .contains(query.toLowerCase()))
          .toList();
    });
  }

  void _mostrarSelectorColor() {
    final colores = [
      Colors.orange,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.yellow,
      Colors.pink,
      Colors.cyan,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Color de todos tus territorios',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Se aplicará a todos tus territorios y se guardará',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: colores
                  .map((color) => GestureDetector(
                        onTap: () {
                          _guardarColorUsuario(color);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: _colorTerritorio == color
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading || _centroMapa == null
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Stack(
              fit: StackFit.expand,
              children: [
                // ── FONDO: gradiente base ─────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black,
                        _colorTerritorio.withValues(alpha: 0.07),
                        Colors.black,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),

                // ── FONDO: grid decorativo (igual que perfil_screen) ──────
                CustomPaint(
                  painter: _GridPainter(color: _colorTerritorio),
                  size: Size.infinite,
                ),

                // ── CONTENIDO encima del fondo ────────────────────────────
                SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(context),
                        const SizedBox(height: 24),
                        _miniMapaResumen(),
                        const SizedBox(height: 24),
                        _statsGrid(retosTotalesHistorial),
                        const SizedBox(height: 28),
                        _achievementsSection(),
                        const SizedBox(height: 28),
                        _actions(context),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 2),
    );
  }

  // ── Mini mapa ─────────────────────────────────────────────────────────────
  Widget _miniMapaResumen() {
    bool tieneRutaValida = widget.ruta.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullscreenMapScreen(
                territorios: _territoriosEnMapa,
                colorTerritorio: _colorTerritorio,
                centroInicial: _centroMapa!,
                ruta: widget.ruta,
                mostrarRuta: widget.esDesdeCarrera,
              ),
            ),
          ),
          child: Stack(
            children: [
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _colorTerritorio.withValues(alpha: 0.25)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _centroMapa!,
                      initialZoom: 15,
                      onMapReady: () {
                        if (tieneRutaValida) {
                          _mapController.fitCamera(
                            CameraFit.bounds(
                              bounds: LatLngBounds.fromPoints(widget.ruta),
                              padding: const EdgeInsets.all(50),
                            ),
                          );
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.runner_risk.app',
                      ),
                      if (_territoriosEnMapa.isNotEmpty)
                        PolygonLayer(
                          polygons: _territoriosEnMapa.map((t) {
                            return Polygon(
                              points: t.puntos,
                              color: t.color.withValues(alpha: 0.67),
                              borderColor: t.color,
                              borderStrokeWidth: 3,
                            );
                          }).toList(),
                        ),
                      if (tieneRutaValida && widget.esDesdeCarrera)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: widget.ruta,
                              strokeWidth: 4.0,
                              color: _colorTerritorio,
                            ),
                          ],
                        ),
                      if (!tieneRutaValida)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _centroMapa!,
                              child: Icon(Icons.location_on,
                                  color: _colorTerritorio, size: 30),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fullscreen,
                      color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _mostrarSelectorColor,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _colorTerritorio.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _colorTerritorio,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Color de territorio',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(width: 8),
                const Icon(Icons.edit, color: Colors.white38, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    String titulo = widget.targetNickname != null
        ? 'Actividad de ${widget.targetNickname}'
        : 'Resumen de sesión';
    return Row(
      children: [
        if (Navigator.canPop(context))
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          )
        else
          const SizedBox(width: 10),
        Expanded(
          child: Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  // ── Stats grid ────────────────────────────────────────────────────────────
  Widget _statsGrid(int numRetos) {
    double horas = widget.tiempo.inSeconds / 3600;
    double velocidadMedia =
        (horas > 0 && widget.distancia > 0) ? widget.distancia / horas : 0.0;
    String tiempoFormateado =
        "${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}";

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      children: [
        _StatCard(
            icon: Icons.straighten,
            title: 'Distancia',
            value: widget.distancia.toStringAsFixed(2),
            unit: 'km',
            highlight: true,
            accentColor: _colorTerritorio),
        _StatCard(
            icon: Icons.timer,
            title: 'Tiempo',
            value: tiempoFormateado,
            unit: 'min',
            accentColor: _colorTerritorio),
        _StatCard(
            icon: Icons.speed,
            title: 'Velocidad',
            value: velocidadMedia.toStringAsFixed(1),
            unit: 'km/h',
            accentColor: _colorTerritorio),
        _StatCard(
            icon: Icons.military_tech,
            title: 'Retos Totales',
            value: numRetos.toString(),
            unit: 'tot',
            highlight: true,
            accentColor: _colorTerritorio),
        _StatCard(
            icon: Icons.monetization_on,
            title: 'Puntos G.',
            value: (widget.distancia * 10).toInt().toString(),
            unit: 'pts',
            highlight: true,
            accentColor: _colorTerritorio),
      ],
    );
  }

  // ── Achievements ──────────────────────────────────────────────────────────
  Widget _achievementsSection() {
    bool estaBuscando = _searchController.text.isNotEmpty;
    final listaAMostrar = (_verTodosLosLogros || estaBuscando)
        ? _logrosFiltrados
        : todosLosLogros.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '🏆 Historial de Logros',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            if (todosLosLogros.length > 5)
              TextButton(
                onPressed: () {
                  setState(() {
                    _verTodosLosLogros = !_verTodosLosLogros;
                    if (!_verTodosLosLogros) {
                      _searchController.clear();
                      _logrosFiltrados = todosLosLogros;
                    }
                  });
                },
                child: Text(
                  _verTodosLosLogros ? "Ver menos" : "Ver más",
                  style: TextStyle(color: _colorTerritorio),
                ),
              ),
          ],
        ),
        if (_verTodosLosLogros) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: _filtrarBusqueda,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Buscar reto...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.search, color: _colorTerritorio, size: 20),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
        const SizedBox(height: 15),
        if (listaAMostrar.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("No hay logros registrados",
                  style: TextStyle(color: Colors.white54)),
            ),
          )
        else
          ...listaAMostrar.map((data) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AchievementCard(
                  icon: Icons.emoji_events,
                  title: data['titulo'],
                  subtitle: 'Fecha: ${data['fecha']}',
                  points: '+${data['recompensa']} pts',
                  accentColor: _colorTerritorio,
                ),
              )),
      ],
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Widget _actions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.share, color: Colors.white),
            label: const Text('Compartir Logros'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: _colorTerritorio.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ── CustomPainter: grid decorativo (igual que en perfil_screen) ──────────────
// Líneas de cuadrícula + círculos concéntricos con la opacidad muy baja
// para que sea solo ambiente, no interfiere con el contenido
class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintLine);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintLine);
    }

    // Círculos de acento en la esquina superior derecha (igual que en perfil)
    final paintCircle = Paint()
      ..color = color.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.15), 100, paintCircle);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.15), 160, paintCircle);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.15), 220, paintCircle);

    // Segundo foco en la esquina inferior izquierda para dar más profundidad
    final paintCircle2 = Paint()
      ..color = color.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.85), 120, paintCircle2);
    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.85), 180, paintCircle2);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

// ── Widgets helper ────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final bool highlight;
  final Color accentColor;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    this.highlight = false,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: highlight
                ? accentColor.withValues(alpha: 0.5)
                : Colors.white24),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              color: highlight ? accentColor : Colors.white70, size: 20),
          const Spacer(),
          Text(title,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                      text: value,
                      style: TextStyle(
                          color: highlight ? accentColor : Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String points;
  final Color accentColor;

  const _AchievementCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: accentColor.withValues(alpha: 0.15),
              radius: 18,
              child: Icon(icon, color: accentColor, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Text(points,
              style: TextStyle(
                  color: accentColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}