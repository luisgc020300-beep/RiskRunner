import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

class ResumenScreen extends StatefulWidget {
  final String? targetUserId;
  final String? targetNickname;
  final double distancia;
  final Duration tiempo;
  final List<LatLng> ruta;
  final List<Map<String, dynamic>> logrosCompletados;

  const ResumenScreen({
    super.key,
    this.targetUserId,
    this.targetNickname,
    required this.distancia,
    required this.tiempo,
    required this.ruta,
    this.logrosCompletados = const [],
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

  // --- VARIABLES DE CONTROL ---
  bool _verTodosLosLogros = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _logrosFiltrados = [];

  @override
  void initState() {
    super.initState();
    userId = widget.targetUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    _inicializarPantalla();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _inicializarPantalla() async {
    await _cargarUbicacionInicial();
    await _cargarHistorialTotal();
  }

  Future<void> _cargarUbicacionInicial() async {
    if (widget.ruta.isNotEmpty) {
      _centroMapa = widget.ruta.first;
    } else {
      try {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        _centroMapa = LatLng(position.latitude, position.longitude);
      } catch (e) {
        _centroMapa = const LatLng(40.4167, -3.70325);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _cargarHistorialTotal() async {
    if (userId.isEmpty) return;
    if (mounted) setState(() => isLoading = true);

    try {
      // Nota: Quitamos el orderBy para evitar errores de índices en Firebase
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .get();

      List<Map<String, dynamic>> listaTemporal = [];
      int sumaMonedas = 0;

      for (var doc in logsSnap.docs) {
        final data = doc.data();
        listaTemporal.add({
          'titulo': data['titulo'] ?? 'Reto completado',
          'recompensa': (data['recompensa'] as num? ?? 0).toInt(),
          'fecha': data['fecha_dia'] ?? 'Sin fecha',
          'timestamp': data['timestamp'], // Lo guardamos para ordenar
        });
        sumaMonedas += (data['recompensa'] as num? ?? 0).toInt();
      }

      // ORDENACIÓN MANUAL (Más reciente primero)
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

  Widget _achievementsSection() {
    bool estaBuscando = _searchController.text.isNotEmpty;
    
    // Si no está en "ver todos", solo mostramos los 5 primeros del historial
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
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                child: Text(_verTodosLosLogros ? "Ver menos" : "Ver más", 
                style: const TextStyle(color: Colors.orange)),
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
              prefixIcon: const Icon(Icons.search, color: Colors.orange, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
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
          const Center(child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("No hay logros registrados", style: TextStyle(color: Colors.white54)),
          ))
        else
          ...listaAMostrar.map((data) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AchievementCard(
              icon: Icons.emoji_events,
              title: data['titulo'],
              subtitle: 'Fecha: ${data['fecha']}',
              points: '+${data['recompensa']} pts',
            ),
          )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1C1C1E), Color(0xFF2C2C2E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: isLoading || _centroMapa == null
              ? const Center(child: CircularProgressIndicator(color: Colors.orange))
              : SingleChildScrollView(
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
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // --- WIDGETS DE APOYO EXTRAÍDOS PARA LIMPIEZA ---

  Widget _buildBottomNav() {
    return BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.white54,
        currentIndex: 2,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 2) return;
          if (index == 0) Navigator.pushReplacementNamed(context, '/home');
          if (index == 1) Navigator.pushReplacementNamed(context, '/correr');
          if (index == 3) Navigator.pushReplacementNamed(context, '/social');
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Correr'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Social'),
        ],
      );
  }

  Widget _miniMapaResumen() {
    bool tieneRutaValida = widget.ruta.length > 1;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.runner_risk.app',
            ),
            if (tieneRutaValida)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.ruta,
                    strokeWidth: 4.0,
                    color: Colors.orange,
                  ),
                ],
              ),
            if (!tieneRutaValida)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _centroMapa!,
                    child: const Icon(Icons.location_on, color: Colors.orange, size: 30),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

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
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _statsGrid(int numRetos) {
    double horas = widget.tiempo.inSeconds / 3600;
    double velocidadMedia = (horas > 0 && widget.distancia > 0) ? widget.distancia / horas : 0.0;
    String tiempoFormateado = "${widget.tiempo.inMinutes.toString().padLeft(2, '0')}:${(widget.tiempo.inSeconds % 60).toString().padLeft(2, '0')}";

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
        _StatCard(icon: Icons.straighten, title: 'Distancia', value: widget.distancia.toStringAsFixed(2), unit: 'km', highlight: true),
        _StatCard(icon: Icons.timer, title: 'Tiempo', value: tiempoFormateado, unit: 'min'),
        _StatCard(icon: Icons.speed, title: 'Velocidad', value: velocidadMedia.toStringAsFixed(1), unit: 'km/h'),
        _StatCard(icon: Icons.military_tech, title: 'Retos Totales', value: numRetos.toString(), unit: 'tot', highlight: true),
        _StatCard(icon: Icons.monetization_on, title: 'Puntos G.', value: (widget.distancia * 10).toInt().toString(), unit: 'pts', highlight: true),
      ],
    );
  }

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
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// Los widgets _StatCard y _AchievementCard se mantienen igual que en tu código original.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final bool highlight;
  const _StatCard({required this.icon, required this.title, required this.value, required this.unit, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? Colors.orange.withOpacity(0.5) : Colors.white24),
        color: Colors.white.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: highlight ? Colors.orange : Colors.white70, size: 20),
          const Spacer(),
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: value, style: TextStyle(color: highlight ? Colors.orange : Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  TextSpan(text: ' $unit', style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
  const _AchievementCard({required this.icon, required this.title, required this.subtitle, required this.points});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
        color: Colors.white.withOpacity(0.05),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Colors.orange.withOpacity(0.2), radius: 18, child: Icon(icon, color: Colors.orange, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Text(points, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}