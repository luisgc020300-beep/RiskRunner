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
    );
  }
}