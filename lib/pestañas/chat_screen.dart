import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/social/social_theme.dart';
import '../widgets/social/social_shared.dart';
import 'perfil_screen.dart';

class ChatScreen extends StatefulWidget {
  final String currentUserId, friendId, friendNickname;
  final String? friendFoto;
  const ChatScreen({super.key, required this.currentUserId, required this.friendId,
    required this.friendNickname, this.friendFoto});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  SocialPalette get _p => SocialPalette.of(context);
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final String _chatId;
  late final CollectionReference _msgsRef;
  late final DocumentReference _chatRef;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    final sorted = [widget.currentUserId, widget.friendId]..sort();
    _chatId = sorted.join('_');
    _chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    _msgsRef = _chatRef.collection('messages');
    _marcarLeido();
  }
  @override void dispose() { _msgCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _marcarLeido() async =>
    _chatRef.set({'unread_${widget.currentUserId}': 0}, SetOptions(merge: true));

  Future<void> _send() async {
    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;
    _msgCtrl.clear();
    final now = FieldValue.serverTimestamp();
    await _msgsRef.add({'senderId': widget.currentUserId, 'text': texto, 'timestamp': now});
    await _chatRef.set({
      'participants': [widget.currentUserId, widget.friendId],
      'lastMessage': texto, 'lastMessageTime': now,
      'lastSenderId': widget.currentUserId,
      'unread_${widget.currentUserId}': 0,
      'unread_${widget.friendId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  void _mostrarOpciones() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  _opcionChat(
                    icon: Icons.person_outline_rounded,
                    label: 'Ver perfil de ${widget.friendNickname}',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PerfilScreen(targetUserId: widget.friendId),
                      ));
                    },
                  ),
                  _divOpc(),
                  _opcionChat(
                    icon: Icons.notifications_off_outlined,
                    label: 'Silenciar conversación',
                    onTap: () { Navigator.pop(context); _silenciarConversacion(); },
                  ),
                  _divOpc(),
                  _opcionChat(
                    icon: Icons.mark_chat_unread_outlined,
                    label: 'Marcar como no leído',
                    onTap: () { Navigator.pop(context); _marcarNoLeido(); },
                  ),
                  _divOpc(),
                  _opcionChat(
                    icon: Icons.delete_outline_rounded,
                    label: 'Eliminar conversación',
                    color: const Color(0xFFFF453A),
                    onTap: () { Navigator.pop(context); _confirmarEliminar(); },
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text('Cancelar',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opcionChat({required IconData icon, required String label, required VoidCallback onTap, Color? color}) {
    final c = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: c, fontSize: 16))),
          Icon(icon, color: c, size: 20),
        ]),
      ),
    );
  }

  Widget _divOpc() => const Divider(height: 1, color: Color(0xFF38383A), indent: 18, endIndent: 0);

  Future<void> _silenciarConversacion() async {
    try {
      await _chatRef.set({'muted_${widget.currentUserId}': true}, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Conversación silenciada'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
    } catch (_) {}
  }

  Future<void> _marcarNoLeido() async {
    try {
      await _chatRef.set({'unread_${widget.currentUserId}': 1}, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {}
  }

  Future<void> _confirmarEliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Eliminar conversación', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('El chat con ${widget.friendNickname} se eliminará para ti.',
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Color(0xFFFF453A), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _chatRef.set({'deleted_${widget.currentUserId}': true}, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      backgroundColor: const Color(0xFF0D0D0D), elevation: 0, surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: kSocAccent)),
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 16), onPressed: () => Navigator.pop(context)),
      title: Row(children: [
        SocialAvatar(fotoBase64: widget.friendFoto, nickname: widget.friendNickname, size: 34),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.friendNickname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
          Row(children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: kSocGreenFg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            const Text('EN LÍNEA', style: TextStyle(color: kSocGreenFg, fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ]),
      actions: [
        IconButton(
          onPressed: _mostrarOpciones,
          icon: Icon(Icons.more_horiz, color: _p.dim, size: 20),
          padding: EdgeInsets.zero,
        ),
      ]),
    body: Column(children: [
      Expanded(child: StreamBuilder<QuerySnapshot>(
        stream: _msgsRef.orderBy('timestamp', descending: false).snapshots(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) return Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _p.dim, strokeWidth: 1.5)));
          final msgs = snapshot.data!.docs;
          if (msgs.length > _count) {
            _count = msgs.length;
            if (msgs.isNotEmpty) {
              final last = msgs.last.data() as Map<String, dynamic>;
              if (last['senderId'] != widget.currentUserId)
                WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLeido());
            }
          }
          if (msgs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 56, height: 56,
              decoration: BoxDecoration(color: _p.surface3, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.chat_bubble_outline_rounded, color: _p.dim, size: 22)),
            const SizedBox(height: 14),
            Text('¡Saluda a ${widget.friendNickname}!',
              style: TextStyle(color: _p.subtext, fontSize: 13, fontStyle: FontStyle.italic)),
          ]));
          return ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            itemCount: msgs.length,
            itemBuilder: (ctx, i) {
              final m = msgs[i].data() as Map<String, dynamic>;
              final bool esMio = m['senderId'] == widget.currentUserId;
              final Timestamp? ts = m['timestamp'] as Timestamp?;
              final DateTime? d = ts?.toDate();
              return _Bubble(texto: m['text'] ?? '', esMio: esMio,
                hora: d != null ? '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}' : '');
            });
        })),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(color: _p.bg, border: Border(top: BorderSide(color: _p.line))),
        child: SafeArea(top: false, child: Row(children: [
          Expanded(child: Container(
            decoration: BoxDecoration(color: _p.surface, border: Border.all(color: _p.line2), borderRadius: BorderRadius.circular(10)),
            child: TextField(controller: _msgCtrl,
              style: TextStyle(color: _p.text1, fontSize: 13),
              maxLines: null, textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...', hintStyle: TextStyle(color: _p.dim, fontSize: 13),
                border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11))))),
          const SizedBox(width: 8),
          SocialPress(onTap: _send, child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: kSocAccent, borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 10)]),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 17))),
        ]))),
    ]));
}

// ── Message Bubble ────────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final String texto, hora; final bool esMio;
  const _Bubble({required this.texto, required this.esMio, required this.hora});
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: esMio ? 60 : 0, right: esMio ? 0 : 60),
      child: Align(
        alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: esMio ? p.text1 : p.surface3,
            border: esMio ? null : Border.all(color: p.line2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(esMio ? 14 : 3), bottomRight: Radius.circular(esMio ? 3 : 14))),
          child: Column(
            crossAxisAlignment: esMio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(texto, style: TextStyle(color: esMio ? p.bg : p.text1, fontSize: 13)),
              const SizedBox(height: 4),
              Text(hora, style: TextStyle(color: esMio ? p.bg.withValues(alpha: 0.4) : p.subtext, fontSize: 9)),
            ]))));
  }
}
