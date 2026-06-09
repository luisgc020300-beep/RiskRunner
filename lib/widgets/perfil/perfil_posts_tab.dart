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
  bool _mostrandoGuardados = false;

  static const _tileUrl =
      'https://api.mapbox.com/styles/v1/mapbox/dark-v11'
      '/tiles/256/{z}/{x}/{y}?access_token=${Env.mapboxPublicToken}';

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

  // ── Selector posts / guardados ──────────────────────────────────────────────
  Widget _buildSelector(PerfilPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        _selectorBtn(p, Icons.grid_on_rounded,      !_mostrandoGuardados, () => setState(() => _mostrandoGuardados = false)),
        const SizedBox(width: 8),
        _selectorBtn(p, Icons.bookmark_rounded,      _mostrandoGuardados,  () => setState(() => _mostrandoGuardados = true)),
      ]),
    );
  }

  Widget _selectorBtn(PerfilPalette p, IconData icon, bool active, VoidCallback onTap) {
    final color = active ? p.title : p.dim;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: active ? p.title.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? p.title.withValues(alpha: 0.35) : p.border2),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = _p;

    if (widget.isOwnProfile && _mostrandoGuardados) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _buildSelector(p),
        PerfilSavedTab(uid: widget.viewedUserId!, colorTerritorio: widget.colorTerritorio),
      ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (widget.isOwnProfile) _buildSelector(p),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('userId', isEqualTo: widget.viewedUserId)
            .orderBy('timestamp', descending: true)
            .limit(60)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(child: SizedBox(
                  width: 20, height: 20,
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
                  widget.isOwnProfile ? 'Comparte tus carreras' : 'Sin publicaciones aún',
                  style: perfilStyle(14, FontWeight.w600, p.sub),
                ),
                if (widget.isOwnProfile) ...[
                  const SizedBox(height: 6),
                  Text('Al terminar una carrera puedes publicarla en el feed',
                      style: perfilStyle(11, FontWeight.w400, p.dim),
                      textAlign: TextAlign.center),
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
      ),
    ]);
  }

  Widget _buildPostCell(BuildContext context, String postId,
      Map<String, dynamic> data, PerfilPalette p) {
    final dist     = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
    final ts       = data['timestamp'] as Timestamp?;
    final date     = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year % 100}'
        : '';
    final likes    = (data['likes'] as List<dynamic>?)?.length ?? 0;
    final comments = (data['comentariosCount'] as num?)?.toInt() ?? 0;
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
            bottom: 6, right: 6,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.favorite_rounded,
                  color: Colors.white.withValues(alpha: 0.85), size: 9),
              const SizedBox(width: 2),
              Text('$likes',
                  style: perfilStyle(9, FontWeight.w700,
                      Colors.white.withValues(alpha: 0.85))),
              const SizedBox(width: 5),
              Icon(Icons.chat_bubble_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 9),
              const SizedBox(width: 2),
              Text('$comments',
                  style: perfilStyle(9, FontWeight.w700,
                      Colors.white.withValues(alpha: 0.7))),
            ]),
          ),
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

// ── Tab de publicaciones guardadas ────────────────────────────────────────────
class PerfilSavedTab extends StatefulWidget {
  final String uid;
  final Color colorTerritorio;
  const PerfilSavedTab({super.key, required this.uid, required this.colorTerritorio});
  @override State<PerfilSavedTab> createState() => _PerfilSavedTabState();
}

class _PerfilSavedTabState extends State<PerfilSavedTab> {
  PerfilPalette get _p => PerfilPalette.of(context);

  static const _tileUrl =
      'https://api.mapbox.com/styles/v1/mapbox/dark-v11'
      '/tiles/256/{z}/{x}/{y}?access_token=${Env.mapboxPublicToken}';

  List<LatLng> _parseRoute(dynamic rawRoute) {
    if (rawRoute == null) return [];
    return (rawRoute as List<dynamic>).map((pt) {
      final m = pt as Map;
      return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    }).toList();
  }

  Future<void> _quitarGuardado(String postId) async {
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .update({'saved': FieldValue.arrayRemove([widget.uid])});
  }

