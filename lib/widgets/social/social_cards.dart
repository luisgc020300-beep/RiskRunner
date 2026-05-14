import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/league_service.dart';
import 'social_theme.dart';
import 'social_shared.dart';

// ── Toggle Button ─────────────────────────────────────────────────────────────
class SocialToggleBtn extends StatelessWidget {
  final String label; final IconData? icon;
  final bool active; final Color activeColor; final VoidCallback onTap;
  const SocialToggleBtn({super.key, required this.label, this.icon, required this.active, required this.activeColor, required this.onTap});
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: active ? activeColor.withValues(alpha: 0.08) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) Icon(icon, color: active ? activeColor : p.subtext, size: 13),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: active ? activeColor : p.subtext, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ]))));
  }
}

// ── League Banner ─────────────────────────────────────────────────────────────
class SocialLeagueBanner extends StatelessWidget {
  final LeagueInfo ligaInfo; final int puntosLiga; final Color accent;
  const SocialLeagueBanner({super.key, required this.ligaInfo, required this.puntosLiga, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = SocialPalette.of(context);
    final double progress = LeagueHelper.getProgress(puntosLiga);
    final int faltanPts = LeagueHelper.ptsParaSiguiente(puntosLiga);
    const int segs = 12;
    final int filled = (progress * segs).floor().clamp(0, segs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: p.surface, border: Border.all(color: ligaInfo.color.withValues(alpha: 0.25), width: 1.5),
            borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                color: ligaInfo.color.withValues(alpha: 0.05),
                border: Border(bottom: BorderSide(color: p.line2))),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: ligaInfo.color.withValues(alpha: 0.08),
                    border: Border.all(color: ligaInfo.color.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Icon(ligaInfo.icon, color: ligaInfo.color, size: 28))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: kSocAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    const Text('TEMPORADA ACTIVA',
                      style: TextStyle(color: kSocAccent, fontSize: 8, letterSpacing: 2.5, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Text(ligaInfo.name.toUpperCase(),
                    style: TextStyle(
                      color: ligaInfo.color, fontSize: 22,
                      fontWeight: FontWeight.w900, letterSpacing: 1.5,
                      shadows: [Shadow(color: ligaInfo.color.withValues(alpha: 0.4), blurRadius: 12)])),
                  const SizedBox(height: 2),
                  Text('LIGA ACTUAL', style: TextStyle(color: p.subtext, fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w600)),
                ])),
              ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$puntosLiga',
                    style: TextStyle(color: p.text1, fontSize: 56, fontWeight: FontWeight.w900, height: 0.9, letterSpacing: -3)),
                  Padding(padding: const EdgeInsets.only(bottom: 8, left: 6),
                    child: Text('PTS', style: TextStyle(color: p.subtext, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2))),
                  const Spacer(),
                  if (faltanPts > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: p.surface3, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('$faltanPts', style: TextStyle(color: p.text1, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        Text('PARA ASCENDER', style: TextStyle(color: p.subtext, fontSize: 7, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                      ])),
                ]),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('PROGRESO', style: TextStyle(color: p.subtext, fontSize: 8, letterSpacing: 3, fontWeight: FontWeight.w700)),
                  Text('${(progress * 100).toInt()}%',
                    style: TextStyle(color: ligaInfo.color, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Row(children: List.generate(segs, (i) {
                  final bool active = i < filled;
                  final bool current = i == filled && progress < 1.0;
                  return Expanded(child: Container(
                    margin: EdgeInsets.only(right: i < segs - 1 ? 3 : 0), height: 5,
                    decoration: BoxDecoration(
                      color: active ? ligaInfo.color.withValues(alpha: 0.75) : current ? ligaInfo.color : p.line2,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: (active || current) ? [BoxShadow(color: ligaInfo.color.withValues(alpha: 0.3), blurRadius: 4)] : null)));
                })),
                const SizedBox(height: 10),
                Text(faltanPts > 0 ? 'Faltan $faltanPts pts para la siguiente liga' : ' Liga máxima alcanzada',
                  style: TextStyle(color: p.text3, fontSize: 10)),
              ])),
          ])),
        Positioned(left: 0, top: 0, bottom: 0,
          child: Container(width: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [ligaInfo.color, ligaInfo.color.withValues(alpha: 0.2)]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14))))),
      ]));
  }
}

