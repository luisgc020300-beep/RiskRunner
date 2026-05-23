import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/avatar_config.dart';
import '../avatar_widget.dart';
import 'perfil_theme.dart';

// ── API pública ──────────────────────────────────────────────────────────────

void mostrarSeguidores(BuildContext context,
    String viewedUserId, String? myUserId, Color accentColor) {
  _showSocialSheet(
    context: context,
    title: 'Seguidores',
    viewedUserId: viewedUserId,
    myUserId: myUserId,
    accentColor: accentColor,
    esSeguidores: true,
  );
}

void mostrarSiguiendo(BuildContext context,
    String viewedUserId, String? myUserId, Color accentColor) {
  _showSocialSheet(
    context: context,
    title: 'Siguiendo',
    viewedUserId: viewedUserId,
    myUserId: myUserId,
    accentColor: accentColor,
    esSeguidores: false,
  );
}

void mostrarTerritorios(BuildContext context,
    String viewedUserId, Color accentColor) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TerritoriosSheet(
      viewedUserId: viewedUserId,
      accentColor: accentColor,
    ),
  );
}

// ── Sheet social (seguidores / siguiendo) ────────────────────────────────────

void _showSocialSheet({
  required BuildContext context,
  required String title,
  required String viewedUserId,
  required String? myUserId,
  required Color accentColor,
  required bool esSeguidores,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SocialSheet(
      title: title,
      viewedUserId: viewedUserId,
      myUserId: myUserId,
      accentColor: accentColor,
      esSeguidores: esSeguidores,
    ),
  );
}

class _SocialSheet extends StatefulWidget {
  final String title;
  final String viewedUserId;
  final String? myUserId;
  final Color accentColor;
  final bool esSeguidores;

  const _SocialSheet({
    required this.title,
    required this.viewedUserId,
    required this.myUserId,
    required this.accentColor,
    required this.esSeguidores,
  });

  @override
  State<_SocialSheet> createState() => _SocialSheetState();
}

class _SocialSheetState extends State<_SocialSheet> {
  PerfilPalette get _p => PerfilPalette.of(context);

