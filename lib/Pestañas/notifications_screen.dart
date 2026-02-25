import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import 'package:RunnerRisk/models/notif_item.dart';
import 'package:RunnerRisk/widgets/mini_mapa_notif.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;

  // ── Stream combinado robusto ───────────────────────────────────────────────
  // Mantiene el último valor de cada sub-stream por separado y emite
  // cada vez que cualquiera de los dos cambia. Así nunca se queda colgado
  // aunque uno de los dos no tenga datos o tarde en responder.
  Stream<List<NotifItem>> _streamCombinado() {
    if (userId == null) return Stream.value([]);

    final sNotifs = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => NotifItem.fromFirestore(doc)).toList());

    final sFriends = FirebaseFirestore.instance
        .collection('friendships')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => NotifItem(
                  id: doc.id,
                  tipo: 'friend_request',
                  mensaje: 'Nueva solicitud de amistad',
                  leida: false,
                  timestamp: doc.data()['timestamp'] as Timestamp?,
                ))
            .toList());

    late StreamController<List<NotifItem>> controller;
    List<NotifItem> lastNotifs = [];
    List<NotifItem> lastFriends = [];
    StreamSubscription? subNotifs;
    StreamSubscription? subFriends;

    void emit() {
      if (!controller.isClosed) {
        final all = [...lastNotifs, ...lastFriends];
        all.sort((a, b) => (b.timestamp ?? Timestamp.now())
            .compareTo(a.timestamp ?? Timestamp.now()));
        controller.add(all);
      }
    }

    controller = StreamController<List<NotifItem>>(
      onListen: () {
        // Emitimos lista vacía de inmediato para que el builder no muestre
        // el spinner infinito mientras llegan los datos de Firebase
        controller.add([]);

        subNotifs = sNotifs.listen(
          (n) {
            lastNotifs = n;
            emit();
          },
          onError: (e) {
            debugPrint('Error stream notifs: $e');
            emit(); // emitimos lo que tenemos aunque haya error
          },
        );

        subFriends = sFriends.listen(
          (f) {
            lastFriends = f;
            emit();
          },
          onError: (e) {
            debugPrint('Error stream friends: $e');
            emit();
          },
        );
      },
      onCancel: () {
        subNotifs?.cancel();
        subFriends?.cancel();
      },
    );

    return controller.stream;
  }

  // ── Formato de tiempo relativo ─────────────────────────────────────────────
  String _formatearTiempo(Timestamp? timestamp) {
    if (timestamp == null) return "";
    final ahora = DateTime.now();
    final fechaNotif = timestamp.toDate();
    final diferencia = ahora.difference(fechaNotif);

    if (diferencia.inMinutes < 1) return "Ahora mismo";
    if (diferencia.inMinutes < 60) return "Hace ${diferencia.inMinutes} min";
    if (diferencia.inHours < 24) return "Hace ${diferencia.inHours} h";
    if (diferencia.inDays == 1) return "Ayer";
    if (diferencia.inDays < 7) return "Hace ${diferencia.inDays} días";
    return "${fechaNotif.day}/${fechaNotif.month}/${fechaNotif.year}";
  }

  // ── Tap: marcar como leída + navegar ──────────────────────────────────────
  Future<void> _handleOnTap(NotifItem item) async {
    if (!item.leida) {
      try {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(item.id)
            .update({'read': true});
      } catch (e) {
        debugPrint("Error al marcar como leída: $e");
      }
    }

    if (!mounted) return;

    switch (item.tipo) {
      case 'friend_request':
        Navigator.pushNamed(context, '/social', arguments: {'initialTab': 1});
        break;
      case 'friend_accepted':
        Navigator.pushNamed(context, '/social', arguments: {'initialTab': 0});
        break;
      case 'territory_lost':
      case 'territory_steal_success':
      case 'territory_invasion':
        if (item.territoryId != null) {
          await _abrirDetalleTerritorio(item.territoryId!, item);
        }
        break;
      case 'territory_conquered':
        _abrirResumenConquista(item);
        break;
    }
  }

  // ── Detalle de territorio ──────────────────────────────────────────────────
  Future<void> _abrirDetalleTerritorio(
      String territoryId, NotifItem item) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('territories')
          .doc(territoryId)
          .get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final List<LatLng> puntos = (data['puntos'] as List)
          .map((p) =>
              LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
          .toList();
      if (!mounted) return;
      _mostrarPopUpDetalle(
        puntos: puntos,
        titulo: item.tipo == 'territory_lost' ? "PERDIDO" : "CAPTURADO",
        color: _colorPorTipo(item.tipo),
        stats: {
          'estado': data['activo'] == true ? "Activo" : "Perdido",
          'sinVisitar': data['ultima_visita'] != null
              ? "${DateTime.now().difference((data['ultima_visita'] as Timestamp).toDate()).inDays}d"
              : "0d",
          'distancia':
              "${item.distancia?.toStringAsFixed(2) ?? "--"} km",
          'velMedia': _calcVel(item),
          'tiempo': item.tiempoSegundos != null
              ? "${(item.tiempoSegundos! / 60).floor()} min"
              : "--",
        },
        nickname: item.fromNickname ?? "Rival",
      );
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  String _calcVel(NotifItem item) {
    if (item.distancia != null &&
        item.tiempoSegundos != null &&
        item.tiempoSegundos! > 0) {
      return "${(item.distancia! / (item.tiempoSegundos! / 3600)).toStringAsFixed(1)} km/h";
    }
    return "--";
  }

  void _mostrarPopUpDetalle({
    required List<LatLng> puntos,
    required String titulo,
    required Color color,
    required Map<String, String> stats,
    required String nickname,
  }) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                CircleAvatar(radius: 4, backgroundColor: color),
                const SizedBox(width: 8),
                Text(nickname.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white24, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              if (puntos.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 160,
                    child: MiniMapaNotif(
                      puntos: puntos,
                      centro: puntos[0],
                      color: color,
                      label: "",
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStatCard(Icons.shield_outlined, "Estado",
                      stats['estado']!, color),
                  _buildStatCard(Icons.calendar_today_outlined, "Sin visitar",
                      stats['sinVisitar']!, Colors.white60),
                  _buildStatCard(Icons.flag_outlined, "Conquistado", "--",
                      Colors.white60),
                  _buildStatCard(Icons.straighten_outlined, "Distancia",
                      stats['distancia']!, Colors.white60),
                  _buildStatCard(Icons.speed_outlined, "Vel. media",
                      stats['velMedia']!, Colors.purpleAccent),
                  _buildStatCard(Icons.timer_outlined, "Tiempo",
                      stats['tiempo']!, Colors.orangeAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, String label, String value, Color vColor) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: vColor),
          const Spacer(),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 9)),
          Text(value,
              style: TextStyle(
                  color: vColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _colorPorTipo(String t) {
    if (t.contains('lost')) return Colors.redAccent;
    if (t.contains('conquered') || t.contains('steal')) return Colors.cyanAccent;
    if (t.contains('friend')) return Colors.blueAccent;
    return Colors.orangeAccent;
  }

  IconData _iconoPorTipo(String t) {
    if (t.contains('lost')) return Icons.shield_outlined;
    if (t.contains('conquered') || t.contains('steal')) return Icons.flag_rounded;
    if (t == 'friend_request') return Icons.person_add_outlined;
    if (t == 'friend_accepted') return Icons.people_outlined;
    if (t.contains('invasion')) return Icons.warning_amber_rounded;
    return Icons.notifications_rounded;
  }

  void _abrirResumenConquista(NotifItem item) {
    Navigator.pushNamed(context, '/resumen', arguments: {
      'distancia': item.distancia ?? 0.0,
      'tiempo': Duration(seconds: item.tiempoSegundos ?? 0),
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "NOTIFICACIONES",
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: StreamBuilder<List<NotifItem>>(
        stream: _streamCombinado(),
        builder: (context, snapshot) {
          // Error de Firebase (permisos, red, etc.)
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white24, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Error al cargar notificaciones\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          // Mientras no ha llegado el primer evento (no debería durar nada
          // porque emitimos [] de inmediato, pero por si acaso)
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          final items = snapshot.data!;

          // Sin notificaciones
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      color: Colors.white12, size: 52),
                  const SizedBox(height: 16),
                  const Text(
                    'Sin notificaciones de momento',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final color = _colorPorTipo(item.tipo);
              final icono = _iconoPorTipo(item.tipo);

              return GestureDetector(
                onTap: () => _handleOnTap(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.leida
                        ? Colors.white.withOpacity(0.02)
                        : color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: item.leida
                          ? Colors.transparent
                          : color.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Punto de no leída
                      if (!item.leida)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Icon(icono, color: color, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.mensaje,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: item.leida
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatearTiempo(item.timestamp),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Colors.white24),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}