// ── Rank Card ─────────────────────────────────────────────────────────────────
class SocialRankCard extends StatelessWidget {
  final int posicion, nivel, monedas, puntosLiga;
  final String nickname;
  final String? fotoBase64;
  final bool esYo;
  final LeagueInfo ligaInfo;
  final Color accent;
  const SocialRankCard({super.key, required this.posicion, required this.nickname, required this.nivel,
    required this.monedas, this.fotoBase64, required this.esYo,
    required this.puntosLiga, required this.ligaInfo, required this.accent});

  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    final Color medal = posicion == 1 ? kSocGold : posicion == 2 ? kSocSilver : posicion == 3 ? kSocBronze : p.line2;
    final bool top3 = posicion <= 3;
    final bool dest = esYo || top3;
    final Color bar = esYo ? kSocAccent : (top3 ? medal : p.line2);
    final double aSize = top3 ? 42.0 : 35.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: top3 ? 14 : 10),
            decoration: BoxDecoration(
              color: top3 ? p.surface2 : esYo ? kSocAccent.withValues(alpha: 0.06) : p.surface,
              border: Border.all(color: top3 ? medal.withValues(alpha: 0.2) : esYo ? kSocAccent.withValues(alpha: 0.3) : p.line2),
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 38, child: top3
                ? Text(['','',''][posicion-1], style: TextStyle(fontSize: posicion==1?26:22), textAlign: TextAlign.center)
                : Text('#$posicion', style: TextStyle(color: esYo ? kSocAccent : p.text3, fontWeight: FontWeight.w900, fontSize: 12), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              SocialAvatar(fotoBase64: fotoBase64, nickname: nickname, size: aSize,
                ringColor: top3 ? medal.withValues(alpha: 0.5) : esYo ? kSocAccent.withValues(alpha: 0.6) : ligaInfo.color.withValues(alpha: 0.35),
                glow: top3 || esYo),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname + (esYo ? ' (Tú)' : ''),
                  style: TextStyle(color: p.text1, fontWeight: top3 ? FontWeight.w900 : FontWeight.w600, fontSize: top3 ? 14 : 13),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text('Niv. $nivel', style: TextStyle(color: p.subtext, fontSize: 10)),
                  const SizedBox(width: 6),
                  SocialPill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$puntosLiga',
                  style: TextStyle(color: top3 ? medal : esYo ? kSocAccent : p.text2,
                    fontWeight: FontWeight.w900, fontSize: top3 ? 20 : 15, letterSpacing: -0.5)),
                Text('pts', style: TextStyle(color: p.dim, fontSize: 9)),
              ]),
            ])),
          if (dest)
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(
                width: top3 ? 3 : 2,
                decoration: BoxDecoration(
                  color: bar,
                  boxShadow: top3 ? [BoxShadow(color: bar.withValues(alpha: 0.5), blurRadius: 8)] : null,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))))),
        ])));
  }
}

// ── Simple Rank Card ──────────────────────────────────────────────────────────
class SocialSimpleRankCard extends StatelessWidget {
  final int posicion;
  final String nickname;
  final int nivel;
  final String? fotoBase64;
  final bool esYo;
  final String valor;
  final String unidad;
  final Color color;
  final Color accent;
  final SocialPalette p;

  const SocialSimpleRankCard({super.key,
    required this.posicion, required this.nickname, required this.nivel,
    required this.fotoBase64, required this.esYo, required this.valor,
    required this.unidad, required this.color, required this.accent,
    required this.p,
  });