  List<Map<String, dynamic>> _users = [];
  Set<String> _followedByMe = {};
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final db = FirebaseFirestore.instance;
    try {
      // 1. Docs de follows (sin orderBy para evitar índice compuesto)
      final followSnap = await (widget.esSeguidores
          ? db.collection('follows')
              .where('followingId', isEqualTo: widget.viewedUserId)
              .limit(200)
              .get()
          : db.collection('follows')
              .where('followerId', isEqualTo: widget.viewedUserId)
              .limit(200)
              .get());

      if (followSnap.docs.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 2. Extraer UIDs + timestamps, ordenar por más reciente
      final entries = followSnap.docs.map((doc) {
        final d = doc.data();
        final uid = widget.esSeguidores
            ? (d['followerId'] as String? ?? '')
            : (d['followingId'] as String? ?? '');
        final ts = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
        return (uid: uid, ts: ts);
      }).where((e) => e.uid.isNotEmpty).toList()
        ..sort((a, b) => b.ts.compareTo(a.ts));

      final uids = entries.map((e) => e.uid).toList();
      final tsMap = {for (final e in entries) e.uid: e.ts};

      // 3. Datos de players en paralelo (chunks de 30)
      final chunks = <List<String>>[];
      for (int i = 0; i < uids.length; i += 30) {
        chunks.add(uids.sublist(i, (i + 30).clamp(0, uids.length)));
      }
      final snaps = await Future.wait(
        chunks.map((c) =>
            db.collection('players').where(FieldPath.documentId, whereIn: c).get()),
      );
      final result = <Map<String, dynamic>>[];
      for (final s in snaps) {
        for (final doc in s.docs) {
          result.add({'uid': doc.id, '_ts': tsMap[doc.id], ...doc.data()});
        }
      }
      result.sort((a, b) {
        final ta = a['_ts'] as DateTime? ?? DateTime(0);
        final tb = b['_ts'] as DateTime? ?? DateTime(0);
        return tb.compareTo(ta);
      });

      // 4. Mis follows para saber el estado del botón
      Set<String> followedByMe = {};
      if (widget.myUserId != null) {
        final mySnap = await db.collection('follows')
            .where('followerId', isEqualTo: widget.myUserId)
            .get();
        followedByMe = mySnap.docs
            .map((d) => d.data()['followingId'] as String? ?? '')
            .toSet();
      }

      if (mounted) {
        setState(() {
          _users = result;
          _followedByMe = followedByMe;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error social sheet: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(String targetUid) async {
    if (widget.myUserId == null || widget.myUserId == targetUid) return;
    final db = FirebaseFirestore.instance;
    final already = _followedByMe.contains(targetUid);
    setState(() {
      if (already) { _followedByMe.remove(targetUid); }
      else { _followedByMe.add(targetUid); }
    });
    try {
      if (already) {
        final snap = await db.collection('follows')
            .where('followerId', isEqualTo: widget.myUserId)
            .where('followingId', isEqualTo: targetUid)
            .limit(1)
            .get();
        for (final doc in snap.docs) { await doc.reference.delete(); }
      } else {
        await db.collection('follows').add({
          'followerId': widget.myUserId,
          'followingId': targetUid,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      setState(() {
        if (already) { _followedByMe.add(targetUid); }
        else { _followedByMe.remove(targetUid); }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final filtered = _search.isEmpty
        ? _users
        : _users
            .where((u) => (u['nickname'] as String? ?? '')
                .toLowerCase()
                .contains(_search))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: p.border2, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          Text(widget.title,
              style: GoogleFonts.inter(
                  color: p.title, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          // Buscador
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.border2),
              ),
              child: Row(children: [
                const SizedBox(width: 10),
                Icon(Icons.search_rounded, color: p.muted, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.inter(color: p.text, fontSize: 13),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Buscar',
                      hintStyle:
                          GoogleFonts.inter(color: p.muted, fontSize: 13),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) =>
                        setState(() => _search = v.toLowerCase()),
                  ),
                ),
                if (_search.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child:
                          Icon(Icons.close_rounded, color: p.muted, size: 14),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),

          // Lista
          Expanded(
            child: _loading
                ? Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: widget.accentColor, strokeWidth: 1.5),
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                color: p.muted, size: 36),
                            const SizedBox(height: 10),
                            Text(
                              _search.isNotEmpty
                                  ? 'Sin resultados'
                                  : 'Nadie aquí todavía',
                              style: GoogleFonts.inter(
                                  color: p.dim, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final u = filtered[i];
                          final uid = u['uid'] as String? ?? '';
                          return _UserRow(
                            data: u,
                            myUserId: widget.myUserId,
                            accentColor: widget.accentColor,
                            isFollowing: _followedByMe.contains(uid),
                            isSelf: uid == widget.myUserId,
                            onToggleFollow: () => _toggleFollow(uid),
                            p: p,
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

// ── Fila de usuario ──────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? myUserId;
  final Color accentColor;
  final bool isFollowing;
  final bool isSelf;
  final VoidCallback onToggleFollow;
  final PerfilPalette p;

  const _UserRow({
    required this.data,
    required this.myUserId,
    required this.accentColor,
    required this.isFollowing,
    required this.isSelf,
    required this.onToggleFollow,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = (data['nickname'] as String? ?? 'Usuario').toUpperCase();
    final nivel = (data['nivel'] as num?)?.toInt() ?? 1;
    final fotoBase64 = data['fotoBase64'] as String?;
    final avatarRaw = data['avatarConfig'];
    final avatarConfig = avatarRaw is Map<String, dynamic>
        ? AvatarConfig.fromMap(avatarRaw)
        : const AvatarConfig();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        // Avatar
        Container(
          width: 44, height: 44,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: p.surface2),
          child: ClipOval(
            child: fotoBase64 != null
                ? Image.memory(base64Decode(fotoBase64), fit: BoxFit.cover)
                : AvatarWidget(
                    config: avatarConfig, size: 44, fallbackLabel: nickname),
          ),
        ),
        const SizedBox(width: 12),

        // Nombre y nivel
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nickname,
                style: GoogleFonts.inter(
                    color: p.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text('NIV. $nivel',
                style: GoogleFonts.inter(
                    color: p.dim, fontSize: 10, fontWeight: FontWeight.w500)),
          ]),
        ),

        // Botón seguir/siguiendo (no mostrar en perfil propio)
        if (!isSelf && myUserId != null)
          GestureDetector(
            onTap: onToggleFollow,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isFollowing ? Colors.transparent : accentColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isFollowing ? p.border : accentColor),
              ),
              child: Text(
                isFollowing ? 'Siguiendo' : 'Seguir',
                style: GoogleFonts.inter(
                  color: isFollowing ? p.sub : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Sheet de territorios ─────────────────────────────────────────────────────

class _TerritoriosSheet extends StatefulWidget {
  final String viewedUserId;
  final Color accentColor;

  const _TerritoriosSheet(
      {required this.viewedUserId, required this.accentColor});

  @override
  State<_TerritoriosSheet> createState() => _TerritoriosSheetState();
}

class _TerritoriosSheetState extends State<_TerritoriosSheet> {
  PerfilPalette get _p => PerfilPalette.of(context);

  List<Map<String, dynamic>> _territorios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: widget.viewedUserId)
          .limit(200)
          .get();

      final list = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList()
        ..sort((a, b) {
          final ta =
              (a['fecha_creacion'] as Timestamp?)?.toDate() ?? DateTime(0);
          final tb =
              (b['fecha_creacion'] as Timestamp?)?.toDate() ?? DateTime(0);
          return tb.compareTo(ta);
        });

      if (mounted) setState(() { _territorios = list; _loading = false; });
    } catch (e) {
      debugPrint('Error territorios sheet: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: p.border2, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          Text('Territorios',
              style: GoogleFonts.inter(
                  color: p.title, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          Expanded(
            child: _loading
                ? Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: widget.accentColor, strokeWidth: 1.5),
                    ),
                  )
                : _territorios.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.crop_square_rounded,
                                color: p.muted, size: 36),
                            const SizedBox(height: 10),
                            Text('Sin territorios activos',
                                style: GoogleFonts.inter(
                                    color: p.dim, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        separatorBuilder: (_, __) =>
                            Container(height: 0.5, color: p.border2),
                        itemCount: _territorios.length,
                        itemBuilder: (ctx, i) =>
                            _TerritorioRow(data: _territorios[i], p: p),
                      ),
          ),
        ]),
      ),
    );
  }
}

// ── Fila de territorio ───────────────────────────────────────────────────────

class _TerritorioRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final PerfilPalette p;

  const _TerritorioRow({required this.data, required this.p});

  @override
  Widget build(BuildContext context) {
    final colorInt = (data['color'] as num?)?.toInt() ?? 0xFF8B1A1A;
    final color = Color(colorInt);
    final areaM2 = (data['area_m2'] as num?)?.toDouble() ?? 0;
    final ts = data['fecha_creacion'] as Timestamp?;
    final fecha = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '—';
    final modo = data['modo'] as String? ?? '';
    final hp = (data['hp'] as num?)?.toDouble() ?? 0;
    final hpMax = ((data['hpMax'] as num?)?.toDouble() ?? 1).clamp(1, 99999);
    final hpRatio = (hp / hpMax).clamp(0.0, 1.0);

    final areaLabel = areaM2 >= 1000000
        ? '${(areaM2 / 1000000).toStringAsFixed(2)} km²'
        : areaM2 >= 1000
            ? '${(areaM2 / 1000).toStringAsFixed(1)} km²'
            : '${areaM2.toInt()} m²';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        // Color badge
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Icon(Icons.crop_square_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 12),

        // Info
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(areaLabel,
                  style: GoogleFonts.inter(
                      color: p.title,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (modo == 'solitario') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: p.border2),
                  ),
                  child: Text('SOLO',
                      style: GoogleFonts.inter(
                          color: p.dim,
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ],
            ]),
            const SizedBox(height: 5),
            // Barra de HP
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: hpRatio,
                    minHeight: 3,
                    backgroundColor: p.surface2,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${(hpRatio * 100).toInt()}%',
                  style: GoogleFonts.inter(
                      color: p.dim,
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 3),
            Text(fecha,
                style: GoogleFonts.inter(color: p.dim, fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}
