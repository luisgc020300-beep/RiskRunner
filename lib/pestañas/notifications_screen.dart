import 'dart:async';
import 'package:RiskRunner/widgets/mini_mapa_notif.dart';
import 'package:RiskRunner/models/notif_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';

// Alias locales para no reescribir cada referencia en el cuerpo del archivo
const _kBg      = AppColors.bg;
const _kSurface = AppColors.surface;
const _kBorder2 = AppColors.border;
const _kMuted   = AppColors.textMuted;
const _kDim     = AppColors.textTertiary;
const _kSub     = AppColors.textTertiary;
const _kText    = AppColors.textSecondary;
const _kWhite   = AppColors.textPrimary;
const _kRed     = AppColors.red;

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0.5, double? height}) =>
    AppTypography.raj(size, weight, color, spacing: spacing, height: height);

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
        .map((snap) => snap.docs.map((doc) {
              final d    = doc.data();
              final tipo = (d['type'] as String?) == 'follow_request'
                  ? 'follow_request'
                  : 'friend_request';
              return NotifItem(
                id: doc.id,
                tipo: tipo,
                mensaje: tipo == 'follow_request'
                    ? 'Quiere seguirte'
                    : 'Nueva solicitud de amistad',
                leida: false,
                timestamp: d['timestamp'] as Timestamp?,
                fromUserId: d['senderId'] as String?,
                fromNickname: d['senderNickname'] as String?,
              );
            }).toList());

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

      // ── Follow ─────────────────────────────────────────────────────────────
      case 'follow':
        if (item.fromUserId != null) {
          Navigator.pushNamed(context, '/perfil',
              arguments: {'userId': item.fromUserId});
        }
        break;

      // ── Solicitudes (amistad y seguimiento) ───────────────────────────────
      case 'follow_request':
      case 'friend_request':
        if (item.fromUserId != null) {
          Navigator.pushNamed(context, '/perfil',
              arguments: {'userId': item.fromUserId});
        } else {
          Navigator.pushNamed(context, '/social', arguments: {'initialTab': 1});
        }
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

      // ── Publicaciones: like y comentario ──────────────────────────────────
      case 'post_like':
      case 'post_comment':
        await _abrirDetallePost(item.postId);
        break;
    }
  }

  // ── Detalle de publicación ─────────────────────────────────────────────────
  Future<void> _abrirDetallePost(String? postId) async {
    if (postId == null) { return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('posts').doc(postId).get();
      if (!mounted) return;
      if (!doc.exists) {
        _snack('Esta publicación ya no existe', _kMuted);
        return;
      }
      _mostrarPopUpPost(doc.data()!);
    } catch (e) {
      debugPrint('Error abrirDetallePost: $e');
    }
  }

  void _mostrarPopUpPost(Map<String, dynamic> data) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bgColor  = isDark ? const Color(0xFF1C1C1E) : _kSurface;
    final txtColor = isDark ? const Color(0xFFEEEEEE) : _kWhite;

    final dist   = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
    final tiempo = (data['tiempoSegundos'] as num?)?.toInt() ?? 0;
    final vel    = (data['velocidadMedia'] as num?)?.toDouble() ?? 0;
    final desc   = (data['descripcion'] as String? ?? '').trim();
    final titulo = (data['titulo'] as String? ?? '').trim();
    final ts     = data['timestamp'] as Timestamp?;
    final mins   = tiempo ~/ 60;
    final secs   = tiempo % 60;

    final List<LatLng> puntos = ((data['ruta'] as List<dynamic>?) ?? []).map((p) {
      final m = p as Map;
      return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(
              color: isDark ? const Color(0xFF38383A) : _kBorder2),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: _kMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2)),
          ),
          if (titulo.isNotEmpty || ts != null) ...[
            Row(children: [
              if (titulo.isNotEmpty)
                Expanded(child: Text(titulo,
                    style: _raj(15, FontWeight.w700, txtColor))),
              if (ts != null)
                Text(
                  '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}',
                  style: _raj(10, FontWeight.w400, _kSub),
                ),
            ]),
            const SizedBox(height: 16),
          ],
          if (puntos.length > 1) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 180,
                child: FlutterMap(
                  options: MapOptions(
                    backgroundColor: const Color(0xFF1A1A1A),
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(puntos),
                      padding: const EdgeInsets.all(32),
                    ),
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.tuapp.juego',
                    ),
                    PolylineLayer(polylines: [
                      Polyline(
                          points: puntos,
                          color: _kRed,
                          strokeWidth: 3),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(children: [
            _postStatCell(
                '${dist.toStringAsFixed(2)} km', 'DISTANCIA', txtColor),
            Container(width: 1, height: 32,
                color: isDark ? const Color(0xFF38383A) : _kBorder2),
            _postStatCell(
                '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                'TIEMPO', txtColor),
            Container(width: 1, height: 32,
                color: isDark ? const Color(0xFF38383A) : _kBorder2),
            _postStatCell(
                '${vel.toStringAsFixed(1)} km/h', 'VELOCIDAD', txtColor),
          ]),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 0.5,
                color: isDark ? const Color(0xFF38383A) : _kBorder2),
            const SizedBox(height: 12),
            Text(desc,
                style: _raj(13, FontWeight.w400, txtColor),
                maxLines: 5,
                overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
  }

  Widget _postStatCell(String val, String label, Color txtColor) =>
      Expanded(child: Column(children: [
        Text(val, style: _raj(12, FontWeight.w800, txtColor)),
        const SizedBox(height: 2),
        Text(label, style: _raj(7, FontWeight.w700, _kSub, spacing: 1)),
      ]));

  // ── Detalle de territorio ──────────────────────────────────────────────────
  Future<void> _abrirDetalleTerritorio(
      String territoryId, NotifItem item) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('territories').doc(territoryId).get();
      if (!mounted) return;
      if (!doc.exists) {
        _snack('Este territorio ya no existe', _kMuted);
        return;
      }
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
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final dialogBg     = isDark ? const Color(0xFF1C1C1E) : _kSurface;
    final cardBg       = isDark ? const Color(0xFF2C2C2E) : _kBg;
    final cardBdr      = isDark ? const Color(0xFF38383A) : _kBorder2;
    final nickColor    = isDark ? const Color(0xFFEEEEEE) : _kWhite;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dialogBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(width: 2, height: 16, color: color),
              const SizedBox(width: 10),
              Text(titulo, style: _raj(12, FontWeight.w900, color, spacing: 2)),
              const SizedBox(width: 8),
              Text(nickname.toUpperCase(),
                  style: _raj(12, FontWeight.w700, nickColor)),
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
                    stats['estado']!, color, bgColor: cardBg, borderColor: cardBdr),
                _buildStatCard(Icons.calendar_today_outlined, 'Sin visitar',
                    stats['sinVisitar']!, _kText, bgColor: cardBg, borderColor: cardBdr),
                _buildStatCard(Icons.straighten_outlined, 'Distancia',
                    stats['distancia']!, _kText, bgColor: cardBg, borderColor: cardBdr),
                _buildStatCard(Icons.speed_outlined, 'Vel. media',
                    stats['velMedia']!, _kText, bgColor: cardBg, borderColor: cardBdr),
                _buildStatCard(Icons.timer_outlined, 'Tiempo',
                    stats['tiempo']!, _kText, bgColor: cardBg, borderColor: cardBdr),
                _buildStatCard(Icons.flag_outlined, 'Resultado',
                    titulo, color, bgColor: cardBg, borderColor: cardBdr),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color c, {Color? bgColor, Color? borderColor}) =>
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor ?? _kBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor ?? _kBorder2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: c),
          const Spacer(),
          Text(label, style: _raj(8, FontWeight.w600, _kSub)),
          Text(value, style: _raj(11, FontWeight.w900, c)),
        ]),
      );

  // ── Helpers de estilo ──────────────────────────────────────────────────────
  Color _colorPorTipo(String t) => _kDim;

  IconData _iconoPorTipo(String t) {
    if (t.contains('lost'))                              return Icons.shield_outlined;
    if (t.contains('conquered') || t.contains('steal')) return Icons.flag_rounded;
    if (t == 'follow' || t == 'follow_request')          return Icons.person_add_rounded;
    if (t == 'friend_request')                           return Icons.group_add_outlined;
    if (t == 'friend_accepted')                          return Icons.people_outlined;
    if (t.contains('invasion'))                          return Icons.warning_amber_rounded;
    if (t == 'desafio_recibido')                         return Icons.sports_mma_rounded;
    if (t == 'desafio_aceptado')                         return Icons.sports_mma_rounded;
    if (t == 'desafio_ganado')                           return Icons.emoji_events_rounded;
    if (t == 'desafio_perdido')                          return Icons.sports_mma_rounded;
    if (t == 'post_like')                                return Icons.favorite_rounded;
    if (t == 'post_comment')                             return Icons.chat_bubble_rounded;
    return Icons.notifications_rounded;
  }

  String _labelPorTipo(String t) {
    switch (t) {
      case 'territory_lost':          return 'TERRITORIO PERDIDO';
      case 'territory_conquered':     return 'TERRITORIO CONQUISTADO';
      case 'territory_steal_success': return 'ROBO EXITOSO';
      case 'territory_invasion':      return 'INVASIÓN DETECTADA';
      case 'follow':                  return 'NUEVO SEGUIDOR';
      case 'follow_request':          return 'SOLICITUD DE SEGUIMIENTO';
      case 'friend_request':          return 'SOLICITUD DE AMISTAD';
      case 'friend_accepted':         return 'SOLICITUD ACEPTADA';
      case 'desafio_recibido':        return 'DESAFÍO RECIBIDO';
      case 'desafio_aceptado':        return 'DESAFÍO ACEPTADO';
      case 'desafio_ganado':          return 'DESAFÍO GANADO';
      case 'desafio_perdido':         return 'DESAFÍO PERDIDO';
      case 'post_like':               return 'ME GUSTA';
      case 'post_comment':            return 'COMENTARIO';
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
            label: '  ACEPTAR',
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
          _datoCeldaDesafio('$apuesta ', 'APUESTA'),
          Container(width: 1, height: 28, color: _kBorder2),
          _datoCeldaDesafio('${horas}h', 'DURACIÓN'),
          Container(width: 1, height: 28, color: _kBorder2),
          _datoCeldaDesafio('${apuesta * 2} ', 'PREMIO'),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _botonDesafio(
          label: '  ACEPTAR',
          color: _kRed,
          filled: true,
          onTap: () => _aceptarDesafio(item, apuesta, horas, desafioId),
        )),
        const SizedBox(width: 6),
        Expanded(child: _botonDesafio(
          label: '  NEGOCIAR',
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
      AppButton(
        label: label,
        onTap: onTap,
        variant: filled ? AppButtonVariant.primary : AppButtonVariant.secondary,
        color: color,
        fontSize: 10,
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
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final sheetBg    = isDark ? const Color(0xFF1C1C1E) : _kSurface;
    final controlBg  = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final controlBdr = isDark ? const Color(0xFF38383A) : _kBorder2;
    final titleColor = isDark ? const Color(0xFFEEEEEE) : _kWhite;
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
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
                  style: _raj(13, FontWeight.w900, titleColor, spacing: 2)),
            ]),
            const SizedBox(height: 6),
            Text('Propón tus condiciones al rival',
                style: _raj(12, FontWeight.w500, _kSub)),
            const SizedBox(height: 24),
            // Apuesta
            _buildInputControl(
              label: 'APUESTA',
              value: '$apuesta ',
              sub: 'Tienes $misMonedas  disponibles',
              bgColor: controlBg,
              borderColor: controlBdr,
              titleColor: titleColor,
              onMinus: () => setModal(() => apuesta = (apuesta - 25).clamp(25, misMonedas)),
              onPlus:  () => setModal(() => apuesta = (apuesta + 25).clamp(25, misMonedas)),
            ),
            const SizedBox(height: 12),
            // Horas
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: controlBg,
                  border: Border.all(color: controlBdr)),
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
                    style: _raj(22, FontWeight.w900, titleColor),
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
                child: Text('  ENVIAR CONTRAPROPUESTA',
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
    Color bgColor = const Color(0xFF101010),
    Color borderColor = _kBorder2,
    Color titleColor = _kWhite,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _raj(9, FontWeight.w700, _kDim, spacing: 2)),
          const SizedBox(height: 12),
          Row(children: [
            GestureDetector(onTap: onMinus,
                child: Container(width: 36, height: 36, color: _kMuted,
                    child: const Icon(Icons.remove, color: Colors.white, size: 16))),
            Expanded(child: Center(child: Text(value,
                style: _raj(28, FontWeight.w900, titleColor)))),
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
        'message':           ' $myNick contrapropone: ${horas}h · $apuesta ',
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
      if (mounted) _snack('Error al enviar la contrapropuesta', Colors.redAccent);
    }
  }

  Future<void> _aceptarDesafio(NotifItem item, int apuesta, int horas,
      String? desafioId) async {
    try {
      final db = FirebaseFirestore.instance;
      final String targetId;
      Map<String, dynamic> data;

      if (desafioId != null) {
        final doc = await db.collection('desafios').doc(desafioId).get();
        if (!doc.exists) return;
        targetId = desafioId;
        data     = doc.data()!;
      } else {
        final snap = await db.collection('desafios')
            .where('retadoId', isEqualTo: userId)
            .where('estado', isEqualTo: 'pendiente')
            .limit(1).get();
        if (snap.docs.isEmpty) return;
        targetId = snap.docs.first.id;
        data     = snap.docs.first.data();
      }

      // Transacción atómica: verificar saldo y descontar en un solo paso
      String myNick = 'Rival';
      await db.runTransaction((tx) async {
        final snap       = await tx.get(db.collection('players').doc(userId));
        myNick           = snap.data()?['nickname'] as String? ?? 'Rival';
        final misMonedas = (snap.data()?['monedas'] as num?)?.toInt() ?? 0;
        if (misMonedas < apuesta) throw 'insufficient_coins';
        tx.update(snap.reference, {'monedas': FieldValue.increment(-apuesta)});
      });

      final ahora = DateTime.now();
      final fin   = ahora.add(Duration(hours: horas));

      await db.collection('desafios').doc(targetId).update({
        'estado':        'activo',
        'apuesta':       apuesta,
        'duracionHoras': horas,
        'inicio':        Timestamp.fromDate(ahora),
        'fin':           Timestamp.fromDate(fin),
        'puntosRetador': 0,
        'puntosRetado':  0,
      });
      await db.collection('notifications').doc(item.id).update({'read': true});

      final retadorId = data['retadorId'] as String;
      final toUserId  = userId == retadorId ? data['retadoId'] : retadorId;

      await db.collection('notifications').add({
        'toUserId':     toUserId,
        'type':         'desafio_aceptado',
        'fromNickname': myNick,
        'desafioId':    targetId,
        'message':      ' $myNick aceptó el desafío · ${horas}h · $apuesta  ¡Empieza ahora!',
        'read':         false,
        'timestamp':    FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _snack('¡Desafío aceptado! Tienes ${horas}h para ganar', _kRed);
        Navigator.pushNamed(context, '/desafios', arguments: {'desafioId': targetId});
      }
    } catch (e) {
      if (e == 'insufficient_coins') {
        if (mounted) _snack('No tienes suficientes monedas', Colors.redAccent);
      } else {
        if (mounted) _snack('Error al aceptar el desafío', Colors.redAccent);
      }
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
      if (mounted) _snack('Error al rechazar el desafío', Colors.redAccent);
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
      if (mounted) _snack('Error al cancelar el desafío', Colors.redAccent);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final appBarFg = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final scaffoldBg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: appBarFg, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('NOTIFICACIONES',
            style: _raj(14, FontWeight.w900, appBarFg, spacing: 3)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1,
              color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8)),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.done_all_rounded, color: isDark ? _kDim : _kSub, size: 20),
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

          final cardBg   = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
          final cardBdr  = isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6);
          final textMain = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF1C1C1E);

          return RefreshIndicator(
            onRefresh: () async {},
            color: _kRed,
            child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
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
                        ? cardBg
                        : color.withValues(alpha: isDark ? 0.10 : 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(
                          color: item.leida
                              ? cardBdr
                              : color.withValues(alpha: 0.6),
                          width: 2),
                      top: BorderSide(color: cardBdr),
                      right: BorderSide(color: cardBdr),
                      bottom: BorderSide(color: cardBdr),
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
                            textMain)),
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
          ),
          );
        },
      ),
    );
  }
}