  @override
  Widget build(BuildContext ctx) {
    final Color medal = posicion == 1 ? kSocGold : posicion == 2 ? kSocSilver : posicion == 3 ? kSocBronze : p.line2;
    final bool top3 = posicion <= 3;
    final bool dest = esYo || top3;
    final Color bar  = esYo ? accent : (top3 ? medal : color);
    final double aSize = top3 ? 42.0 : 35.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: top3 ? 14 : 10),
            decoration: BoxDecoration(
              color: top3 ? p.surface2 : esYo ? accent.withValues(alpha: 0.06) : p.surface,
              border: Border.all(color: top3 ? medal.withValues(alpha: 0.2) : esYo ? accent.withValues(alpha: 0.3) : p.line2),
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 38,
                child: Text('#$posicion',
                  style: TextStyle(
                    color: top3 ? medal : esYo ? accent : p.text3,
                    fontWeight: FontWeight.w900,
                    fontSize: top3 ? (posicion == 1 ? 15 : 13) : 12),
                  textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              SocialAvatar(fotoBase64: fotoBase64, nickname: nickname, size: aSize,
                ringColor: top3 ? medal.withValues(alpha: 0.5) : esYo ? accent.withValues(alpha: 0.6) : color.withValues(alpha: 0.35),
                glow: top3 || esYo),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname + (esYo ? ' (Tú)' : ''),
                  style: TextStyle(color: p.text1, fontWeight: top3 ? FontWeight.w900 : FontWeight.w600, fontSize: top3 ? 14 : 13),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('Niv. $nivel', style: TextStyle(color: p.subtext, fontSize: 10)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(valor,
                  style: TextStyle(
                    color: top3 ? medal : esYo ? accent : color,
                    fontWeight: FontWeight.w900, fontSize: top3 ? 20 : 15, letterSpacing: -0.5)),
                Text(unidad, style: TextStyle(color: p.dim, fontSize: 9)),
              ]),
            ])),
          if (dest)
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(
                width: top3 ? 3 : 2,
                decoration: BoxDecoration(
                  color: bar,
                  boxShadow: top3 ? [BoxShadow(color: bar.withValues(alpha: 0.5), blurRadius: 8)] : null,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))))),
        ])));
  }
}

// ── Friend Card ───────────────────────────────────────────────────────────────
class SocialFriendCard extends StatelessWidget {
  final String nickname; final int nivel, monedas, puntosLiga;
  final String? fotoBase64; final Color accent, territorioColor;
  final bool activo;
  final VoidCallback onChat, onPerfil;
  const SocialFriendCard({super.key, required this.nickname, required this.nivel, required this.monedas,
    required this.puntosLiga, this.fotoBase64, required this.accent,
    required this.territorioColor, required this.activo,
    required this.onChat, required this.onPerfil});

  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    final Color tc = territorioColor == p.line2 ? p.dim : territorioColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line2),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Stack(alignment: Alignment.bottomRight, children: [
                SocialAvatar(fotoBase64: fotoBase64, nickname: nickname, size: 46,
                  ringColor: tc.withValues(alpha: 0.55)),
                Container(
                  width: 11, height: 11,
                  decoration: BoxDecoration(
                    color: p.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.bg, width: 1.5)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: activo ? kSocGreenFg : p.dim,
                      shape: BoxShape.circle)),
                ),
              ]),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname, style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    activo ? 'ACTIVO' : 'INACTIVO',
                    style: TextStyle(
                      color: activo ? kSocGreenFg.withValues(alpha: 0.7) : p.dim,
                      fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  Container(width: 1, height: 8, color: p.line2,
                    margin: const EdgeInsets.symmetric(horizontal: 6)),
                  SocialPill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
                ]),
              ])),
              SocialPress(onTap: onPerfil, child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: p.surface3,
                  border: Border.all(color: p.line2),
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.person_outline_rounded, color: p.text3, size: 15))),
              const SizedBox(width: 6),
              SocialPress(onTap: onChat, child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: kSocAccent, borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 10)]),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 15))),
            ])),
          Positioned(left: 0, top: 0, bottom: 0,
            child: Container(width: 3,
              decoration: BoxDecoration(
                color: tc.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
        ])));
  }
}