  void _mostrarDetalle(BuildContext context, String postId, Map<String, dynamic> data) {
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
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: p.border2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (titulo.isNotEmpty)
                Text(titulo, style: GoogleFonts.inter(
                    color: p.title, fontSize: 16, fontWeight: FontWeight.w700)),
              if (ts != null)
                Text(
                  '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}',
                  style: GoogleFonts.inter(color: p.dim, fontSize: 11)),
            ])),
            GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                await _quitarGuardado(postId);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.border2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bookmark_remove_rounded, color: p.dim, size: 14),
                  const SizedBox(width: 5),
                  Text('Quitar', style: GoogleFonts.inter(
                      color: p.sub, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 20),
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
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.example.mi_app'),
                    PolylineLayer(polylines: [
                      Polyline(points: route, color: widget.colorTerritorio, strokeWidth: 4),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(children: [
            _stat(p, '${dist.toStringAsFixed(2)} km', 'DISTANCIA'),
            Container(width: 0.5, height: 32, color: p.border2, margin: const EdgeInsets.symmetric(horizontal: 4)),
            _stat(p, '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}', 'TIEMPO'),
            Container(width: 0.5, height: 32, color: p.border2, margin: const EdgeInsets.symmetric(horizontal: 4)),
            _stat(p, '${vel.toStringAsFixed(1)} km/h', 'VELOCIDAD'),
          ]),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 0.5, color: p.border2),
            const SizedBox(height: 12),
            Text(desc, style: GoogleFonts.inter(color: p.text, fontSize: 13, height: 1.5)),
          ],
        ]),
      ),
    );
  }

  Widget _stat(PerfilPalette p, String val, String label) =>
      Expanded(child: Column(children: [
        Text(val, style: GoogleFonts.inter(color: p.title, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(color: p.dim, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ]));

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('saved', arrayContains: widget.uid)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(color: p.dim, strokeWidth: 1.5))),
          );
        }
        final posts = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);
        posts.sort((a, b) {
          final ta = ((a.data() as Map)['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
          final tb = ((b.data() as Map)['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
          return tb.compareTo(ta);
        });
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bookmark_border_rounded, color: p.muted, size: 36),
              const SizedBox(height: 12),
              Text('Sin publicaciones guardadas',
                  style: perfilStyle(14, FontWeight.w600, p.sub)),
              const SizedBox(height: 6),
              Text('Guarda publicaciones del feed para verlas aquí',
                  style: perfilStyle(11, FontWeight.w400, p.dim),
                  textAlign: TextAlign.center),
            ]),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: posts.length,
          itemBuilder: (ctx, i) {
            final doc  = posts[i];
            final data = (doc.data() ?? {}) as Map<String, dynamic>;
            final dist = (data['distanciaKm'] as num?)?.toDouble() ?? 0;
            final ts   = data['timestamp'] as Timestamp?;
            final date = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year % 100}'
                : '';
            final route = _parseRoute(data['ruta']);
            final offsetRoute = (data['ruta'] as List<dynamic>?)?.map((pt) {
              final m = pt as Map;
              return Offset((m['lng'] as num).toDouble(), (m['lat'] as num).toDouble());
            }).toList() ?? <Offset>[];

            return GestureDetector(
              onTap: () => _mostrarDetalle(context, doc.id, data),
              child: Container(
                color: const Color(0xFF141414),
                child: Stack(fit: StackFit.expand, children: [
                  if (route.length > 1)
                    FlutterMap(
                      options: MapOptions(
                        backgroundColor: const Color(0xFF141414),
                        initialCameraFit: CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(route),
                          padding: const EdgeInsets.all(12),
                        ),
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.example.mi_app'),
                        PolylineLayer(polylines: [
                          Polyline(points: route, color: widget.colorTerritorio, strokeWidth: 2),
                        ]),
                      ],
                    )
                  else if (offsetRoute.length > 1)
                    CustomPaint(painter: _RouteMiniPainter(offsetRoute, widget.colorTerritorio)),
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                      stops: const [0.45, 1.0]),
                  ))),
                  Positioned(bottom: 6, left: 7,
                      child: Text('${dist.toStringAsFixed(1)} km',
                          style: perfilStyle(11, FontWeight.w800, Colors.white))),
                  Positioned(top: 6, right: 6,
                      child: Text(date,
                          style: perfilStyle(8, FontWeight.w500, Colors.white.withValues(alpha: 0.7)))),
                  Positioned(top: 6, left: 6,
                      child: Icon(Icons.bookmark_rounded,
                          color: Colors.white.withValues(alpha: 0.6), size: 10)),
                ]),
              ),
            );
          },
        );
      },
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
