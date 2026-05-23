import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../config/env.dart';
import 'perfil_theme.dart';

class PerfilPostsTab extends StatefulWidget {
  final String? viewedUserId;
  final bool isOwnProfile;
  final Color colorTerritorio;

  const PerfilPostsTab({
    super.key,
    required this.viewedUserId,
    required this.isOwnProfile,
    required this.colorTerritorio,
  });

  @override
  State<PerfilPostsTab> createState() => _PerfilPostsTabState();
}

class _PerfilPostsTabState extends State<PerfilPostsTab> {
  PerfilPalette get _p => PerfilPalette.of(context);

  static const _tileUrl =
      'https://api.mapbox.com/styles/v1/${Env.mapboxStyleId}'
      '/tiles/256/{z}/{x}/{y}@2x?access_token=${Env.mapboxPublicToken}';

  // ── Borrar un post ──────────────────────────────────────────────────────────
  Future<void> _borrarPost(BuildContext ctx, String postId) async {
    Navigator.pop(ctx);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sCtx) => _ConfirmDeleteSheet(
        p: _p,
        onConfirm: () async {
          Navigator.pop(sCtx);
          await FirebaseFirestore.instance
              .collection('posts')
              .doc(postId)
              .delete();
        },
        onCancel: () => Navigator.pop(sCtx),
      ),
    );
  }

  // ── Parsear ruta ────────────────────────────────────────────────────────────
  List<LatLng> _parseRoute(dynamic rawRoute) {
    if (rawRoute == null) return [];
    return (rawRoute as List<dynamic>).map((pt) {
      final m = pt as Map;
      return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    }).toList();
  }

  // ── Detail sheet ────────────────────────────────────────────────────────────
  void _mostrarDetallePost(
      BuildContext context, String postId, Map<String, dynamic> data) {
    final p      = _p;
    final dist   = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
    final tiempo = (data['tiempoSegundos'] as num?)?.toInt() ?? 0;
    final vel    = (data['velocidadMedia'] as num?)?.toDouble() ?? 0;
    final desc   = (data['descripcion'] as String? ?? '').trim();
    final titulo = (data['titulo'] as String? ?? '').trim();
    final ts     = data['timestamp'] as Timestamp?;
    final route  = _parseRoute(data['ruta']);
    final mins   = tiempo ~/ 60;
    final secs   = tiempo % 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: p.border2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),

          // Header: título + opciones (solo propio)
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (titulo.isNotEmpty)
                  Text(titulo, style: GoogleFonts.inter(
                      color: p.title, fontSize: 16, fontWeight: FontWeight.w700)),
                if (ts != null)
                  Text(
                    '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}',
                    style: GoogleFonts.inter(
                        color: p.dim, fontSize: 11, fontWeight: FontWeight.w400),
                  ),
              ]),
            ),
            if (widget.isOwnProfile)
              GestureDetector(
                onTap: () => _borrarPost(ctx, postId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFFF3B30).withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFFF3B30), size: 14),
                    const SizedBox(width: 5),
                    Text('Eliminar',
                        style: GoogleFonts.inter(
                            color: const Color(0xFFFF3B30),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 20),

          // Mini mapa con tiles reales
          if (route.length > 1) ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    backgroundColor: const Color(0xFF1A1A1A),
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(route),
                      padding: const EdgeInsets.all(32),
                    ),
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      userAgentPackageName: 'com.example.mi_app',
                    ),
                    PolylineLayer(polylines: [
                      Polyline(
                        points: route,
                        color: widget.colorTerritorio,
                        strokeWidth: 4,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Stats
          Row(children: [
            _postStat(p, '${dist.toStringAsFixed(2)} km', 'DISTANCIA'),
            _postDivider(p),
            _postStat(p,
                '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                'TIEMPO'),
            _postDivider(p),
            _postStat(p, '${vel.toStringAsFixed(1)} km/h', 'VELOCIDAD'),
          ]),

          // Descripción
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 0.5, color: p.border2),
            const SizedBox(height: 12),
            Text(desc, style: GoogleFonts.inter(
                color: p.text, fontSize: 13, height: 1.5)),
          ],
        ]),
      ),
    );
  }

  Widget _postStat(PerfilPalette p, String val, String label) =>
      Expanded(child: Column(children: [
        Text(val,
            style: GoogleFonts.inter(
                color: p.title, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.inter(
                color: p.dim, fontSize: 7,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
      ]));

  Widget _postDivider(PerfilPalette p) => Container(
      width: 0.5, height: 32, color: p.border2,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = _p;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.viewedUserId)
          .orderBy('timestamp', descending: true)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: p.dim, strokeWidth: 1.5)),
            ),
          );
        }
        final posts = snap.data?.docs ?? [];
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.directions_run_rounded, color: p.muted, size: 36),
              const SizedBox(height: 12),
              Text(
                widget.isOwnProfile
                    ? 'Comparte tus carreras'
                    : 'Sin publicaciones aún',
                style: perfilStyle(14, FontWeight.w600, p.sub),
              ),
              if (widget.isOwnProfile) ...[
                const SizedBox(height: 6),
                Text(
                  'Al terminar una carrera puedes publicarla en el feed',
                  style: perfilStyle(11, FontWeight.w400, p.dim),
                  textAlign: TextAlign.center,
                ),
              ],
            ]),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2,
          ),
          itemCount: posts.length,
          itemBuilder: (ctx, i) {
            final doc  = posts[i];
            final data = (doc.data() ?? {}) as Map<String, dynamic>;
            return _buildPostCell(context, doc.id, data, p);
          },
        );
      },
    );
  }

  Widget _buildPostCell(BuildContext context, String postId,
      Map<String, dynamic> data, PerfilPalette p) {
    final dist = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
    final ts   = data['timestamp'] as Timestamp?;
    final date = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year % 100}'
        : '';
    final route = _parseRoute(data['ruta']);

    // Offset route para el painter (sin tiles, solo la forma)
    final offsetRoute = (data['ruta'] as List<dynamic>?)?.map((pt) {
      final m = pt as Map;
      return Offset((m['lng'] as num).toDouble(), (m['lat'] as num).toDouble());
    }).toList() ?? <Offset>[];

    return GestureDetector(
      onTap: () => _mostrarDetallePost(context, postId, data),
      child: Container(
        color: const Color(0xFF141414),
        child: Stack(fit: StackFit.expand, children: [
          // Fondo: mapa con tiles reales si hay ruta
          if (route.length > 1)
            FlutterMap(
              options: MapOptions(
                backgroundColor: const Color(0xFF141414),
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(route),
                  padding: const EdgeInsets.all(12),
                ),
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: 'com.example.mi_app',
                ),
                PolylineLayer(polylines: [
                  Polyline(
                    points: route,
                    color: widget.colorTerritorio,
                    strokeWidth: 2,
                  ),
                ]),
              ],
            )
          else if (offsetRoute.length > 1)
            CustomPaint(
                painter: _RouteMiniPainter(offsetRoute, widget.colorTerritorio)),
          // Gradiente inferior para texto
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 6, left: 7,
            child: Text('${dist.toStringAsFixed(1)} km',
                style: perfilStyle(11, FontWeight.w800, Colors.white))),
          Positioned(
            top: 6, right: 6,
            child: Text(date,
                style: perfilStyle(8, FontWeight.w500,
                    Colors.white.withValues(alpha: 0.7)))),
        ]),
      ),
    );
  }
}

