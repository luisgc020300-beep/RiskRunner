import 'package:cloud_firestore/cloud_firestore.dart';

class NotifItem {
  final String id;
  final String tipo;
  final String mensaje;
  final Timestamp? timestamp;
  final bool leida;
  final String? territoryId;
  final String? fromNickname;
  final double? distancia;
  final int? tiempoSegundos;

  // ── Campos para desafíos ──────────────────────────────────
  final String? desafioId;
  final int? apuestaDesafio;
  final int? duracionHoras;
  final bool esContrapropuesta;
  final String? fromUserId;

  NotifItem({
    required this.id,
    required this.tipo,
    required this.mensaje,
    this.timestamp,
    required this.leida,
    this.territoryId,
    this.fromNickname,
    this.distancia,
    this.tiempoSegundos,
    this.desafioId,
    this.apuestaDesafio,
    this.duracionHoras,
    this.esContrapropuesta = false,
    this.fromUserId,
  });

  factory NotifItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotifItem(
      id: doc.id,
      tipo: data['type'] ?? '',
      mensaje: data['message'] ?? '',
      timestamp: data['timestamp'] as Timestamp?,
      leida: data['read'] ?? false,
      territoryId: data['territoryId'] as String?,
      fromNickname: data['fromNickname'] as String?,
      distancia: (data['distancia'] as num?)?.toDouble(),
      tiempoSegundos: (data['tiempo_segundos'] as num?)?.toInt(),
      desafioId: data['desafioId'] as String?,
      apuestaDesafio: (data['apuesta'] as num?)?.toInt(),
      duracionHoras: (data['duracionHoras'] as num?)?.toInt(),
      esContrapropuesta: data['esContrapropuesta'] as bool? ?? false,
      fromUserId: data['fromUserId'] as String?,
    );
  }
}