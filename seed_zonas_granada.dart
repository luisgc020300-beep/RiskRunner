// lib/scripts/seed_zonas_granada.dart
//
// Ejecútalo UNA SOLA VEZ desde cualquier sitio de tu app, por ejemplo
// añadiendo un botón temporal en el menú de admin:
//
//   await SeedZonasGranada.ejecutar();
//
// Cuando termine, quita el botón. Las zonas quedan en Firestore para siempre.

import 'package:cloud_firestore/cloud_firestore.dart';

class SeedZonasGranada {
  static final _db = FirebaseFirestore.instance;

  static Future<void> ejecutar() async {
    final zonas = _zonasGranada();
    int insertadas = 0;

    for (final zona in zonas) {
      // Evitar duplicados: solo insertar si no existe ya una zona con ese nombre
      final existe = await _db
          .collection('zonas')
          .where('nombre', isEqualTo: zona['nombre'])
          .limit(1)
          .get();
      if (existe.docs.isNotEmpty) {
        print('⏭ Ya existe: ${zona['nombre']}');
        continue;
      }

      await _db.collection('zonas').add({
        'nombre'         : zona['nombre'],
        'nombre_corto'   : zona['nombre_corto'],
        'poligono'       : (zona['poligono'] as List).map((p) => {
          'lat': p[0],
          'lng': p[1],
        }).toList(),
        'rey_actual_id'  : null,
        'rey_actual_nick': null,
        'temporada_actual': 1,
        'ciudad'         : 'Granada',
        'creada'         : FieldValue.serverTimestamp(),
      });

      print('✅ Insertada: ${zona['nombre']}');
      insertadas++;
    }

    print('\n🏁 Completado: $insertadas zonas nuevas insertadas en Granada.');
  }

  static List<Map<String, dynamic>> _zonasGranada() {
    return [
      {
        'nombre'      : 'Centro',
        'nombre_corto': 'Centro',
        'poligono'    : [
          [37.1773, -3.5990],
          [37.1810, -3.5990],
          [37.1820, -3.5940],
          [37.1800, -3.5900],
          [37.1760, -3.5910],
          [37.1745, -3.5960],
          [37.1773, -3.5990],
        ],
      },
      {
        'nombre'      : 'Albaicín',
        'nombre_corto': 'Albaicín',
        'poligono'    : [
          [37.1800, -3.5940],
          [37.1840, -3.5940],
          [37.1860, -3.5890],
          [37.1840, -3.5840],
          [37.1810, -3.5850],
          [37.1790, -3.5890],
          [37.1800, -3.5940],
        ],
      },
      {
        'nombre'      : 'Realejo',
        'nombre_corto': 'Realejo',
        'poligono'    : [
          [37.1745, -3.5960],
          [37.1760, -3.5910],
          [37.1745, -3.5880],
          [37.1720, -3.5880],
          [37.1710, -3.5920],
          [37.1725, -3.5960],
          [37.1745, -3.5960],
        ],
      },
      {
        'nombre'      : 'Zaidín',
        'nombre_corto': 'Zaidín',
        'poligono'    : [
          [37.1620, -3.6000],
          [37.1680, -3.5980],
          [37.1700, -3.5920],
          [37.1680, -3.5860],
          [37.1620, -3.5860],
          [37.1590, -3.5920],
          [37.1600, -3.5980],
          [37.1620, -3.6000],
        ],
      },
      {
        'nombre'      : 'Chana',
        'nombre_corto': 'Chana',
        'poligono'    : [
          [37.1820, -3.6120],
          [37.1870, -3.6100],
          [37.1880, -3.6040],
          [37.1850, -3.5990],
          [37.1810, -3.5990],
          [37.1790, -3.6040],
          [37.1800, -3.6100],
          [37.1820, -3.6120],
        ],
      },
      {
        'nombre'      : 'Norte (Cartuja)',
        'nombre_corto': 'Cartuja',
        'poligono'    : [
          [37.1930, -3.6050],
          [37.1980, -3.6010],
          [37.1990, -3.5950],
          [37.1960, -3.5900],
          [37.1920, -3.5910],
          [37.1900, -3.5970],
          [37.1910, -3.6040],
          [37.1930, -3.6050],
        ],
      },
      {
        'nombre'      : 'Genil',
        'nombre_corto': 'Genil',
        'poligono'    : [
          [37.1700, -3.5860],
          [37.1740, -3.5840],
          [37.1750, -3.5790],
          [37.1720, -3.5760],
          [37.1690, -3.5770],
          [37.1670, -3.5820],
          [37.1680, -3.5860],
          [37.1700, -3.5860],
        ],
      },
      {
        'nombre'      : 'Rondas',
        'nombre_corto': 'Rondas',
        'poligono'    : [
          [37.1760, -3.5910],
          [37.1800, -3.5900],
          [37.1800, -3.5860],
          [37.1770, -3.5840],
          [37.1740, -3.5840],
          [37.1740, -3.5880],
          [37.1760, -3.5910],
        ],
      },
      {
        'nombre'      : 'Beiro',
        'nombre_corto': 'Beiro',
        'poligono'    : [
          [37.1900, -3.5910],
          [37.1940, -3.5890],
          [37.1950, -3.5840],
          [37.1920, -3.5800],
          [37.1880, -3.5810],
          [37.1870, -3.5860],
          [37.1890, -3.5910],
          [37.1900, -3.5910],
        ],
      },
      {
        'nombre'      : 'Sacromonte',
        'nombre_corto': 'Sacromonte',
        'poligono'    : [
          [37.1840, -3.5840],
          [37.1870, -3.5820],
          [37.1880, -3.5780],
          [37.1860, -3.5750],
          [37.1830, -3.5760],
          [37.1810, -3.5800],
          [37.1820, -3.5840],
          [37.1840, -3.5840],
        ],
      },
      {
        'nombre'      : 'La Caleta',
        'nombre_corto': 'La Caleta',
        'poligono'    : [
          [37.1850, -3.6040],
          [37.1890, -3.6020],
          [37.1900, -3.5970],
          [37.1870, -3.5940],
          [37.1840, -3.5950],
          [37.1830, -3.6000],
          [37.1840, -3.6040],
          [37.1850, -3.6040],
        ],
      },
      {
        'nombre'      : 'Figares',
        'nombre_corto': 'Figares',
        'poligono'    : [
          [37.1710, -3.5960],
          [37.1745, -3.5960],
          [37.1745, -3.5920],
          [37.1720, -3.5900],
          [37.1700, -3.5910],
          [37.1695, -3.5940],
          [37.1710, -3.5960],
        ],
      },
    ];
  }
}