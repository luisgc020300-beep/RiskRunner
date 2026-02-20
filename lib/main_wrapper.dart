import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
// Asegúrate de que las rutas de importación sean las correctas en tu proyecto
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

  // Estas variables guardan los datos para pasárselos al Resumen
  double ultimaDistancia = 0.0;
  Duration ultimoTiempo = Duration.zero;
  List<LatLng> ultimaRuta = [];

  @override
  Widget build(BuildContext context) {
    // Definimos las pantallas aquí dentro para que se reconstruyan con los nuevos datos
    final List<Widget> _screens = [
      const HomeScreen(),
      LiveActivityScreen(
        onFinish: (distancia, tiempo, ruta) {
          // ESTO ES LO QUE TE REDIRIGE AUTOMÁTICAMENTE
          setState(() {
            ultimaDistancia = distancia;
            ultimoTiempo = tiempo;
            ultimaRuta = ruta;
            _currentIndex = 2; // Cambia a la pestaña de Resumen (índice 2)
          });
        },
      ),
      ResumenScreen(
        distancia: ultimaDistancia,
        tiempo: ultimoTiempo,
        ruta: ultimaRuta,
      ),
      const SocialScreen(),
    ];

    return Scaffold(
      // Usamos IndexedStack para mantener el estado de las pantallas
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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