// ── Chat Card ─────────────────────────────────────────────────────────────────
class SocialChatCard extends StatelessWidget {
  final String chatId, nickname; final String? fotoBase64;
  final String lastMessage; final Timestamp? lastTime;
  final int unread; final Color accent; final VoidCallback onTap;
  const SocialChatCard({super.key, required this.chatId, required this.nickname, this.fotoBase64,
    required this.lastMessage, this.lastTime, required this.unread, required this.accent, required this.onTap});

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate(); final now = DateTime.now(); final dif = now.difference(d);
    if (dif.inDays == 0) return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    if (dif.inDays == 1) return 'Ayer';
    if (dif.inDays < 7) return '${dif.inDays}d';
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    final bool h = unread > 0;
    return SocialPress(onTap: onTap, child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: h ? p.surface2 : p.surface,
              border: Border.all(color: h ? kSocAccent.withValues(alpha: 0.3) : p.line2),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              SocialAvatar(fotoBase64: fotoBase64, nickname: nickname, size: 46,
                ringColor: h ? kSocAccent.withValues(alpha: 0.5) : p.line2, glow: h),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nickname, style: TextStyle(color: h ? p.text1 : p.text2,
                  fontWeight: h ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                const SizedBox(height: 4),
                Text(lastMessage.isEmpty ? 'Inicia la conversación' : lastMessage,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: h ? p.text3 : p.subtext, fontSize: 12, fontStyle: FontStyle.italic)),
              ])),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_fmt(lastTime), style: TextStyle(color: h ? kSocAccent.withValues(alpha: 0.8) : p.dim,
                  fontSize: 10, fontWeight: h ? FontWeight.w600 : FontWeight.w400)),
                if (h) ...[const SizedBox(height: 6), SocialPulseBadge(count: unread, color: kSocAccent)],
              ]),
            ])),
          if (h) Positioned(left: 0, top: 0, bottom: 0,
            child: Container(width: 3, decoration: BoxDecoration(
              color: kSocAccent,
              boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 8)],
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
        ]))));
  }
}

// ── Player Card ───────────────────────────────────────────────────────────────
class SocialPlayerCard extends StatefulWidget {
  final String userId, nickname, relacion, currentUserId;
  final int nivel, monedas, rango, puntosLiga;
  final String? fotoBase64;
  final Color accent;
  final VoidCallback onAgregar, onVerPerfil;
  const SocialPlayerCard({super.key,
    required this.userId, required this.nickname, required this.nivel,
    required this.monedas, required this.rango, required this.relacion,
    this.fotoBase64, required this.puntosLiga, required this.accent,
    required this.onAgregar, required this.onVerPerfil,
    required this.currentUserId,
  });
  @override State<SocialPlayerCard> createState() => _SocialPlayerCardState();
}

