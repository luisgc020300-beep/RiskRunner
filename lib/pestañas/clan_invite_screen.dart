// lib/Pestañas/clan_invite_screen.dart
// ═══════════════════════════════════════════════════════════
//  CLAN INVITE SCREEN — Invitaciones + buscar amigos para invitar
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/clan_service.dart';

const _kAccent = Color(0xFFE02020);

class _CP {
  final Color bg, surface, line, line2, dim, subtext, text;
  const _CP._({
    required this.bg,
    required this.surface,
    required this.line,
    required this.line2,
    required this.dim,
    required this.subtext,
    required this.text,
  });
  static const light = _CP._(
    bg:      Color(0xFFE8E8ED),
    surface: Color(0xFFFFFFFF),
    line:    Color(0xFFC6C6C8),
    line2:   Color(0xFFD1D1D6),
    dim:     Color(0xFFAEAEB2),
    subtext: Color(0xFF8E8E93),
    text:    Color(0xFF1C1C1E),
  );
  static const dark = _CP._(
    bg:      Color(0xFF090807),
    surface: Color(0xFF1C1C1E),
    line:    Color(0xFF38383A),
    line2:   Color(0xFF2C2C2E),
    dim:     Color(0xFF636366),
    subtext: Color(0xFF8E8E93),
    text:    Color(0xFFEEEEEE),
  );
  static _CP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

class ClanInviteScreen extends StatefulWidget {
  const ClanInviteScreen({super.key});
  @override
  State<ClanInviteScreen> createState() => _ClanInviteScreenState();
}

class _ClanInviteScreenState extends State<ClanInviteScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;
  final _buscarCtrl = TextEditingController();

  List<Map<String, dynamic>> _amigos     = [];
  List<Map<String, dynamic>> _resultados = [];
  bool _cargandoAmigos = true;
  bool _sinResultados  = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargarAmigos();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarAmigos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _cargandoAmigos = false); return; }

    try {
      final fs = FirebaseFirestore.instance;

      final asSender = await fs.collection('friendships')
          .where('senderId', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final asReceiver = await fs.collection('friendships')
          .where('receiverId', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final Set<String> amigoUids = {};
      for (final doc in asSender.docs) {
        final rid = doc.data()['receiverId'] as String?;
        if (rid != null && rid != uid) amigoUids.add(rid);
      }
      for (final doc in asReceiver.docs) {
        final sid = doc.data()['senderId'] as String?;
        if (sid != null && sid != uid) amigoUids.add(sid);
      }

      if (amigoUids.isEmpty) {
        if (mounted) setState(() => _cargandoAmigos = false);
        return;
      }

      final List<Map<String, dynamic>> todos = [];
      final uidList = amigoUids.toList();
      for (var i = 0; i < uidList.length; i += 10) {
        final batch = uidList.sublist(
            i, i + 10 > uidList.length ? uidList.length : i + 10);
        final snap = await fs.collection('players')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final d in snap.docs) {
          todos.add({'uid': d.id, ...d.data()});
        }
      }

      if (mounted) setState(() { _amigos = todos; _cargandoAmigos = false; });
    } catch (e) {
      if (mounted) setState(() => _cargandoAmigos = false);
    }
  }

  void _buscar(String q) {
    if (q.isEmpty) {
      setState(() { _resultados = []; _sinResultados = false; });
      return;
    }
    final lower   = q.toLowerCase();
    final matches = _amigos.where((a) =>
        (a['nickname'] as String? ?? '').toLowerCase().contains(lower)).toList();
    setState(() { _resultados = matches; _sinResultados = matches.isEmpty; });
  }

  @override
  Widget build(BuildContext context) {
    final p = _CP.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('CLANES', style: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w900,
            color: Colors.white, letterSpacing: 3)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _kAccent,
          indicatorWeight: 2,
          labelStyle: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2),
          unselectedLabelColor: const Color(0xFF8E8E93),
          labelColor: Colors.white,
          tabs: const [
            Tab(text: 'INVITACIONES'),
            Tab(text: 'INVITAR AMIGOS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildInvitaciones(p), _buildInvitarAmigos(p)],
      ),
    );
  }

  Widget _buildInvitaciones(_CP p) {
    return StreamBuilder<List<ClanInvite>>(
      stream: ClanService.misInvitacionesPendientes(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2));
        }
        final invites = snap.data ?? [];
        if (invites.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_rounded, size: 52, color: p.dim),
            const SizedBox(height: 16),
            Text('Sin invitaciones pendientes',
                style: GoogleFonts.inter(fontSize: 15, color: p.subtext)),
          ]));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: invites.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _InviteTile(invite: invites[i]),
        );
      },
    );
  }

  Widget _buildInvitarAmigos(_CP p) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _buscarCtrl,
          onChanged: _buscar,
          style: GoogleFonts.inter(color: p.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar amigo por nickname...',
            hintStyle: GoogleFonts.inter(color: p.dim),
            filled: true, fillColor: p.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: p.line2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: p.line2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kAccent)),
            prefixIcon: Icon(Icons.search_rounded, color: p.subtext, size: 18),
            suffixIcon: _buscarCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded, color: p.subtext, size: 16),
                    onPressed: () {
                      _buscarCtrl.clear();
                      setState(() { _resultados = []; _sinResultados = false; });
                    })
                : null,
          ),
        ),
      ),
      Expanded(child: _buildCuerpo(p)),
    ]);
  }

  Widget _buildCuerpo(_CP p) {
    if (_cargandoAmigos) {
      return const Center(
          child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2));
    }

    if (_amigos.isEmpty && _buscarCtrl.text.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.people_rounded, size: 52, color: p.dim),
        const SizedBox(height: 16),
        Text('Aún no tienes amigos',
            style: GoogleFonts.inter(fontSize: 15, color: p.subtext)),
        const SizedBox(height: 4),
        Text('Añade amigos para poder invitarlos a tu clan',
            style: GoogleFonts.inter(fontSize: 11, color: p.dim),
            textAlign: TextAlign.center),
      ]));
    }

    if (_buscarCtrl.text.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_rounded, size: 44, color: p.dim),
        const SizedBox(height: 12),
        Text('Busca a un amigo por su nickname',
            style: GoogleFonts.inter(fontSize: 14, color: p.subtext)),
        const SizedBox(height: 4),
        Text('Solo puedes invitar a jugadores que ya son tus amigos',
            style: GoogleFonts.inter(fontSize: 11, color: p.dim),
            textAlign: TextAlign.center),
      ]));
    }

    if (_sinResultados) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 44, color: p.dim),
        const SizedBox(height: 12),
        Text('Usuario no encontrado',
            style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
        const SizedBox(height: 4),
        Text('Solo puedes invitar a tus amigos',
            style: GoogleFonts.inter(fontSize: 11, color: p.subtext)),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _resultados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _AmigoTile(amigo: _resultados[i]),
    );
  }
}

