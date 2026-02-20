import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final CollectionReference desafiosRef =
      FirebaseFirestore.instance.collection('daily_challenges');

  Future<void> cargarDesafiosMasivos() async {
    List<Map<String, dynamic>> listaRetos = [
      // NIVEL 1-9 (Rango 1)
      {"titulo": "Paseo de Calentamiento", "descripcion": "Camina o trota 1km", "objetivo_valor": 1000, "rango_requerido": 1, "recompensas_monedas": 50},
      {"titulo": "Sprint Matutino", "descripcion": "Recorre 500m a ritmo rápido", "objetivo_valor": 500, "rango_requerido": 1, "recompensas_monedas": 40},
      {"titulo": "Explorador Barrial", "descripcion": "Mapea 1.5km en tu zona", "objetivo_valor": 1500, "rango_requerido": 1, "recompensas_monedas": 75},
      {"titulo": "Resistencia Básica", "descripcion": "Mantén el movimiento por 2km", "objetivo_valor": 2000, "rango_requerido": 1, "recompensas_monedas": 100},
      {"titulo": "Cazador de Sombras", "descripcion": "Corre 1.2km al atardecer", "objetivo_valor": 1200, "rango_requerido": 1, "recompensas_monedas": 60},
      {"titulo": "Ruta de Vigilancia", "descripcion": "Patrulla 800m de terreno nuevo", "objetivo_valor": 800, "rango_requerido": 1, "recompensas_monedas": 45},
      {"titulo": "Doble Paso", "descripcion": "Completa 2.5km trotando", "objetivo_valor": 2500, "rango_requerido": 1, "recompensas_monedas": 120},
      {"titulo": "Escurridizo", "descripcion": "Recorre 600m en menos de 4 min", "objetivo_valor": 600, "rango_requerido": 1, "recompensas_monedas": 55},
      
      // NIVEL 10+ (Rango 10)
      {"titulo": "Maratón de Distrito", "descripcion": "Domina 5km de una sola vez", "objetivo_valor": 5000, "rango_requerido": 10, "recompensas_monedas": 300},
      {"titulo": "Asalto de Velocidad", "descripcion": "Sprint de 2km sostenido", "objetivo_valor": 2000, "rango_requerido": 10, "recompensas_monedas": 250},
      {"titulo": "Comandante de Zona", "descripcion": "Mapea 7km en total", "objetivo_valor": 7000, "rango_requerido": 10, "recompensas_monedas": 450},
      {"titulo": "Corredor Fantasma", "descripcion": "Completa 4km sin detenerte", "objetivo_valor": 4000, "rango_requerido": 10, "recompensas_monedas": 350},
    ];

    for (var reto in listaRetos) {
      // Usamos 'add' para que Firebase cree un ID automático único para cada uno
      await desafiosRef.add(reto);
    }
    print("--- ¡DESAFÍOS CARGADOS CON ÉXITO EN FIREBASE! ---");
  }
}