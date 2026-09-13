// lib/pestañas/blocked_users_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  List<String> _bloqueados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = _uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('players').doc(uid).get();
    final raw = (doc.data()?['bloqueados'] as List<dynamic>?) ?? [];
    if (mounted) {
      setState(() {
        _bloqueados = raw.map((e) => e.toString()).toList();
        _cargando   = false;
      });
    }
  }

  Future<void> _desbloquear(String otroUid) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _bloqueados.remove(otroUid));
    try {
      await FirebaseFirestore.instance.collection('players').doc(uid).update({
        'bloqueados': FieldValue.arrayRemove([otroUid]),
      });
    } catch (_) {
      if (mounted) setState(() => _bloqueados.add(otroUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xFF090807) : const Color(0xFFF2F2F7);
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final border  = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD1D1D6);
    final textPri = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF1C1C1E);
    final textSec = isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Usuarios bloqueados',
            style: GoogleFonts.inter(color: textPri, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _bloqueados.isEmpty
              ? Center(
                  child: Text('No has bloqueado a nadie.',
                      style: GoogleFonts.inter(color: textSec, fontSize: 14)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bloqueados.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final otroUid = _bloqueados[i];
                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance.collection('players').doc(otroUid).get(),
                      builder: (_, snap) {
                        final nick = snap.data?.data()?['nickname'] as String? ?? 'Usuario';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border.withValues(alpha: 0.5)),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(nick,
                                  style: GoogleFonts.inter(
                                      color: textPri, fontSize: 15, fontWeight: FontWeight.w500)),
                            ),
                            TextButton(
                              onPressed: () => _desbloquear(otroUid),
                              child: Text('Desbloquear',
                                  style: GoogleFonts.inter(
                                      color: const Color(0xFFCC2222), fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ]),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
