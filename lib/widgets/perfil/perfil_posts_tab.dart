import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'perfil_theme.dart';

class PerfilPostsTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = PerfilPalette.of(context);
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: viewedUserId)
          .orderBy('timestamp', descending: true)
          .limit(60)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: p.dim, strokeWidth: 1.5))),
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
                isOwnProfile ? 'Comparte tus carreras' : 'Sin publicaciones aún',
                style: perfilStyle(14, FontWeight.w600, p.sub),
              ),
              if (isOwnProfile) ...[
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
            final data = (posts[i].data() ?? {}) as Map<String, dynamic>;
            return _buildPostCell(context, data, p);
          },
        );
      },
    );
  }

  Widget _buildPostCell(BuildContext context, Map<String, dynamic> data, PerfilPalette p) {
    final dist = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
    final ts   = data['timestamp'] as Timestamp?;
    final date = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year % 100}'
        : '';
    final rawRoute = data['ruta'] as List<dynamic>?;
    final route = rawRoute?.map((pt) {
      final m = pt as Map;
      return Offset((m['lng'] as num).toDouble(), (m['lat'] as num).toDouble());
    }).toList() ?? <Offset>[];

    return GestureDetector(
      onTap: () => _mostrarDetallePost(context, data, p),
      child: Container(
        color: p.surface,
        child: Stack(fit: StackFit.expand, children: [
          if (route.length > 1)
            CustomPaint(painter: _RouteMiniPainter(route, colorTerritorio)),
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, p.bg.withValues(alpha: 0.85)],
                stops: const [0.4, 1.0],
              ),
            )),
          ),
          Positioned(bottom: 6, left: 7,
            child: Text('${dist.toStringAsFixed(1)} km',
                style: perfilStyle(11, FontWeight.w800, p.title))),
          Positioned(top: 6, right: 6,
            child: Text(date, style: perfilStyle(8, FontWeight.w500, p.dim))),
        ]),
      ),
    );
  }

  void _mostrarDetallePost(BuildContext context, Map<String, dynamic> data, PerfilPalette p) {
    final dist   = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
    final tiempo = (data['tiempoSegundos'] as num?)?.toInt() ?? 0;
    final vel    = (data['velocidadMedia'] as num?)?.toDouble() ?? 0;
    final desc   = (data['descripcion'] as String? ?? '').trim();
    final ts     = data['timestamp'] as Timestamp?;
    final rawRoute = data['ruta'] as List<dynamic>?;
    final route  = rawRoute?.map((pt) {
      final m = pt as Map;
      return Offset((m['lng'] as num).toDouble(), (m['lat'] as num).toDouble());
    }).toList() ?? <Offset>[];
    final mins = tiempo ~/ 60;
    final secs = tiempo % 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 3,
              decoration: BoxDecoration(
                  color: p.border2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          if (route.length > 1) ...[
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.border2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                    painter: _RouteMiniPainter(route, colorTerritorio,
                        strokeWidth: 2.5)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(children: [
            _postStat(p, '${dist.toStringAsFixed(2)} km', 'DISTANCIA'),
            _postDivider(p),
            _postStat(p,
                '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                'TIEMPO'),
            _postDivider(p),
            _postStat(p, '${vel.toStringAsFixed(1)} km/h', 'VELOCIDAD'),
          ]),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: p.border2),
            const SizedBox(height: 12),
            Text(desc, style: perfilStyle(13, FontWeight.w400, p.text)),
          ],
          if (ts != null) ...[
            const SizedBox(height: 10),
            Text(
              '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}',
              style: perfilStyle(10, FontWeight.w400, p.dim),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _postStat(PerfilPalette p, String val, String label) =>
      Expanded(child: Column(children: [
        Text(val, style: perfilStyle(13, FontWeight.w800, p.title)),
        const SizedBox(height: 2),
        Text(label, style: perfilStyle(7, FontWeight.w700, p.dim, spacing: 1)),
      ]));

  Widget _postDivider(PerfilPalette p) => Container(
      width: 1, height: 32, color: p.border2,
      margin: const EdgeInsets.symmetric(horizontal: 4));
}

// ── Painter privado — solo usado en este tab ──────────────────────────────────
class _RouteMiniPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  const _RouteMiniPainter(this.points, this.color, {this.strokeWidth = 1.5});

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
      ..strokeWidth = strokeWidth + 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_RouteMiniPainter old) => false;
}
