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

  String? _tipChat;
  String? _initiatorId;
  bool    _esMutual = false;

  bool get _esSolicitudRecibida =>
      _tipChat == 'solicitud' && _initiatorId != null && _initiatorId != widget.currentUserId;

  @override
  void initState() {
    super.initState();
    final sorted = [widget.currentUserId, widget.friendId]..sort();
    _chatId = sorted.join('_');
    _chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    _msgsRef = _chatRef.collection('messages');
    _marcarLeido();
    _cargarEstadoChat();
  }

  Future<void> _cargarEstadoChat() async {
    final chatSnap = await _chatRef.get();
    if (chatSnap.exists) {
      final d = chatSnap.data() as Map<String, dynamic>;
      if (mounted) { setState(() {
        _tipChat     = d['tipo'] as String? ?? 'normal';
        _initiatorId = d['initiatorId'] as String?;
      }); }
    } else {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('follows')
            .where('followerId',  isEqualTo: widget.currentUserId)
            .where('followingId', isEqualTo: widget.friendId)
            .limit(1).get(),
        db.collection('follows')
            .where('followerId',  isEqualTo: widget.friendId)
            .where('followingId', isEqualTo: widget.currentUserId)
            .limit(1).get(),
      ]);
      if (mounted) {
        setState(() => _esMutual =
            results[0].docs.isNotEmpty && results[1].docs.isNotEmpty);
      }
    }
  }

  Future<void> _aceptarSolicitud() async {
    await _chatRef.update({'tipo': 'normal'});
    if (mounted) setState(() => _tipChat = 'normal');
  }

  Future<void> _ignorarSolicitud() async {
    await _chatRef.set({'deleted_${widget.currentUserId}': true}, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() { _msgCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _marcarLeido() async =>
    _chatRef.set({'unread_${widget.currentUserId}': 0}, SetOptions(merge: true));

  Future<void> _send() async {
    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;
    _msgCtrl.clear();
    final now = FieldValue.serverTimestamp();
    final tipo = _tipChat ?? (_esMutual ? 'normal' : 'solicitud');
    await _msgsRef.add({'senderId': widget.currentUserId, 'text': texto, 'timestamp': now});
    await _chatRef.set({
      'participants':  [widget.currentUserId, widget.friendId],
      'lastMessage':   texto,
      'lastMessageTime': now,
      'lastSenderId':  widget.currentUserId,
      'tipo':          tipo,
      'initiatorId':   _initiatorId ?? widget.currentUserId,
      'unread_${widget.currentUserId}': 0,
      'unread_${widget.friendId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
    if (_tipChat == null) setState(() { _tipChat = tipo; _initiatorId = widget.currentUserId; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
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
        title: const Text('Eliminar conversación',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('El chat con ${widget.friendNickname} se eliminará para ti.',
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Color(0xFFFF453A), fontWeight: FontWeight.w700))),
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

  // ── Helpers de agrupación ─────────────────────────────────────────────────
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _sameGroup(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a['senderId'] != b['senderId']) return false;
    final tsA = (a['timestamp'] as Timestamp?)?.toDate();
    final tsB = (b['timestamp'] as Timestamp?)?.toDate();
    if (tsA == null || tsB == null) return false;
    return tsB.difference(tsA).inMinutes.abs() <= 3;
  }

  // Construye la lista de items (mensajes + separadores de fecha)
  List<_ChatItem> _buildItems(List<QueryDocumentSnapshot> docs) {
    final items = <_ChatItem>[];
    DateTime? lastDay;

    for (int i = 0; i < docs.length; i++) {
      final m    = docs[i].data() as Map<String, dynamic>;
      final ts   = (m['timestamp'] as Timestamp?)?.toDate();
      final day  = ts != null ? DateTime(ts.year, ts.month, ts.day) : null;

      // Separador de fecha
      if (day != null && (lastDay == null || !_sameDay(lastDay, day))) {
        items.add(_DateItem(day));
        lastDay = day;
      }

      final prev = i > 0 ? (docs[i - 1].data() as Map<String, dynamic>) : null;
      final next = i < docs.length - 1 ? (docs[i + 1].data() as Map<String, dynamic>) : null;

      // Si el anterior era de otro día, forzamos inicio de grupo
      final prevDay = prev != null ? (prev['timestamp'] as Timestamp?)?.toDate() : null;
      final prevDifferentDay = prevDay == null || day == null || !_sameDay(prevDay, day);

      final isFirst = prev == null || prevDifferentDay || !_sameGroup(prev, m);
      final isLast  = next == null || !_sameGroup(m, next) ||
          (() {
            final nextDay = (next['timestamp'] as Timestamp?)?.toDate();
            return nextDay == null || day == null || !_sameDay(day, nextDay);
          })();

      items.add(_MsgItem(m, isFirst: isFirst, isLast: isLast));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _p.bg,
    appBar: AppBar(
      backgroundColor: _p.bg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 0.5, color: _p.line),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: _p.text1, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PerfilScreen(targetUserId: widget.friendId),
        )),
        child: Row(children: [
          SocialAvatar(fotoBase64: widget.friendFoto, nickname: widget.friendNickname, size: 36),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.friendNickname,
                style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
            Row(children: [
              Container(width: 6, height: 6,
                  decoration: const BoxDecoration(color: kSocGreenFg, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('EN LÍNEA',
                  style: const TextStyle(
                      color: kSocGreenFg, fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ]),
      ),
      actions: [
        IconButton(
          onPressed: _mostrarOpciones,
          icon: Icon(Icons.more_horiz, color: _p.dim, size: 22),
          padding: EdgeInsets.zero,
        ),
      ],
    ),
    body: Column(children: [
      if (_esSolicitudRecibida)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _p.surface,
            border: Border(bottom: BorderSide(color: _p.line, width: 0.5)),
          ),
          child: Row(children: [
            Expanded(child: Text(
              '${widget.friendNickname} quiere enviarte un mensaje',
              style: TextStyle(color: _p.subtext, fontSize: 12),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _aceptarSolicitud,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: kSocAccent, borderRadius: BorderRadius.circular(20)),
                child: const Text('Aceptar',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _ignorarSolicitud,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: _p.line2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Ignorar', style: TextStyle(color: _p.dim, fontSize: 12)),
              ),
            ),
          ]),
        ),

      // ── Lista de mensajes ──────────────────────────────────────────────
      Expanded(child: StreamBuilder<QuerySnapshot>(
        stream: _msgsRef.orderBy('timestamp', descending: false).snapshots(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: _p.dim, strokeWidth: 1.5)),
            );
          }
          final docs = snapshot.data!.docs;
          if (docs.length > _count) {
            _count = docs.length;
            if (docs.isNotEmpty) {
              final last = docs.last.data() as Map<String, dynamic>;
              if (last['senderId'] != widget.currentUserId) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLeido());
              }
            }
          }

          if (docs.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 60, height: 60,
                decoration: BoxDecoration(
                  color: _p.surface,
                  border: Border.all(color: _p.line2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.chat_bubble_outline_rounded, color: _p.dim, size: 24),
              ),
              const SizedBox(height: 14),
              Text('¡Saluda a ${widget.friendNickname}!',
                  style: TextStyle(color: _p.subtext, fontSize: 13, fontStyle: FontStyle.italic)),
            ]));
          }

          final items = _buildItems(docs);

          return ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              if (item is _DateItem) return _DateSeparator(date: item.date);
              final msg = item as _MsgItem;
              final m = msg.data;
              final esMio = m['senderId'] == widget.currentUserId;
              final ts = (m['timestamp'] as Timestamp?)?.toDate();
              final hora = ts != null
                  ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                  : '';
              return _Bubble(
                texto: m['text'] ?? '',
                esMio: esMio,
                hora: hora,
                isFirst: msg.isFirst,
                isLast: msg.isLast,
              );
            },
          );
        },
      )),

      // ── Barra de entrada ───────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: _p.bg,
          border: Border(top: BorderSide(color: _p.line, width: 0.5)),
        ),
        child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: _p.surface,
              border: Border.all(color: _p.line2),
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: _msgCtrl,
              style: TextStyle(color: _p.text1, fontSize: 14),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Mensaje...',
                hintStyle: TextStyle(color: _p.dim, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: kSocAccent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kSocAccentGlow, blurRadius: 12, spreadRadius: 1)],
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ])),
      ),
    ]),
  );
}

