import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'Pestañas/Home_screen.dart';
import 'Pestañas/social_screen.dart';
import 'Pestañas/Resumen_screen.dart';
import 'Pestañas/LiveActivity_screen.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  // Datos de la actividad
  double ultimaDistancia = 0.0;
  Duration ultimoTiempo = Duration.zero;
  List<LatLng> ultimaRuta = [];

  // Contador para forzar el refresco
  int _resumenKeyCounter = 0;

  // CORRECCIÓN: Guardado como variable, no calculado en cada build
  int _lastFinishTimestamp = 0;

  void _finalizarActividad(double distancia, Duration tiempo, List<LatLng> ruta) {
    setState(() {
      ultimaDistancia = distancia;
      ultimoTiempo = tiempo;
      ultimaRuta = ruta;
      _resumenKeyCounter++;
      _lastFinishTimestamp = DateTime.now().millisecondsSinceEpoch; // CORRECCIÓN
      _currentIndex = 2;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("¡Carrera finalizada con éxito!", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          LiveActivityScreen(onFinish: _finalizarActividad),
          ResumenScreen(
            key: ValueKey('resumen_$_resumenKeyCounter'), // CORRECCIÓN: key simple y limpio
            distancia: ultimaDistancia,
            tiempo: ultimoTiempo,
            ruta: ultimaRuta,
            timestamp: _lastFinishTimestamp, // CORRECCIÓN: variable guardada, no recalculada
          ),
          const SocialScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.white54,
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Correr'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Social'),
        ],
      ),
    );
  }
}