class _SocialPlayerCardState extends State<SocialPlayerCard> {
  bool _siguiendo = false;
  bool _loadingFollow = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('follows')
          .where('followerId',  isEqualTo: widget.currentUserId)
          .where('followingId', isEqualTo: widget.userId)
          .limit(1).get();
      if (mounted) setState(() => _siguiendo = snap.docs.isNotEmpty);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    setState(() => _loadingFollow = true);
    try {
      if (_siguiendo) {
        final snap = await FirebaseFirestore.instance.collection('follows')
            .where('followerId',  isEqualTo: widget.currentUserId)
            .where('followingId', isEqualTo: widget.userId)
            .limit(1).get();
        for (final d in snap.docs) await d.reference.delete();
        if (mounted) setState(() => _siguiendo = false);
      } else {
        await FirebaseFirestore.instance.collection('follows').add({
          'followerId':  widget.currentUserId,
          'followingId': widget.userId,
          'timestamp':   FieldValue.serverTimestamp(),
        });
        final myDoc = await FirebaseFirestore.instance
            .collection('players').doc(widget.currentUserId).get();
        final nick = myDoc.data()?['nickname'] as String? ?? 'Runner';
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUserId':     widget.userId,
          'type':         'follow',
          'fromUserId':   widget.currentUserId,
          'fromNickname': nick,
          'message':      'ha empezado a seguirte',
          'read':         false,
          'timestamp':    FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() => _siguiendo = true);
      }
    } catch (e) {
      debugPrint('Error follow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          backgroundColor: Colors.redAccent.withValues(alpha: 0.95),
          content: const Row(children: [
            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
            SizedBox(width: 10),
            Text('No se pudo completar la acción',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        ));
      }
    }
    finally { if (mounted) setState(() => _loadingFollow = false); }
  }

  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    final ligaInfo = LeagueHelper.getLeague(widget.puntosLiga);
    return SocialPress(onTap: widget.onVerPerfil, child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        SocialAvatar(fotoBase64: widget.fotoBase64, nickname: widget.nickname, size: 44, ringColor: ligaInfo.color.withValues(alpha: 0.5)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.nickname, style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 5),
          Row(children: [
            SocialPill(label: 'NIV.${widget.nivel}', color: widget.accent),
            const SizedBox(width: 5),
            SocialPill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
          ]),
          const SizedBox(height: 4),
          Text('${widget.monedas}   ·  Rango #${widget.rango}', style: TextStyle(color: p.subtext, fontSize: 10)),
        ])),
        const SizedBox(width: 8),
        SocialPress(
          onTap: _loadingFollow ? null : _toggleFollow,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _siguiendo ? p.surface3 : kSocAccent.withValues(alpha: 0.10),
              border: Border.all(color: _siguiendo ? p.line2 : kSocAccent.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _loadingFollow
                ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: kSocAccent))
                : Text(_siguiendo ? 'SIGUIENDO' : 'SEGUIR',
                    style: TextStyle(
                      color: _siguiendo ? p.subtext : kSocAccent,
                      fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
        ),
        const SizedBox(width: 6),
        SocialRelBtn(relacion: widget.relacion, accent: widget.accent, onAgregar: widget.onAgregar),
      ])));
  }
}

// ── Relation Button ───────────────────────────────────────────────────────────
class SocialRelBtn extends StatelessWidget {
  final String relacion; final Color accent; final VoidCallback onAgregar;
  const SocialRelBtn({super.key, required this.relacion, required this.accent, required this.onAgregar});
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    if (relacion == 'accepted') return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: kSocGreen.withValues(alpha: 0.3), border: Border.all(color: kSocGreenFg.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(6)),
      child: const Text('ALIADO', style: TextStyle(color: kSocGreenFg, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)));
    if (relacion == 'pending') return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: p.surface3, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(6)),
      child: Text('PENDIENTE', style: TextStyle(color: p.subtext, fontSize: 9, fontWeight: FontWeight.w700)));
    return SocialPress(onTap: onAgregar, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: kSocAccent, borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 8)]),
      child: const Text('+ UNIRSE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5))));
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────
class SocialRequestCard extends StatelessWidget {
  final String nickname; final int nivel, puntosLiga;
  final String? fotoBase64; final Color accent; final VoidCallback onAceptar, onRechazar;
  const SocialRequestCard({super.key, required this.nickname, required this.nivel, this.fotoBase64,
    required this.puntosLiga, required this.accent, required this.onAceptar, required this.onRechazar});

  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    final ligaInfo = LeagueHelper.getLeague(puntosLiga);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        SocialAvatar(fotoBase64: fotoBase64, nickname: nickname, size: 44, ringColor: ligaInfo.color.withValues(alpha: 0.5)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nickname, style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 5),
          Row(children: [
            Text('Nivel $nivel', style: TextStyle(color: p.text3, fontSize: 11)),
            const SizedBox(width: 6),
            SocialPill(label: ligaInfo.name, color: ligaInfo.color, leading: Icon(ligaInfo.icon, color: ligaInfo.color, size: 9)),
          ]),
        ])),
        SocialPress(onTap: onRechazar, child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: p.surface3, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.close_rounded, color: p.text3, size: 16))),
        const SizedBox(width: 8),
        SocialPress(onTap: onAceptar, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: kSocAccent, borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 10)]),
          child: const Text('ACEPTAR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)))),
      ]));
  }
}