// ── Tile de amigo para invitar ────────────────────────────
class _AmigoTile extends StatefulWidget {
  final Map<String, dynamic> amigo;
  const _AmigoTile({required this.amigo});
  @override
  State<_AmigoTile> createState() => _AmigoTileState();
}

class _AmigoTileState extends State<_AmigoTile> {
  bool _loading = false;
  bool _enviada = false;

  Future<void> _invitar() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final myDoc  = await FirebaseFirestore.instance
          .collection('players').doc(uid).get();
      final myNick = myDoc.data()?['nickname'] as String? ?? 'Runner';
      final clanId = myDoc.data()?['clanId'] as String?;
      if (clanId == null) throw Exception('No perteneces a ningún clan');

      final clanDoc = await FirebaseFirestore.instance
          .collection('clans').doc(clanId).get();
      final clan = ClanData.fromDoc(clanDoc);

      await ClanService.invitarJugador(
        clan:           clan,
        targetUid:      widget.amigo['uid'] as String,
        targetNickname: widget.amigo['nickname'] as String? ?? '',
        myNickname:     myNick,
      );

      if (mounted) setState(() => _enviada = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''),
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: _kAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p    = _CP.of(context);
    final nick  = widget.amigo['nickname'] as String? ?? '?';
    final nivel = widget.amigo['nivel'] as int? ?? 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kAccent.withValues(alpha: 0.15),
            border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
          ),
          child: Center(child: Text(nick[0].toUpperCase(),
              style: GoogleFonts.inter(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: _kAccent))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nick, style: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
          Text('Nivel $nivel',
              style: GoogleFonts.inter(fontSize: 10, color: p.subtext)),
        ])),
        if (_enviada)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2A5A3A)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_rounded,
                  size: 11, color: Color(0xFF4FA830)),
              const SizedBox(width: 4),
              Text('ENVIADA', style: GoogleFonts.inter(
                  fontSize: 9, fontWeight: FontWeight.w900,
                  color: const Color(0xFF4FA830), letterSpacing: 1)),
            ]),
          )
        else
          GestureDetector(
            onTap: _loading ? null : _invitar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1A3060), _kAccent]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(
                    color: _kAccent.withValues(alpha: 0.25), blurRadius: 8)],
              ),
              child: _loading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('INVITAR', style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w900,
                      color: Colors.white, letterSpacing: 1.5)),
            ),
          ),
      ]),
    );
  }
}

// ── Tile de invitación recibida ───────────────────────────
class _InviteTile extends StatefulWidget {
  final ClanInvite invite;
  const _InviteTile({required this.invite});
  @override
  State<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends State<_InviteTile> {
  bool _loading = false;

  Future<void> _aceptar() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final playerDoc = await FirebaseFirestore.instance
          .collection('players').doc(uid).get();
      final nick = playerDoc.data()?['nickname'] as String? ?? 'Runner';
      final foto = playerDoc.data()?['foto_base64'] as String?;
      await ClanService.aceptarInvitacion(
          invite: widget.invite, myNickname: nick, myFoto: foto);
      if (mounted) _snack('¡Bienvenido al clan!', ok: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rechazar() async {
    await ClanService.rechazarInvitacion(widget.invite.inviteId);
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
      backgroundColor: ok ? const Color(0xFF1A4A35) : _kAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p   = _CP.of(context);
    final inv = widget.invite;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forward_to_inbox_rounded, size: 22, color: _kAccent),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Invitación de ${inv.fromNickname}',
                style: GoogleFonts.inter(fontSize: 11, color: p.subtext)),
            Text('[${inv.clanTag}] ${inv.clanNombre}',
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: _loading ? null : _aceptar,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1A4A35), Color(0xFF2A6A50)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _loading
                  ? const Center(child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)))
                  : Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('ACEPTAR', style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 1.5)),
                    ])),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _rechazar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.line2),
              ),
              child: Icon(Icons.close_rounded, size: 16, color: p.subtext),
            ),
          ),
        ]),
      ]),
    );
  }
}
