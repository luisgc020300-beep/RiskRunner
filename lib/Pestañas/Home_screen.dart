import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  Position? _currentPosition;
  String nickname = "Cargando...";
  int monedas = 0;
  int nivel = 1;
  bool isLoading = true;

  List<QueryDocumentSnapshot> _dailyChallenges = [];
  bool _loadingChallenges = true;
  List<Map<String, dynamic>> _completedChallengesCache = [];

  bool _mostrarTodosLosLogros = false;
  Timer? _dailyResetTimer;
  Duration _timeUntilReset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _initializeData();
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position position = await Geolocator.getCurrentPosition();
        if (mounted) setState(() => _currentPosition = position);
      }
    } catch (e) {
      debugPrint("Error ubicación: $e");
    }
  }

  Future<void> _initializeData() async {
    if (userId == null) return;
    if (mounted) setState(() => isLoading = true);

    try {
      await _loadUserData();
      await _checkDailyReset();
      await _loadCompletedChallenges();
      await _loadRandomDailyChallenges();
    } catch (e) {
      debugPrint("Error en inicialización: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadUserData() async {
    final userDoc = await FirebaseFirestore.instance.collection('players').doc(userId).get();
    if (userDoc.exists && mounted) {
      final data = userDoc.data()!;
      setState(() {
        nickname = data['nickname'] ?? "Corredor";
        monedas = data['monedas'] ?? 0;
        nivel = data['nivel'] ?? 1;
      });
    }
  }

  Future<void> _loadCompletedChallenges() async {
    if (userId == null) return;
    
    final ahora = DateTime.now();
    final String fechaHoy = "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";

    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .where('fecha_dia', isEqualTo: fechaHoy)
          .get();

      List<Map<String, dynamic>> listaTemporal = logsSnap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();

      listaTemporal.sort((a, b) {
        Timestamp? tA = a['timestamp'] as Timestamp?;
        Timestamp? tB = b['timestamp'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });

      if (mounted) {
        setState(() {
          _completedChallengesCache = listaTemporal;
        });
      }
    } catch (e) {
      debugPrint("Error cargando logros: $e");
    }
  }

  Future<void> _checkDailyReset() async {
    final userDocRef = FirebaseFirestore.instance.collection('players').doc(userId);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) return;

    final data = userDoc.data()!;
    final lastReset = data['last_daily_reset'] as Timestamp?;
    final now = DateTime.now();

    if (lastReset == null || now.difference(lastReset.toDate()).inHours >= 24) {
      await userDocRef.update({'last_daily_reset': Timestamp.now()});
      _setupDailyTimer(lastResetTime: now);
    } else {
      _setupDailyTimer(lastResetTime: lastReset.toDate());
    }
  }

  void _setupDailyTimer({required DateTime lastResetTime}) {
    final resetTime = lastResetTime.add(const Duration(hours: 24));
    _dailyResetTimer?.cancel();
    
    _dailyResetTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final now = DateTime.now();
        setState(() {
          _timeUntilReset = resetTime.difference(now);
        });

        if (_timeUntilReset.isNegative || _timeUntilReset.inSeconds == 0) {
          _dailyResetTimer?.cancel();
          _handleDailyReset();
        }
      }
    });
  }

  Future<void> _handleDailyReset() async {
    if (mounted) {
      setState(() {
        _completedChallengesCache.clear();
        _dailyChallenges.clear();
        isLoading = true;
      });
    }
    await _initializeData(); 
  }

  Future<void> _loadRandomDailyChallenges() async {
    if (mounted) setState(() => _loadingChallenges = true);
    try {
      final challengesSnap = await FirebaseFirestore.instance
          .collection('daily_challenges')
          .where('rango_requerido', isLessThanOrEqualTo: nivel)
          .get();

      final completedIds = _completedChallengesCache
          .map((c) => c['id_reto_completado']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final disponibles = challengesSnap.docs
          .where((doc) => !completedIds.contains(doc.id))
          .toList();
      
      disponibles.shuffle();

      if (mounted) {
        setState(() {
          _dailyChallenges = disponibles.take(3).toList();
          _loadingChallenges = false;
        });
      }
    } catch (e) {
      debugPrint("Error desafíos: $e");
      if (mounted) setState(() => _loadingChallenges = false);
    }
  }

  Future<void> _finalizarActividad(String id, String titulo, int premio) async {
    if (userId == null) return;
    
    final ahora = DateTime.now();
    final String fechaId = "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";

    setState(() {
      _completedChallengesCache.insert(0, {
        'titulo': titulo, 
        'recompensa': premio, 
        'id_reto_completado': id,
        'fecha_dia': fechaId,
        'timestamp': Timestamp.now(),
      });
      _dailyChallenges.removeWhere((doc) => doc.id == id);
      monedas += premio;
    });

    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': userId,
        'id_reto_completado': id,
        'titulo': titulo,
        'recompensa': premio,
        'timestamp': FieldValue.serverTimestamp(),
        'fecha_dia': fechaId, 
      });

      await FirebaseFirestore.instance.collection('players').doc(userId).update({
        'monedas': monedas,
        'nivel': (monedas ~/ 30) + 1,
      });
    } catch (e) {
      debugPrint("Error al guardar: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Runner Risk", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: _initializeData),
          _buildUserMenu(),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
              onRefresh: _initializeData,
              color: Colors.orange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    _buildUserHeader(),
                    const SizedBox(height: 30),
                    _buildTwoStatsCards(),
                    const SizedBox(height: 25),
                    
                    _buildSectionTitle(
                      "Logros de Hoy", 
                      _completedChallengesCache.length > 3 ? (_mostrarTodosLosLogros ? "Ver menos" : "Ver todos") : "",
                      () => setState(() => _mostrarTodosLosLogros = !_mostrarTodosLosLogros)
                    ),
                    const SizedBox(height: 15),
                    _buildCompletedChallengesList(),
                    
                    const SizedBox(height: 25),
                    _buildSectionTitle("Desafíos del Día", "Hoy", null),
                    _buildDailyResetTimer(),
                    const SizedBox(height: 15),
                    _buildDailyChallengesList(),
                    const SizedBox(height: 100), 
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // --- WIDGETS DE APOYO ---

  Widget _buildCompletedChallengesList() {
    if (_completedChallengesCache.isEmpty) {
      return const Text("No hay retos completados hoy", style: TextStyle(color: Colors.white54));
    }

    final lista = _mostrarTodosLosLogros 
        ? _completedChallengesCache 
        : _completedChallengesCache.take(3).toList();

    return Column(
      children: lista.map((data) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(data['titulo'] ?? "Reto", style: const TextStyle(color: Colors.white))),
            Text("+${data['recompensa']}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildDailyChallengesList() {
    if (_loadingChallenges) return const Center(child: CircularProgressIndicator(color: Colors.orange));
    if (_dailyChallenges.isEmpty) return const Text("¡Todos los desafíos completados!", style: TextStyle(color: Colors.white54));

    return Column(
      children: _dailyChallenges.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return InkWell(
          onTap: () => _finalizarActividad(doc.id, data['titulo'], data['recompensas_monedas']),
          child: _buildChallengeCard(data['titulo'], data['descripcion'], data['recompensas_monedas'].toString()),
        );
      }).toList(),
    );
  }

  Widget _buildChallengeCard(String title, String desc, String reward) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
    child: Row(
      children: [
        const Icon(Icons.bolt, color: Colors.orange),
        const SizedBox(width: 15),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        Text("+$reward", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _buildSectionTitle(String title, String action, VoidCallback? onActionTap) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      if (action.isNotEmpty)
        TextButton(onPressed: onActionTap, child: Text(action, style: const TextStyle(color: Colors.orange))),
    ],
  );

  Widget _buildDailyResetTimer() {
    final h = _timeUntilReset.inHours.toString().padLeft(2, '0');
    final m = _timeUntilReset.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _timeUntilReset.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text("Reset en: $h:$m:$s", style: const TextStyle(color: Colors.white54, fontSize: 12));
  }

  Widget _buildUserHeader() => Row(
    children: [
      const CircleAvatar(radius: 30, backgroundColor: Colors.orange, child: Icon(Icons.person, color: Colors.white, size: 35)),
      const SizedBox(width: 15),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(nickname, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text("Nivel $nivel", style: const TextStyle(color: Colors.orange, fontSize: 14)),
      ]),
    ],
  );

  Widget _buildTwoStatsCards() => Row(
    children: [
      Expanded(child: _ClickableStatCard(label: "Nivel", value: nivel.toString(), icon: Icons.military_tech)),
      const SizedBox(width: 15),
      Expanded(child: _ClickableStatCard(label: "Monedas", value: monedas.toString(), icon: Icons.stars)),
    ],
  );

  Widget _buildUserMenu() => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert, color: Colors.orange),
    onSelected: (value) async {
      if (value == 'logout') {
        try {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            // Navegación limpia al Login
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        } catch (e) {
          debugPrint("Error al cerrar sesión: $e");
        }
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'logout', 
        child: Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent, size: 20), 
            SizedBox(width: 10),
            Text('Cerrar sesión', style: TextStyle(color: Colors.black87)),
          ],
        )
      ),
    ],
  );

  Widget _buildBottomNav() => BottomNavigationBar(
    backgroundColor: const Color(0xFF1A1A1A),
    selectedItemColor: Colors.orange,
    unselectedItemColor: Colors.white54,
    currentIndex: 0,
    type: BottomNavigationBarType.fixed,
    onTap: (index) {
      if (index == 0) return;
      if (index == 1) Navigator.pushReplacementNamed(context, '/correr');
      if (index == 2) Navigator.pushReplacementNamed(context, '/resumen');
      if (index == 3) Navigator.pushReplacementNamed(context, '/social');
    },
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: 'Correr'),
      BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Resumen'),
      BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Social'),
    ],
  );
}

class _ClickableStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _ClickableStatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(25)),
      child: Column(children: [
        Icon(icon, color: Colors.orange, size: 30),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}