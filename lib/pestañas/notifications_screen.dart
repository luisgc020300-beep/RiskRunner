import 'dart:async';
import 'package:RiskRunner/Widgets/mini_mapa_notif.dart';
import 'package:RiskRunner/models/notif_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../services/desafios_service.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kBg      = Color(0xFFE8E8ED);
const _kSurface = Color(0xFFFFFFFF);
const _kBorder2 = Color(0xFFD1D1D6);
const _kMuted   = Color(0xFFAEAEB2);
const _kDim     = Color(0xFF8E8E93);
const _kSub     = Color(0xFF636366);
const _kText    = Color(0xFF3C3C43);
const _kWhite   = Color(0xFF1C1C1E);
const _kRed     = Color(0xFFE02020);
const _kRedDim  = Color(0xFFFF6B6B);
const _kGold    = Color(0xFFFFD60A);
const _kGoldDim = Color(0xFFAEAEB2);
const _kGreen   = Color(0xFF30D158);

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.rajdhani(fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height);

// =============================================================================
// PANTALLA
// =============================================================================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;

  // ── Stream combinado: creado una sola vez en initState ────────────────────
  late final Stream<List<NotifItem>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
  }

  Stream<List<NotifItem>> _buildStream() {
    if (userId == null) return Stream.value([]);

    final sNotifs = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(60)
        .snapshots()
        .map((snap) => snap.docs.map(NotifItem.fromFirestore).toList());

    final sFriends = FirebaseFirestore.instance
        .collection('friendships')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => NotifItem(
              id: doc.id,
              tipo: 'friend_request',
              mensaje: 'Nueva solicitud de amistad',
              leida: false,
              timestamp: doc.data()['timestamp'] as Timestamp?,
            )).toList());

    late StreamController<List<NotifItem>> controller;
    List<NotifItem> lastNotifs  = [];
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
        controller.add([]);
        subNotifs  = sNotifs.listen(
            (n) { lastNotifs  = n; emit(); },
            onError: (_) => emit());
        subFriends = sFriends.listen(
            (f) { lastFriends = f; emit(); },
            onError: (_) => emit());
      },
      onCancel: () { subNotifs?.cancel(); subFriends?.cancel(); },
    );

    return controller.stream;
  }

  // ── Marcar todas como leídas ───────────────────────────────────────────────
  Future<void> _marcarTodasLeidas() async {
    if (userId == null) return;
    HapticFeedback.lightImpact();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marcarTodasLeidas: $e');
    }
  }

  // ── Handler de tap ─────────────────────────────────────────────────────────
  Future<void> _handleOnTap(NotifItem item) async {
    // Los desafíos recibidos no navegan al tap — tienen sus propios botones
    if (item.tipo == 'desafio_recibido' && !item.leida) return;

    // Marcar como leída
    if (!item.leida && item.tipo != 'friend_request') {
      try {
        await FirebaseFirestore.instance
            .collection('notifications').doc(item.id)
            .update({'read': true});
      } catch (e) {
        debugPrint('Error marcando leída: $e');
      }
    }

    if (!mounted) return;

    switch (item.tipo) {

      // ── Amistad ────────────────────────────────────────────────────────────
      case 'friend_request':
        Navigator.pushNamed(context, '/social', arguments: {'initialTab': 1});
        break;
      case 'friend_accepted':
        Navigator.pushNamed(context, '/social', arguments: {'initialTab': 0});
        break;

      // ── Territorios ────────────────────────────────────────────────────────
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

      // ── Desafíos ───────────────────────────────────────────────────────────
      case 'desafio_aceptado':
      case 'desafio_ganado':
      case 'desafio_perdido':
        Navigator.pushNamed(
          context, '/desafios',
          arguments: {'desafioId': item.desafioId},
        );
        break;

      // ── Desafío recibido pero ya leído (mostrar detalle) ───────────────────
      case 'desafio_recibido':
        if (item.desafioId != null) {
          Navigator.pushNamed(
            context, '/desafios',
            arguments: {'desafioId': item.desafioId},
          );
        }
        break;
    }
  }

  // ── Detalle de territorio ──────────────────────────────────────────────────
  Future<void> _abrirDetalleTerritorio(
      String territoryId, NotifItem item) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('territories').doc(territoryId).get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      final List<LatLng> puntos = (data['puntos'] as List)
          .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble()))
          .toList();
      _mostrarPopUpDetalle(
        puntos: puntos,
        titulo: item.tipo == 'territory_lost' ? 'PERDIDO' : 'CAPTURADO',
        color: _colorPorTipo(item.tipo),
        stats: {
          'estado':     data['activo'] == true ? 'Activo' : 'Perdido',
          'sinVisitar': data['ultima_visita'] != null
              ? '${DateTime.now().difference((data['ultima_visita'] as Timestamp).toDate()).inDays}d'
              : '0d',
          'distancia':  '${item.distancia?.toStringAsFixed(2) ?? "--"} km',
          'velMedia':   _calcVel(item),
          'tiempo':     item.tiempoSegundos != null
              ? '${(item.tiempoSegundos! / 60).floor()} min' : '--',
        },
        nickname: item.fromNickname ?? 'Rival',
      );
    } catch (e) {
      debugPrint('Error abrirDetalleTerritorio: $e');
    }
  }

  String _calcVel(NotifItem item) {
    if (item.distancia != null &&
        item.tiempoSegundos != null &&
        item.tiempoSegundos! > 0)
      return '${(item.distancia! / (item.tiempoSegundos! / 3600)).toStringAsFixed(1)} km/h';
    return '--';
  }

  void _abrirResumenConquista(NotifItem item) {
    Navigator.pushNamed(context, '/resumen', arguments: {
      'distancia': item.distancia ?? 0.0,
      'tiempo': Duration(seconds: item.tiempoSegundos ?? 0),
    });
  }

  void _mostrarPopUpDetalle({
    required List<LatLng> puntos, required String titulo,
    required Color color, required Map<String, String> stats,
    required String nickname,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kSurface,
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 32)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(width: 2, height: 16, color: color),
              const SizedBox(width: 10),
              Text(titulo, style: _raj(12, FontWeight.w900, color, spacing: 2)),
              const SizedBox(width: 8),
              Text(nickname.toUpperCase(),
                  style: _raj(12, FontWeight.w700, _kWhite)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: _kSub, size: 18),
                onPressed: () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            if (puntos.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 160,
                  child: MiniMapaNotif(
                      puntos: puntos, centro: puntos[0],
                      color: color, label: ''),
                ),
              ),
            ],
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true, crossAxisCount: 3,
              crossAxisSpacing: 8, mainAxisSpacing: 8,
              childAspectRatio: 0.85,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStatCard(Icons.shield_outlined, 'Estado',
                    stats['estado']!, color),
                _buildStatCard(Icons.calendar_today_outlined, 'Sin visitar',
                    stats['sinVisitar']!, _kText),
                _buildStatCard(Icons.straighten_outlined, 'Distancia',
                    stats['distancia']!, _kText),
                _buildStatCard(Icons.speed_outlined, 'Vel. media',
                    stats['velMedia']!, _kText),
                _buildStatCard(Icons.timer_outlined, 'Tiempo',
                    stats['tiempo']!, _kText),
                _buildStatCard(Icons.flag_outlined, 'Resultado',
                    titulo, color),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color c) =>
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _kBg,
          border: Border.all(color: _kBorder2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: c),
          const Spacer(),
          Text(label, style: _raj(8, FontWeight.w600, _kSub)),
          Text(value, style: _raj(11, FontWeight.w900, c)),
        ]),
      );

  // ── Helpers de estilo ──────────────────────────────────────────────────────
  Color _colorPorTipo(String t) {
    if (t.contains('lost'))                              return Colors.redAccent;
    if (t.contains('conquered') || t.contains('steal')) return Colors.cyanAccent;
    if (t == 'friend_request' || t == 'friend_accepted')return Colors.blueAccent;
    if (t.contains('invasion'))                         return Colors.orangeAccent;
    if (t == 'desafio_recibido')                        return _kRed;
    if (t == 'desafio_aceptado')                        return _kRed;
    if (t == 'desafio_ganado')                          return _kGold;
    if (t == 'desafio_perdido')                         return Colors.redAccent;
    return Colors.orangeAccent;
  }

  IconData _iconoPorTipo(String t) {
    if (t.contains('lost'))                              return Icons.shield_outlined;
    if (t.contains('conquered') || t.contains('steal')) return Icons.flag_rounded;
    if (t == 'friend_request')                          return Icons.person_add_outlined;
    if (t == 'friend_accepted')                         return Icons.people_outlined;
    if (t.contains('invasion'))                         return Icons.warning_amber_rounded;
    if (t == 'desafio_recibido')                        return Icons.sports_mma_rounded;
    if (t == 'desafio_aceptado')                        return Icons.sports_mma_rounded;
    if (t == 'desafio_ganado')                          return Icons.emoji_events_rounded;
    if (t == 'desafio_perdido')                         return Icons.sports_mma_rounded;
    return Icons.notifications_rounded;
  }

  String _labelPorTipo(String t) {
    switch (t) {
      case 'territory_lost':          return 'TERRITORIO PERDIDO';
      case 'territory_conquered':     return 'TERRITORIO CONQUISTADO';
      case 'territory_steal_success': return 'ROBO EXITOSO';
      case 'territory_invasion':      return 'INVASIÓN DETECTADA';
      case 'friend_request':          return 'SOLICITUD DE AMISTAD';
      case 'friend_accepted':         return 'SOLICITUD ACEPTADA';
      case 'desafio_recibido':        return 'DESAFÍO RECIBIDO';
      case 'desafio_aceptado':        return 'DESAFÍO ACEPTADO';
      case 'desafio_ganado':          return 'DESAFÍO GANADO';
      case 'desafio_perdido':         return 'DESAFÍO PERDIDO';
      default:                        return 'NOTIFICACIÓN';
    }
  }

  String _formatearTiempo(Timestamp? ts) {
    if (ts == null) return '';
    final dif = DateTime.now().difference(ts.toDate());
    if (dif.inMinutes < 1)  return 'Ahora mismo';
    if (dif.inMinutes < 60) return 'Hace ${dif.inMinutes} min';
    if (dif.inHours   < 24) return 'Hace ${dif.inHours} h';
    if (dif.inDays    == 1) return 'Ayer';
    if (dif.inDays    < 7)  return 'Hace ${dif.inDays} días';
    final dt = ts.toDate();
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // =============================================================================
  // BOTONES DE DESAFÍO
  // =============================================================================
  Widget _buildBotonesDesafio(NotifItem item) {
    final esContra  = item.esContrapropuesta;
    final desafioId = item.desafioId;
    final apuesta   = item.apuestaDesafio ?? 0;
    final horas     = item.duracionHoras ?? 24;

    if (esContra) {
      // Ronda 2: solo ACEPTAR o CANCELAR
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(child: _botonDesafio(
            label: '✅  ACEPTAR',
            color: _kRed,
            filled: true,
            onTap: () => _aceptarDesafio(item, apuesta, horas, desafioId),
          )),
          const SizedBox(width: 8),
          Expanded(child: _botonDesafio(
            label: 'CANCELAR',
            color: _kDim,
            filled: false,
            onTap: () => _cancelarDesafio(item, desafioId),
          )),
        ]),
      );
    }

    // Ronda 1: datos + ACEPTAR / NEGOCIAR / RECHAZAR
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      // Datos del desafío
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kBg,
          border: Border.all(color: _kBorder2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _datoCeldaDesafio('$apuesta 🪙', 'APUESTA'),
          Container(width: 1, height: 28, color: _kBorder2),
          _datoCeldaDesafio('${horas}h', 'DURACIÓN'),
          Container(width: 1, height: 28, color: _kBorder2),
          _datoCeldaDesafio('${apuesta * 2} 🪙', 'PREMIO'),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _botonDesafio(
          label: '⚔️  ACEPTAR',
          color: _kRed,
          filled: true,
          onTap: () => _aceptarDesafio(item, apuesta, horas, desafioId),
        )),
        const SizedBox(width: 6),
        Expanded(child: _botonDesafio(
          label: '🔄  NEGOCIAR',
          color: _kRed,
          filled: false,
          onTap: () => _abrirModalContrapropuesta(
              item, apuesta, horas, desafioId),
        )),
        const SizedBox(width: 6),
        Expanded(child: _botonDesafio(
          label: 'RECHAZAR',
          color: _kDim,
          filled: false,
          onTap: () => _rechazarDesafio(item, desafioId),
        )),
      ]),
    ]);
  }

  Widget _datoCeldaDesafio(String val, String label) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(val, style: _raj(16, FontWeight.w900, _kWhite, height: 1)),
        Text(label, style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
      ]);

  Widget _botonDesafio({
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            border: Border.all(
                color: filled ? color : color.withValues(alpha: 0.5)),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: _raj(10, FontWeight.w900,
                  filled ? Colors.white : color, spacing: 1)),
        ),
      );

  // =============================================================================
  // MODAL CONTRAPROPUESTA
  // =============================================================================
  Future<void> _abrirModalContrapropuesta(
      NotifItem item, int apuestaInicial, int horasIniciales,
      String? desafioId) async {
    if (userId == null || desafioId == null) return;
    final myDoc      = await FirebaseFirestore.instance
        .collection('players').doc(userId).get();
    final misMonedas = (myDoc.data()?['monedas'] as num?)?.toInt() ?? 0;
    final myNick     = myDoc.data()?['nickname'] as String? ?? 'Runner';

    int apuesta = apuestaInicial;
    int horas   = horasIniciales;
    final horasCtrl = TextEditingController(text: '$horasIniciales');

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 3, color: _kMuted)),
            const SizedBox(height: 24),
            Row(children: [
              Container(width: 2, height: 16, color: _kRed),
              const SizedBox(width: 10),
              Text('CONTRAPROPONAR',
                  style: _raj(13, FontWeight.w900, _kWhite, spacing: 2)),
            ]),
            const SizedBox(height: 6),
            Text('Propón tus condiciones al rival',
                style: _raj(12, FontWeight.w500, _kSub)),
            const SizedBox(height: 24),
            // Apuesta
            _buildInputControl(
              label: 'APUESTA',
              value: '$apuesta 🪙',
              sub: 'Tienes $misMonedas 🪙 disponibles',
              onMinus: () => setModal(() => apuesta = (apuesta - 25).clamp(25, misMonedas)),
              onPlus:  () => setModal(() => apuesta = (apuesta + 25).clamp(25, misMonedas)),
            ),
            const SizedBox(height: 12),
            // Horas
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFF101010),
                  border: Border.all(color: _kBorder2)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('DURACIÓN (HORAS)',
                    style: _raj(9, FontWeight.w700, _kDim, spacing: 2)),
                const SizedBox(height: 12),
                Row(children: [
                  GestureDetector(
                    onTap: () {
                      setModal(() => horas = (horas - 1).clamp(1, 168));
                      horasCtrl.text = '$horas';
                    },
                    child: Container(width: 36, height: 36,
                        color: _kMuted,
                        child: const Icon(Icons.remove, color: Colors.white, size: 16)),
                  ),
                  Expanded(child: TextField(
                    controller: horasCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: _raj(22, FontWeight.w900, _kWhite),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      suffix: Text('h', style: _raj(14, FontWeight.w600, _kSub)),
                    ),
                    onChanged: (v) {
                      final p = int.tryParse(v);
                      if (p != null) setModal(() => horas = p.clamp(1, 168));
                    },
                  )),
                  GestureDetector(
                    onTap: () {
                      setModal(() => horas = (horas + 1).clamp(1, 168));
                      horasCtrl.text = '$horas';
                    },
                    child: Container(width: 36, height: 36,
                        color: _kMuted,
                        child: const Icon(Icons.add, color: Colors.white, size: 16)),
                  ),
                ]),
                const SizedBox(height: 4),
                Center(child: Text('Mínimo 1h · Máximo 168h (7 días)',
                    style: _raj(9, FontWeight.w500, _kSub))),
              ]),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                await _enviarContrapropuesta(
                    item, desafioId, apuesta, horas, myNick);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                color: _kRed,
                child: Text('🔄  ENVIAR CONTRAPROPUESTA',
                    textAlign: TextAlign.center,
                    style: _raj(13, FontWeight.w900, Colors.white, spacing: 2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildInputControl({
    required String label, required String value,
    required String sub,
    required VoidCallback onMinus, required VoidCallback onPlus,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF101010),
            border: Border.all(color: _kBorder2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _raj(9, FontWeight.w700, _kDim, spacing: 2)),
          const SizedBox(height: 12),
          Row(children: [
            GestureDetector(onTap: onMinus,
                child: Container(width: 36, height: 36, color: _kMuted,
                    child: const Icon(Icons.remove, color: Colors.white, size: 16))),
            Expanded(child: Center(child: Text(value,
                style: _raj(28, FontWeight.w900, _kWhite)))),
            GestureDetector(onTap: onPlus,
                child: Container(width: 36, height: 36, color: _kMuted,
                    child: const Icon(Icons.add, color: Colors.white, size: 16))),
          ]),
          const SizedBox(height: 8),
          Center(child: Text(sub, style: _raj(10, FontWeight.w500, _kSub))),
        ]),
      );

  // =============================================================================
  // ACCIONES
  // =============================================================================
  Future<void> _enviarContrapropuesta(NotifItem item, String desafioId,
      int apuesta, int horas, String myNick) async {
    try {
      await FirebaseFirestore.instance
          .collection('desafios').doc(desafioId).update({
        'estado':              'contrapropuesta',
        'rondas':              1,
        'propuestaApuesta':    apuesta,
        'propuestaDuracion':   horas,
        'contrapropuestaDeId': userId,
      });

      final desafioDoc = await FirebaseFirestore.instance
          .collection('desafios').doc(desafioId).get();
      final data      = desafioDoc.data()!;
      final retadorId = data['retadorId'] as String;
      final toUserId  = userId == retadorId ? data['retadoId'] : retadorId;

      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId':          toUserId,
        'type':              'desafio_recibido',
        'fromUserId':        userId,
        'fromNickname':      myNick,
        'desafioId':         desafioId,
        'message':           '🔄 $myNick contrapropone: ${horas}h · $apuesta 🪙',
        'apuesta':           apuesta,
        'duracionHoras':     horas,
        'esContrapropuesta': true,
        'read':              false,
        'timestamp':         FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('notifications').doc(item.id)
          .update({'read': true});

      if (mounted) _snack('Contrapropuesta enviada', _kRed);
    } catch (e) {
      debugPrint('Error contrapropuesta: $e');
    }
  }

  Future<void> _aceptarDesafio(NotifItem item, int apuesta, int horas,
      String? desafioId) async {
    try {
      final String targetId;
      Map<String, dynamic> data;

      if (desafioId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('desafios').doc(desafioId).get();
        if (!doc.exists) return;
        targetId = desafioId;
        data     = doc.data()!;
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('desafios')
            .where('retadoId', isEqualTo: userId)
            .where('estado', isEqualTo: 'pendiente')
            .limit(1).get();
        if (snap.docs.isEmpty) return;
        targetId = snap.docs.first.id;
        data     = snap.docs.first.data();
      }

      final myDoc = await FirebaseFirestore.instance
          .collection('players').doc(userId).get();
      final misMonedas = (myDoc.data()?['monedas'] as num?)?.toInt() ?? 0;

      if (misMonedas < apuesta) {
        if (mounted) _snack('No tienes suficientes monedas', Colors.redAccent);
        return;
      }

      final ahora = DateTime.now();
      final fin   = ahora.add(Duration(hours: horas));

      await FirebaseFirestore.instance
          .collection('desafios').doc(targetId).update({
        'estado':        'activo',
        'apuesta':       apuesta,
        'duracionHoras': horas,
        'inicio':        Timestamp.fromDate(ahora),
        'fin':           Timestamp.fromDate(fin),
        'puntosRetador': 0,
        'puntosRetado':  0,
      });

      await FirebaseFirestore.instance
          .collection('players').doc(userId)
          .update({'monedas': FieldValue.increment(-apuesta)});
      await FirebaseFirestore.instance
          .collection('notifications').doc(item.id)
          .update({'read': true});

      final myNick    = myDoc.data()?['nickname'] as String? ?? 'Rival';
      final retadorId = data['retadorId'] as String;
      final toUserId  = userId == retadorId ? data['retadoId'] : retadorId;

      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId':     toUserId,
        'type':         'desafio_aceptado',
        'fromNickname': myNick,
        'desafioId':    targetId,
        'message':      '⚔️ $myNick aceptó el desafío · ${horas}h · $apuesta 🪙 ¡Empieza ahora!',
        'read':         false,
        'timestamp':    FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _snack('¡Desafío aceptado! Tienes ${horas}h para ganar', _kRed);
        // Navegar directamente a la pantalla de desafíos
        Navigator.pushNamed(context, '/desafios',
            arguments: {'desafioId': targetId});
      }
    } catch (e) {
      debugPrint('Error aceptando desafío: $e');
    }
  }

  Future<void> _rechazarDesafio(NotifItem item, String? desafioId) async {
    try {
      final String? id = desafioId ?? await _buscarDesafioPendiente();
      if (id == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('desafios').doc(id).get();
      if (doc.exists) {
        final apuesta = (doc.data()?['apuesta'] as num?)?.toInt() ?? 0;
        final retadorId = doc.data()?['retadorId'] as String?;
        if (retadorId != null && apuesta > 0) {
          await FirebaseFirestore.instance
              .collection('players').doc(retadorId)
              .update({'monedas': FieldValue.increment(apuesta)});
        }
        await FirebaseFirestore.instance
            .collection('desafios').doc(id)
            .update({'estado': 'rechazado'});
      }
      await FirebaseFirestore.instance
          .collection('notifications').doc(item.id)
          .update({'read': true});

      if (mounted) _snack('Desafío rechazado', Colors.black54);
    } catch (e) {
      debugPrint('Error rechazando desafío: $e');
    }
  }

  Future<void> _cancelarDesafio(NotifItem item, String? desafioId) async {
    try {
      final String? id = desafioId ?? await _buscarDesafioPendiente();
      if (id == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('desafios').doc(id).get();
      if (doc.exists) {
        final apuesta   = (doc.data()?['apuesta'] as num?)?.toInt() ?? 0;
        final retadorId = doc.data()?['retadorId'] as String?;
        if (retadorId != null && apuesta > 0) {
          await FirebaseFirestore.instance
              .collection('players').doc(retadorId)
              .update({'monedas': FieldValue.increment(apuesta)});
        }
        await FirebaseFirestore.instance
            .collection('desafios').doc(id)
            .update({'estado': 'cancelado'});
      }
      await FirebaseFirestore.instance
          .collection('notifications').doc(item.id)
          .update({'read': true});

      if (mounted) _snack('Desafío cancelado — monedas devueltas', Colors.black54);
    } catch (e) {
      debugPrint('Error cancelando desafío: $e');
    }
  }

  Future<String?> _buscarDesafioPendiente() async {
    final snap = await FirebaseFirestore.instance
        .collection('desafios')
        .where('retadoId', isEqualTo: userId)
        .where('estado', isEqualTo: 'pendiente')
        .limit(1).get();
    return snap.docs.isNotEmpty ? snap.docs.first.id : null;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: _raj(13, FontWeight.w700, Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
    ));
  }

  // =============================================================================
  // BUILD
  // =============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('NOTIFICACIONES',
            style: _raj(14, FontWeight.w900, Colors.white, spacing: 3)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kRed),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded, color: _kDim, size: 20),
            tooltip: 'Marcar todas como leídas',
            onPressed: _marcarTodasLeidas,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<NotifItem>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wifi_off_rounded, color: _kDim, size: 40),
              const SizedBox(height: 12),
              Text('Error al cargar notificaciones',
                  style: _raj(13, FontWeight.w500, _kSub)),
            ]));
          }
          if (!snapshot.hasData) return const Center(
              child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));

          final items = snapshot.data!;
          if (items.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.notifications_off_outlined, color: _kMuted, size: 52),
              const SizedBox(height: 16),
              Text('Sin notificaciones de momento',
                  style: _raj(14, FontWeight.w500, _kSub)),
            ]));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item  = items[i];
              final color = _colorPorTipo(item.tipo);
              final icono = _iconoPorTipo(item.tipo);
              final label = _labelPorTipo(item.tipo);
              final esDesafioActivo = item.tipo == 'desafio_recibido'
                  && !item.leida;

              return GestureDetector(
                onTap: () => _handleOnTap(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: item.leida
                        ? _kSurface
                        : color.withValues(alpha: 0.06),
                    border: Border(
                      left: BorderSide(
                          color: item.leida
                              ? _kBorder2
                              : color.withValues(alpha: 0.6),
                          width: 2),
                      top: BorderSide(color: _kBorder2),
                      right: BorderSide(color: _kBorder2),
                      bottom: BorderSide(color: _kBorder2),
                    ),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      // Punto no leída
                      if (!item.leida)
                        Container(
                          width: 6, height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                      Icon(icono, color: color, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(label, style: _raj(8, FontWeight.w900,
                            color, spacing: 1.5)),
                        const SizedBox(height: 3),
                        Text(item.mensaje, style: _raj(13,
                            item.leida ? FontWeight.w500 : FontWeight.w700,
                            item.leida ? _kText : _kWhite)),
                        const SizedBox(height: 3),
                        Text(_formatearTiempo(item.timestamp),
                            style: _raj(10, FontWeight.w500, _kSub)),
                      ])),
                      if (!esDesafioActivo)
                        Icon(Icons.chevron_right_rounded,
                            color: _kDim, size: 16),
                    ]),
                    if (esDesafioActivo)
                      _buildBotonesDesafio(item),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}