// ── Confirmación de borrado ─────────────────────────────────────────────────
class _ConfirmDeleteSheet extends StatelessWidget {
  final PerfilPalette p;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ConfirmDeleteSheet({
    required this.p,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: p.border2, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: Color(0xFFFF3B30), size: 28),
        ),
        const SizedBox(height: 16),
        Text('Eliminar publicación',
            style: GoogleFonts.inter(
                color: p.title, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Esta acción no se puede deshacer.\n¿Seguro que quieres eliminarla?',
            style: GoogleFonts.inter(
                color: p.sub, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onConfirm,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text('Eliminar',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onCancel,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.border2),
            ),
            child: Text('Cancelar',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: p.text, fontSize: 15, fontWeight: FontWeight.w500)),
          ),
        ),
      ]),
    );
  }
}

// ── Painter de fallback (cuando no hay coordenadas GPS válidas) ─────────────
class _RouteMiniPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  const _RouteMiniPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    double minX = points.map((p) => p.dx).reduce(math.min);
    double maxX = points.map((p) => p.dx).reduce(math.max);
    double minY = points.map((p) => p.dy).reduce(math.min);
    double maxY = points.map((p) => p.dy).reduce(math.max);
    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    if (rangeX == 0 || rangeY == 0) return;
    final pad = size.width * 0.12;
    final scale = math.min(
      (size.width - pad * 2) / rangeX,
      (size.height - pad * 2) / rangeY,
    );
    final offX = pad + (size.width  - pad * 2 - rangeX * scale) / 2;
    final offY = pad + (size.height - pad * 2 - rangeY * scale) / 2;

    Offset norm(Offset p) => Offset(
      offX + (p.dx - minX) * scale,
      size.height - (offY + (p.dy - minY) * scale),
    );

    final path = Path()..moveTo(norm(points[0]).dx, norm(points[0]).dy);
    for (int i = 1; i < points.length; i++) {
      final n = norm(points[i]);
      path.lineTo(n.dx, n.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_RouteMiniPainter old) => false;
}