// ── Items de la lista ─────────────────────────────────────────────────────────
abstract class _ChatItem {}

class _DateItem extends _ChatItem {
  final DateTime date;
  _DateItem(this.date);
}

class _MsgItem extends _ChatItem {
  final Map<String, dynamic> data;
  final bool isFirst, isLast;
  _MsgItem(this.data, {required this.isFirst, required this.isLast});
}

// ── Separador de fecha ────────────────────────────────────────────────────────
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String _label() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(date.year, date.month, date.day);
    final diff  = today.difference(d).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    const meses = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    final year  = date.year != now.year ? ' ${date.year}' : '';
    return '${date.day} ${meses[date.month - 1]}$year';
  }

  @override
  Widget build(BuildContext context) {
    final p = SocialPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Expanded(child: Divider(color: p.line2, thickness: 0.5, endIndent: 12)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.line2),
          ),
          child: Text(_label(),
              style: TextStyle(color: p.subtext, fontSize: 10,
                  letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Divider(color: p.line2, thickness: 0.5, indent: 12)),
      ]),
    );
  }
}

// ── Burbuja de mensaje ────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final String texto, hora;
  final bool esMio, isFirst, isLast;

  const _Bubble({
    required this.texto,
    required this.esMio,
    required this.hora,
    required this.isFirst,
    required this.isLast,
  });

  BorderRadius _radius() {
    const full  = Radius.circular(18);
    const small = Radius.circular(4);
    if (esMio) {
      // Burbuja propia (derecha): cola en esquina inferior-derecha
      return BorderRadius.only(
        topLeft:     full,
        topRight:    isFirst ? full : small,
        bottomLeft:  full,
        bottomRight: isLast  ? small : small,
      );
    } else {
      // Burbuja ajena (izquierda): cola en esquina inferior-izquierda
      return BorderRadius.only(
        topLeft:     isFirst ? full : small,
        topRight:    full,
        bottomLeft:  isLast  ? small : small,
        bottomRight: full,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SocialPalette.of(context);
    // Espacio entre burbujas: menos si son del mismo grupo
    final bottomPad = isLast ? 8.0 : 2.0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomPad,
        left:   esMio ? 64 : 0,
        right:  esMio ? 0 : 64,
      ),
      child: Align(
        alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: esMio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: esMio ? kSocAccent : p.surface,
                border: esMio ? null : Border.all(color: p.line2, width: 0.5),
                borderRadius: _radius(),
                boxShadow: esMio
                    ? [BoxShadow(color: kSocAccentGlow, blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Text(texto,
                  style: TextStyle(
                      color: esMio ? Colors.white : p.text1,
                      fontSize: 14,
                      height: 1.4)),
            ),
            // Hora solo en el último mensaje del grupo
            if (isLast && hora.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(hora,
                    style: TextStyle(color: p.dim, fontSize: 9, letterSpacing: 0.3)),
              ),
          ],
        ),
      ),
    );
  }
}
