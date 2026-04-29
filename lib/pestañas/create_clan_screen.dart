// lib/Pestañas/create_clan_screen.dart
// ═══════════════════════════════════════════════════════════
//  CREATE / EDIT CLAN SCREEN
//  Estética: "Cuartel General" — oscuro, táctico, acero
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/clan_service.dart';

const _kSurface  = Color(0xFFFFFFFF);
const _kLine     = Color(0xFFC6C6C8);
const _kLine2    = Color(0xFFD1D1D6);
const _kDim      = Color(0xFFAEAEB2);
const _kSubtext  = Color(0xFF8E8E93);
const _kWhite    = Color(0xFF1C1C1E);
const _kAccent   = Color(0xFFE02020);

TextStyle _raj(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

// ── Emojis de clan disponibles ────────────────────────────
const _kEmojis = [
  '⚔️','🏴','🔥','💀','🦅','🐺','🦁','🐉',
  '⚡','🌑','🗡️','🛡️','🏹','🎯','💣','🔱',
  '☠️','🦊','🐻','🦂','🐍','🌪️','🌊','🏔️',
];

// ── Colores de clan disponibles ───────────────────────────
const _kClanColors = [
  Color(0xFFCC2222), Color(0xFFD4722A), Color(0xFF3B6BBF),
  Color(0xFF4FA830), Color(0xFFC49430), Color(0xFF8B35CC),
  Color(0xFF2EAAAA), Color(0xFFB03070), Color(0xFF5050B0),
  Color(0xFF7A8A96), Color(0xFF2A9470), Color(0xFFA85820),
];

class CreateClanScreen extends StatefulWidget {
  final ClanData? clanExistente; // null = crear, no null = editar
  const CreateClanScreen({super.key, this.clanExistente});

  @override
  State<CreateClanScreen> createState() => _CreateClanScreenState();
}

class _CreateClanScreenState extends State<CreateClanScreen>
    with SingleTickerProviderStateMixin {

  final _nombreCtrl      = TextEditingController();
  final _tagCtrl         = TextEditingController();
  final _descripcionCtrl = TextEditingController();

  String _emoji      = '⚔️';
  int    _colorValue = 0xFFCC2222;
  bool   _loading    = false;

  late AnimationController _anim;
  late Animation<double>   _fade;

  bool get _esEdicion => widget.clanExistente != null;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();

    if (_esEdicion) {
      final c = widget.clanExistente!;
      _nombreCtrl.text      = c.nombre;
      _tagCtrl.text         = c.tag;
      _descripcionCtrl.text = c.descripcion;
      _emoji                = c.emoji;
      _colorValue           = c.color;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _tagCtrl.dispose();
    _descripcionCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  Color get _color => Color(_colorValue);

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final tag    = _tagCtrl.text.trim().toUpperCase();
    final desc   = _descripcionCtrl.text.trim();

    if (nombre.length < 3) { _snack('El nombre debe tener al menos 3 caracteres'); return; }
    if (tag.length < 2 || tag.length > 5) { _snack('El tag debe tener 2-5 caracteres'); return; }

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      if (_esEdicion) {
        await ClanService.editarClan(
          clanId:      widget.clanExistente!.clanId,
          nombre:      nombre,
          descripcion: desc,
          color:       _colorValue,
          emoji:       _emoji,
        );
        if (mounted) { Navigator.pop(context, true); _snack('Clan actualizado', ok: true); }
      } else {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        final playerDoc = await FirebaseFirestore.instance.collection('players').doc(uid).get();
        final myNickname = playerDoc.data()?['nickname'] as String? ?? 'Runner';
        final myFoto     = playerDoc.data()?['foto_base64'] as String?;

        await ClanService.crearClan(
          nombre:      nombre,
          tag:         tag,
          descripcion: desc,
          color:       _colorValue,
          emoji:       _emoji,
          myNickname:  myNickname,
          myFoto:      myFoto,
        );
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _raj(13, FontWeight.w700, Colors.white)),
      backgroundColor: ok ? const Color(0xFF1A4A35) : _kAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _esEdicion ? 'EDITAR CUARTEL' : 'FUNDAR CLAN',
          style: _raj(13, FontWeight.w900, Colors.white, sp: 3),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kLine),
        ),
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Preview del clan ────────────────────────────
            _buildPreview(),
            const SizedBox(height: 28),

            // ── Emoji ───────────────────────────────────────
            _buildLabel('INSIGNIA'),
            const SizedBox(height: 12),
            _buildEmojiPicker(),
            const SizedBox(height: 24),

            // ── Color ───────────────────────────────────────
            _buildLabel('COLOR DE CLAN'),
            const SizedBox(height: 12),
            _buildColorPicker(),
            const SizedBox(height: 24),

            // ── Nombre ──────────────────────────────────────
            _buildLabel('NOMBRE DEL CLAN'),
            const SizedBox(height: 8),
            _buildField(
              controller: _nombreCtrl,
              hint: 'Los Conquistadores...',
              maxLength: 24,
            ),
            const SizedBox(height: 16),

            // ── Tag ─────────────────────────────────────────
            if (!_esEdicion) ...[
              _buildLabel('TAG  [2-5 CHARS]'),
              const SizedBox(height: 8),
              _buildField(
                controller: _tagCtrl,
                hint: 'RISK',
                maxLength: 5,
                uppercase: true,
              ),
              const SizedBox(height: 4),
              Text(
                'El tag es único e inmutable una vez creado',
                style: _raj(10, FontWeight.w500, _kSubtext),
              ),
              const SizedBox(height: 16),
            ],

            // ── Descripción ──────────────────────────────────
            _buildLabel('DESCRIPCIÓN  (OPCIONAL)'),
            const SizedBox(height: 8),
            _buildField(
              controller: _descripcionCtrl,
              hint: 'Dominamos las calles de...',
              maxLength: 120,
              maxLines: 3,
            ),
            const SizedBox(height: 36),

            // ── Botón guardar ────────────────────────────────
            _buildBotonGuardar(),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  // ── Preview ───────────────────────────────────────────────
  Widget _buildPreview() {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _color.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: _color.withValues(alpha: 0.08), blurRadius: 20),
          ],
        ),
        child: Row(children: [
          // Badge del clan
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _color.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Center(child: Text(_emoji, style: const TextStyle(fontSize: 30))),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '[${_tagCtrl.text.isEmpty ? 'TAG' : _tagCtrl.text.toUpperCase()}]',
                  style: _raj(11, FontWeight.w900, _color, sp: 1),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              _nombreCtrl.text.isEmpty ? 'Nombre del clan' : _nombreCtrl.text,
              style: _raj(18, FontWeight.w900, _kWhite, sp: 0.5),
            ),
            if (_descripcionCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _descripcionCtrl.text,
                style: _raj(11, FontWeight.w400, _kSubtext),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ])),
        ]),
      ),
    );
  }

  // ── Emoji picker ──────────────────────────────────────────
  Widget _buildEmojiPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _kEmojis.map((e) {
        final sel = e == _emoji;
        return GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); setState(() => _emoji = e); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: sel ? _color.withValues(alpha: 0.15) : _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel ? _color : _kLine2,
                width: sel ? 2 : 1,
              ),
            ),
            child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
          ),
        );
      }).toList(),
    );
  }

  // ── Color picker ──────────────────────────────────────────
  Widget _buildColorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _kClanColors.map((c) {
        final sel = c.toARGB32() == _colorValue;
        return GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); setState(() => _colorValue = c.toARGB32()); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: sel ? 44 : 38, height: sel ? 44 : 38,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: sel ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: sel
                  ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)]
                  : [],
            ),
            child: sel
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  // ── Campo texto ───────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    int maxLength = 40,
    int maxLines  = 1,
    bool uppercase = false,
  }) {
    return TextField(
      controller:    controller,
      maxLength:     maxLength,
      maxLines:      maxLines,
      onChanged:     (_) => setState(() {}),
      textCapitalization: uppercase
          ? TextCapitalization.characters
          : TextCapitalization.sentences,
      inputFormatters: uppercase
          ? [UpperCaseTextFormatter()]
          : [],
      style: _raj(15, FontWeight.w600, _kWhite),
      decoration: InputDecoration(
        hintText:      hint,
        hintStyle:     _raj(15, FontWeight.w400, _kDim),
        counterStyle:  _raj(9, FontWeight.w500, _kSubtext),
        filled:        true,
        fillColor:     _kSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kLine2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kLine2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _color, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Row(children: [
    Container(width: 3, height: 12, color: _color,
        margin: const EdgeInsets.only(right: 8)),
    Text(text, style: _raj(9, FontWeight.w800, _kSubtext, sp: 2.5)),
  ]);

  // ── Botón guardar ─────────────────────────────────────────
  Widget _buildBotonGuardar() {
    return GestureDetector(
      onTap: _loading ? null : _guardar,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _color.withValues(alpha: 0.8),
              _color,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: _color.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: _loading
            ? const Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_esEdicion ? '⚔️' : '🏴', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Text(
                  _esEdicion ? 'GUARDAR CAMBIOS' : 'FUNDAR EL CLAN',
                  style: _raj(15, FontWeight.w900, Colors.white, sp: 2),
                ),
              ]),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) =>
      nv.copyWith(text: nv.text.toUpperCase(), selection: nv.selection);
}