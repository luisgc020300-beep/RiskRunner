// lib/pestañas/create_post_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/story_service.dart';

// ── Adaptive palette
class _CP {
  final Color bg, surface, surface2, surface3;
  final Color line, dim, subtext, text2, text1;
  const _CP._({
    required this.bg, required this.surface,
    required this.surface2, required this.surface3,
    required this.line, required this.dim, required this.subtext,
    required this.text2, required this.text1,
  });
  static const light = _CP._(
    bg: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA),
    surface3: Color(0xFFF2F2F7),
    line: Color(0xFFC6C6C8),
    dim: Color(0xFFAEAEB2),
    subtext: Color(0xFF8E8E93),
    text2: Color(0xFF3C3C43),
    text1: Color(0xFF1C1C1E),
  );
  static const dark = _CP._(
    bg: Color(0xFF090807),
    surface: Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    surface3: Color(0xFF38383A),
    line: Color(0xFF38383A),
    dim: Color(0xFF636366),
    subtext: Color(0xFF8E8E93),
    text2: Color(0xFFD1D1D6),
    text1: Color(0xFFEEEEEE),
  );
  static _CP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  final TextEditingController _tituloCtrl = TextEditingController();
  final TextEditingController _descCtrl   = TextEditingController();

  String  _destino          = 'feed';
  String  _tipoSeleccionado = 'video';
  String? _mediaBase64;
  bool    _publicando       = false;
  String  _errorMsg         = '';

  Color _accentColor = const Color(0xFFE02020);

  _CP get _p => _CP.of(context);

  @override
  void initState() {
    super.initState();
    _loadAccentColor();
  }

  Future<void> _loadAccentColor() async {
    if (userId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('players').doc(userId).get();
    final colorInt = (doc.data()?['territorio_color'] as num?)?.toInt();
    if (colorInt != null && mounted) {
      setState(() => _accentColor = Color(colorInt));
    }
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Seleccionar media ───────────────────────────────────────────────────────
  Future<void> _seleccionarMedia(ImageSource source, bool esVideo) async {
    try {
      final picker = ImagePicker();
      XFile? file;
      if (esVideo) {
        file = await picker.pickVideo(
            source: source, maxDuration: const Duration(minutes: 10));
      } else {
        file = await picker.pickImage(
            source: source, imageQuality: 60, maxWidth: 800);
      }
      if (file == null) return;
      final bytes = await File(file.path).readAsBytes();
      final kb = bytes.lengthInBytes / 1024;
      if (kb > 900) {
        if (mounted) {
          _showSnack('La imagen es demasiado grande (${kb.toInt()} KB). Máx ~900 KB.');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _mediaBase64      = base64Encode(bytes);
          _tipoSeleccionado = esVideo ? 'video' : 'photo';
          _errorMsg         = '';
        });
      }
    } catch (e) {
      debugPrint('Error seleccionando media: $e');
      if (mounted) _showSnack('Error al cargar el archivo. Inténtalo de nuevo.');
    }
  }

  // ── Publicar ────────────────────────────────────────────────────────────────
  Future<void> _publicar() async {
    if (userId == null) return;
    if (_tituloCtrl.text.trim().isEmpty && _mediaBase64 == null) {
      _showSnack('Añade un título o contenido multimedia');
      return;
    }
    setState(() { _publicando = true; _errorMsg = ''; });
    try {
      if (_destino == 'historia') {
        await _publicarComoHistoria();
      } else {
        await _publicarEnFeed();
      }
    } catch (e) {
      debugPrint('Error publicando: $e');
      if (mounted) {
        setState(() { _publicando = false; _errorMsg = 'Error al publicar. Inténtalo de nuevo.'; });
        _showSnack('Error al publicar. Inténtalo de nuevo.');
      }
    }
  }

  Future<void> _publicarEnFeed() async {
    final playerDoc = await FirebaseFirestore.instance
        .collection('players').doc(userId).get();
    final pd             = playerDoc.data() ?? {};
    final String  nick   = pd['nickname']    ?? 'Runner';
    final int     niv    = (pd['nivel'] as num?)?.toInt() ?? 1;
    final String? avatar = pd['foto_base64'] as String?;

    await FirebaseFirestore.instance.collection('posts').add({
      'userId':           userId,
      'userNickname':     nick,
      'userNivel':        niv,
      'userAvatarBase64': avatar,
      'tipo':             _tipoSeleccionado,
      'titulo':           _tituloCtrl.text.trim(),
      'descripcion':      _descCtrl.text.trim(),
      'mediaBase64':      _mediaBase64,
      'likes':            [],
      'saved':            [],
      'comentariosCount': 0,
      'timestamp':        FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pop(context);
      _showSnack('¡Publicado en el feed!');
    }
  }

  Future<void> _publicarComoHistoria() async {
    await StoryService.uploadStory(
      tipo:        _tipoSeleccionado,
      mediaBase64: _mediaBase64,
      caption:     _tituloCtrl.text.trim().isNotEmpty
                       ? _tituloCtrl.text.trim()
                       : _descCtrl.text.trim().isNotEmpty
                           ? _descCtrl.text.trim()
                           : null,
    );
    if (mounted) {
      Navigator.pop(context);
      _showSnack('¡Historia publicada! Visible 24 horas');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _p.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _p.line),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.12), blurRadius: 16)],
        ),
        child: Text(msg, style: GoogleFonts.inter(
            color: _p.text1, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ));
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _p.bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Feed / Historia
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _buildDestinoSelector(),
            ),
            const SizedBox(height: 20),

            // ── Tipo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTipoSelector(),
            ),

            // ── Media
            if (_tipoSeleccionado != 'texto') ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildMediaArea(),
              ),
            ],
            const SizedBox(height: 24),

            // ── Campos (iOS grouped card)
            _buildFieldsCard(),
            const SizedBox(height: 20),

            // ── Tip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _destino == 'feed' ? _buildInfoTip() : _buildHistoriaTip(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // APP BAR — iOS: Cancelar azul | título | Publicar pill
  // ===========================================================================
  PreferredSizeWidget _buildAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg  = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final blue   = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

    return AppBar(
      backgroundColor: barBg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: _p.line.withValues(alpha: 0.6)),
      ),
      leadingWidth: 96,
      leading: TextButton(
        onPressed: () => Navigator.pop(context),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        child: Text('Cancelar', style: GoogleFonts.inter(
            color: blue, fontSize: 15, fontWeight: FontWeight.w400)),
      ),
      title: Text(
        _destino == 'historia' ? 'Nueva historia' : 'Nueva publicación',
        style: GoogleFonts.inter(
            color: _p.text1, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
          child: _publicando
              ? SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: _accentColor, strokeWidth: 2))
              : GestureDetector(
                  onTap: _publicar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accentColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _destino == 'historia' ? 'Subir' : 'Publicar',
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  ),
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // DESTINO SELECTOR — iOS segmented control exacto
  // ===========================================================================
  Widget _buildDestinoSelector() {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final activeBg    = isDark ? const Color(0xFF3A3A3C) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        _destinoTab('feed',     'Feed',     Icons.dynamic_feed_rounded,
            activeBg: activeBg),
        _destinoTab('historia', 'Historia', Icons.auto_stories_rounded,
            activeBg: activeBg),
      ]),
    );
  }

  Widget _destinoTab(String id, String label, IconData icon,
      {required Color activeBg}) {
    final selected = _destino == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _destino = id;
          if (id == 'historia' && _tipoSeleccionado == 'texto') {
            _tipoSeleccionado = 'photo';
            _mediaBase64 = null;
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.09),
                    blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15,
                color: selected ? _accentColor : _p.subtext),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(
              color: selected ? _p.text1 : _p.subtext,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ]),
        ),
      ),
    );
  }

  // ===========================================================================
  // TIPO SELECTOR
  // ===========================================================================
  Widget _buildTipoSelector() {
    final tipos = _destino == 'historia'
        ? [
            {'id': 'photo', 'label': 'Foto',  'icon': Icons.photo_camera_rounded},
            {'id': 'video', 'label': 'Video', 'icon': Icons.videocam_rounded},
          ]
        : [
            {'id': 'video', 'label': 'Video', 'icon': Icons.videocam_rounded},
            {'id': 'photo', 'label': 'Foto',  'icon': Icons.photo_camera_rounded},
            {'id': 'texto', 'label': 'Texto', 'icon': Icons.edit_rounded},
          ];

    return Row(
      children: tipos.asMap().entries.map((entry) {
        final i        = entry.key;
        final t        = entry.value;
        final isActive = _tipoSeleccionado == t['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _tipoSeleccionado = t['id'] as String;
              _mediaBase64 = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: isActive
                    ? _accentColor.withValues(alpha: 0.09)
                    : _p.surface,
                border: Border.all(
                  color: isActive
                      ? _accentColor.withValues(alpha: 0.45)
                      : _p.line.withValues(alpha: 0.6),
                  width: isActive ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: isActive
                    ? [BoxShadow(
                        color: _accentColor.withValues(alpha: 0.12),
                        blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(t['icon'] as IconData,
                    color: isActive ? _accentColor : _p.dim, size: 24),
                const SizedBox(height: 7),
                Text(t['label'] as String, style: GoogleFonts.inter(
                  color: isActive ? _accentColor : _p.subtext,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                )),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ===========================================================================
  // MEDIA AREA
  // ===========================================================================
  Widget _buildMediaArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _mediaBase64 != null ? _mostrarOpcionesMedia : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 210,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _p.surface,
              border: Border.all(
                color: _mediaBase64 != null
                    ? _accentColor.withValues(alpha: 0.5)
                    : _p.line.withValues(alpha: 0.6),
                width: _mediaBase64 != null ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _mediaBase64 != null
                ? _buildMediaPreview()
                : _buildMediaPlaceholder(),
          ),
        ),
        if (_errorMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_errorMsg,
                style: GoogleFonts.inter(
                    color: const Color(0xFFE05050), fontSize: 11)),
          ),
      ],
    );
  }

  Widget _buildMediaPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Stack(fit: StackFit.expand, children: [
        if (_tipoSeleccionado == 'photo')
          Image.memory(base64Decode(_mediaBase64!), fit: BoxFit.cover)
        else
          Container(
            color: _p.surface,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.videocam_rounded,
                      color: _accentColor, size: 36)),
                const SizedBox(height: 12),
                Text('Video seleccionado', style: GoogleFonts.inter(
                    color: _p.text2, fontSize: 14,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Toca para cambiar', style: GoogleFonts.inter(
                    color: _p.subtext, fontSize: 12)),
              ],
            ),
          ),
        // Pill "Cambiar" en esquina
        Positioned(
          top: 10, right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
              const SizedBox(width: 5),
              Text('Cambiar', style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildMediaPlaceholder() {
    final esVideo = _tipoSeleccionado == 'video';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _p.surface2,
            shape: BoxShape.circle,
          ),
          child: Icon(
            esVideo
                ? Icons.videocam_outlined
                : Icons.add_photo_alternate_outlined,
            color: _p.dim, size: 34,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          esVideo ? 'Añadir video' : 'Añadir foto',
          style: GoogleFonts.inter(
              color: _p.text2, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          _destino == 'historia'
              ? 'Visible durante 24 horas'
              : esVideo
                  ? 'Máx. 10 min · cámara o galería'
                  : 'Desde cámara o galería',
          style: GoogleFonts.inter(color: _p.subtext, fontSize: 12)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _mediaActionBtn(
            icon: esVideo
                ? Icons.videocam_rounded
                : Icons.camera_alt_rounded,
            label: 'Cámara',
            onTap: () => _seleccionarMedia(ImageSource.camera, esVideo),
          ),
          const SizedBox(width: 10),
          _mediaActionBtn(
            icon: esVideo
                ? Icons.video_library_rounded
                : Icons.photo_library_rounded,
            label: 'Galería',
            onTap: () => _seleccionarMedia(ImageSource.gallery, esVideo),
          ),
        ]),
      ],
    );
  }

  Widget _mediaActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: _p.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _p.line.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: _p.text2, size: 14),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(
              color: _p.text2, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Bottom sheet para cambiar media ya seleccionada
  void _mostrarOpcionesMedia() {
    final esVideo = _tipoSeleccionado == 'video';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _p.dim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2))),
            Row(children: [
              Container(
                  width: 3, height: 14,
                  color: _p.subtext,
                  margin: const EdgeInsets.only(right: 10)),
              Text(esVideo ? 'CAMBIAR VIDEO' : 'CAMBIAR FOTO',
                  style: GoogleFonts.inter(
                      color: _p.text2, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 2)),
            ]),
            const SizedBox(height: 16),
            _buildMediaOption(
              icon: esVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded,
              title: esVideo ? 'Grabar video' : 'Hacer foto',
              subtitle: 'Usa la cámara ahora',
              onTap: () {
                Navigator.pop(ctx);
                _seleccionarMedia(ImageSource.camera, esVideo);
              },
            ),
            const SizedBox(height: 8),
            _buildMediaOption(
              icon: esVideo
                  ? Icons.video_library_rounded
                  : Icons.photo_library_rounded,
              title: esVideo ? 'Subir desde galería' : 'Elegir de galería',
              subtitle: 'Vlog, clips de carrera, etc.',
              onTap: () {
                Navigator.pop(ctx);
                _seleccionarMedia(ImageSource.gallery, esVideo);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _p.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _p.line.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _p.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _p.text2, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(
                  color: _p.text1, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle, style: GoogleFonts.inter(
                  color: _p.subtext, fontSize: 12)),
            ],
          )),
          Icon(Icons.chevron_right_rounded, color: _p.dim, size: 18),
        ]),
      ),
    );
  }

  // ===========================================================================
  // FIELDS CARD — iOS grouped table view
  // ===========================================================================
  Widget _buildFieldsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _p.line.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldRow(
              label: 'TÍTULO',
              controller: _tituloCtrl,
              hint: 'Ej: Mi ruta favorita por Granada...',
              maxLength: 80,
              maxLines: 1,
            ),
            if (_destino == 'feed') ...[
              Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: _p.line),
              _buildFieldRow(
                label: 'DESCRIPCIÓN',
                controller: _descCtrl,
                hint: 'Cuéntale a la comunidad sobre esta carrera...',
                maxLength: 400,
                maxLines: 4,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    required int maxLength,
    required int maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(
              fontSize: 9, fontWeight: FontWeight.w700,
              color: _p.subtext, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: maxLines,
            maxLength: maxLength,
            style: GoogleFonts.inter(
                color: _p.text1, fontSize: 15, height: 1.4),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: _p.dim, fontSize: 15),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              counterStyle: GoogleFonts.inter(color: _p.dim, fontSize: 10),
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TIPS
  // ===========================================================================
  Widget _buildInfoTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _p.surface2.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _p.line.withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _p.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.lightbulb_outline_rounded,
              color: _p.dim, size: 14)),
        const SizedBox(width: 12),
        Expanded(child: Text(
          'Para videos tipo vlog: edítalos fuera de la app y '
          'súbelos desde la galería. Los posts de carrera con GPS '
          'los puedes compartir directamente desde la pantalla de Resumen.',
          style: GoogleFonts.inter(
              color: _p.subtext, fontSize: 12, height: 1.5))),
      ]),
    );
  }

  Widget _buildHistoriaTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withValues(alpha: 0.18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.auto_stories_rounded,
              color: _accentColor, size: 14)),
        const SizedBox(width: 12),
        Expanded(child: Text(
          'Las historias desaparecen automáticamente a las 24 horas. '
          'Tus amigos verán un anillo de color en tu avatar cuando '
          'tengas una historia activa.',
          style: GoogleFonts.inter(
              color: _accentColor.withValues(alpha: 0.8),
              fontSize: 12, height: 1.5))),
      ]),
    );
  }
}
