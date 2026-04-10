// lib/scripts/seed_fantasmas_granada.dart
//
// Script de admin — siembra territorios fantasma en puntos clave de Granada.
// Se llama manualmente desde el menú de admin en perfil_screen.dart.
// Usa el mismo sistema de TerritoryService para crear bots reales en Firestore.

import 'package:latlong2/latlong.dart';
import '../services/territory_service.dart';

class SeedFantasmasGranada {
  /// Puntos clave alrededor de Granada donde se siembran fantasmas.
  static const List<LatLng> _centros = [
    LatLng(37.1773, -3.5986), // Centro histórico
    LatLng(37.1900, -3.6100), // Albaicín
    LatLng(37.1650, -3.6050), // Realejo
    LatLng(37.1820, -3.5800), // Campus universitario
    LatLng(37.1700, -3.5750), // Zaidín
    LatLng(37.2000, -3.5900), // Beiro
    LatLng(37.1600, -3.6200), // Chana
    LatLng(37.1950, -3.6300), // Norte
  ];

  /// Ejecuta la siembra para todos los centros de Granada.
  /// Solo añade fantasmas donde no haya territorios ya (reales o fantasma).
  static Future<void> ejecutar() async {
    for (final centro in _centros) {
      // Cargar lo que ya existe en esa zona
      final existentes = await TerritoryService.cargarTerritoriosFantasmaCercanos(
        centro: centro,
      );
      final reales = await TerritoryService.cargarTodosLosTerritorios(
        centro: centro,
      );

      await TerritoryService.crearTerritoriosFantasmaEnZona(
        centro:          centro,
        todosExistentes: [...reales, ...existentes],
        max:             20,
      );
    }
  }
}
