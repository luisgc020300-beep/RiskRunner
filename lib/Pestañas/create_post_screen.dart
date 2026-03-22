// lib/Pestañas/CreatePostScreen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/story_service.dart';

// ── Design tokens
class _C {
  static const bg0       = Color(0xFF060606);
  static const bg1       = Color(0xFF0C0C0C);
  static const bg2       = Color(0xFF101010);
  static const parch     = Color(0xFFEEEEEE);   // texto principal — blanco
  static const parchm    = Color(0xFFCC2222);   // acento — rojo
  static const parchd    = Color(0xFF666666);   // texto secundario — gris
  static const bronze    = Color(0xFFCC2222);   // alias rojo
  static const ivory     = Color(0xFFEEEEEE);   // texto blanco
  static const border    = Color(0x1FCCCCCC);   // borde sutil gris
  static const borderHot = Color(0x3FCC2222);   // borde activo rojo
  static const safe      = Color(0xFF4CAF50);
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

  // ── Destino: 'feed' | 'historia'
  String _destino = 'feed';

  // CORREGIDO: tipo usa 'photo' y 'video' para coincidir con StoryViewerScreen
  String  _tipoSeleccionado = 'video';
  File?   _mediaFile;
  String? _mediaBase64;
  bool    _publicando = false;
  String  _errorMsg   = '';

  Color _accentColor = const Color(0xFFCC2222);

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
        // imageQuality: 60 y maxWidth: 800 para que quepa en Firestore (< 1MB)
        file = await picker.pickImage(
            source: source, imageQuality: 60, maxWidth: 800);
      }

      if (file == null) return;

      final bytes = await File(file.path).readAsBytes();

      // Verificar tamaño — Firestore tiene límite de ~1MB por documento
      final kb = bytes.lengthInBytes / 1024;
      if (kb > 900) {
        if (mounted) {
          _showSnack('La imagen es demasiado grande (${kb.toInt()} KB). Máx ~900 KB.');
        }
        return;
      }

      if (mounted) {
        setState(() {
          _mediaFile        = File(file!.path);
          _mediaBase64      = base64Encode(bytes);
          // CORREGIDO: 'photo' en lugar de 'foto' para coincidir con StoryViewerScreen
          _tipoSeleccionado = esVideo ? 'video' : 'photo';
          _errorMsg         = '';
        });
      }
    } catch (e) {
      debugPrint('Error seleccionando media: $e');
      if (mounted) _showSnack('Error al cargar la imagen. Inténtalo de nuevo.');
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
    final pd            = playerDoc.data() ?? {};
    final String  nick  = pd['nickname']    ?? 'Runner';
    final int     niv   = (pd['nivel'] as num?)?.toInt() ?? 1;
    final String? avatar = pd['foto_base64'] as String?;

    await FirebaseFirestore.instance.collection('posts').add({
      'userId':           userId,
      'userNickname':     nick,
      'userNivel':        niv,
      'userAvatarBase64': avatar,
      'tipo':             _tipoSeleccionado, // 'photo' | 'video' | 'texto'
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
      tipo:        _tipoSeleccionado, // 'photo' | 'video'
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
          color: _C.bg2,
          border: Border.all(color: _C.parchd.withOpacity(0.5)),
          boxShadow: [BoxShadow(
              color: _C.parchm.withOpacity(0.15), blurRadius: 16)],
        ),
        child: Text(msg,
            style: const TextStyle(
                color: _C.parch,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1)),
      ),
    ));
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg0,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── SELECTOR FEED / HISTORIA
              _buildDestinoSelector(),
              const SizedBox(height: 20),

              // ── TIPO DE CONTENIDO
              _buildTipoSelector(),
              const SizedBox(height: 24),

              if (_tipoSeleccionado != 'texto') _buildMediaArea(),
              if (_tipoSeleccionado != 'texto') const SizedBox(height: 24),

              _buildSectionLabel('TÍTULO'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _tituloCtrl,
                hint: 'Ej: Mi ruta favorita por Granada...',
                maxLength: 80,
              ),
              const SizedBox(height: 20),

              if (_destino == 'feed') ...[
                _buildSectionLabel('DESCRIPCIÓN'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _descCtrl,
                  hint: 'Cuéntale a la comunidad sobre esta carrera...',
                  maxLines: 4,
                  maxLength: 400,
                ),
                const SizedBox(height: 28),
                _buildInfoTip(),
              ] else ...[
                const SizedBox(height: 8),
                _buildHistoriaTip(),
              ],
            ],
          ),
      ),
    );
  }

  // ===========================================================================
  // SELECTOR DESTINO
  // ===========================================================================
  Widget _buildDestinoSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        border: Border.all(color: const Color(0x28CC2222)),
      ),
      child: Row(
        children: [
          _destinoTab(id: 'feed',     label: 'FEED',     icon: Icons.dynamic_feed_rounded,  subtitle: 'Publicación permanente'),
          Container(width: 1, height: 56, color: const Color(0x28CC2222)),
          _destinoTab(id: 'historia', label: 'HISTORIA', icon: Icons.auto_stories_rounded,  subtitle: 'Visible 24 horas'),
        ],
      ),
    );
  }

  Widget _destinoTab({
    required String id,
    required String label,
    required IconData icon,
    required String subtitle,
  }) {
    final bool selected = _destino == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _destino = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_accentColor.withOpacity(0.12), _accentColor.withOpacity(0.03)],
                  )
                : null,
            border: Border(
              top: BorderSide(color: selected ? _accentColor : Colors.transparent, width: 2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? _accentColor : _C.parchd),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(
                    color: selected ? _C.parch : _C.parchd,
                    fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  Text(subtitle, style: TextStyle(
                    color: selected ? _accentColor.withOpacity(0.7) : _C.parchd.withOpacity(0.5),
                    fontSize: 9, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // APP BAR
  // ===========================================================================
  PreferredSizeWidget _buildAppBar() {
    final String btnLabel = _destino == 'historia' ? 'Subir' : 'Publicar';
    return AppBar(
      backgroundColor: _C.bg0,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: _C.border)),
          child: const Icon(Icons.close_rounded, color: _C.parchd, size: 16),
        ),
      ),
      title: Text(
        _destino == 'historia' ? 'NUEVA HISTORIA' : 'NUEVA PUBLICACIÓN',
        style: const TextStyle(
          color: _C.parch, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent, Color(0x3FCC2222), Colors.transparent])),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
          child: _publicando
              ? SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(color: _accentColor, strokeWidth: 2))
              : GestureDetector(
                  onTap: _publicar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accentColor, borderRadius: BorderRadius.circular(2)),
                    child: Text(btnLabel, style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900,
                      fontSize: 12, letterSpacing: 1)),
                  ),
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TIPO SELECTOR
  // ===========================================================================
  Widget _buildTipoSelector() {
    // CORREGIDO: ids usan 'photo' en lugar de 'foto'
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
      children: tipos.map((t) {
        final isActive = _tipoSeleccionado == t['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _tipoSeleccionado = t['id'] as String;
              _mediaFile        = null;
              _mediaBase64      = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_accentColor.withOpacity(0.12), _accentColor.withOpacity(0.04)],
                      )
                    : null,
                color: isActive ? null : _C.bg1,
                border: Border.all(
                  color: isActive ? _accentColor.withOpacity(0.7) : _C.border,
                  width: isActive ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t['icon'] as IconData,
                      color: isActive ? _accentColor : _C.parchd, size: 20),
                  const SizedBox(height: 5),
                  Text(t['label'] as String, style: TextStyle(
                    color: isActive ? _accentColor : _C.parchd,
                    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ],
              ),
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
          onTap: _mostrarOpcionesMedia,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _C.bg1,
              border: Border.all(
                color: _mediaBase64 != null
                    ? _accentColor.withOpacity(0.4)
                    : _C.border,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: _mediaBase64 != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(fit: StackFit.expand, children: [
                      // CORREGIDO: comparar con 'photo' en lugar de 'foto'
                      if (_tipoSeleccionado == 'photo')
                        Image.memory(base64Decode(_mediaBase64!), fit: BoxFit.cover)
                      else
                        Container(
                          color: _C.bg1,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_rounded, color: _accentColor, size: 48),
                                const SizedBox(height: 8),
                                const Text('Video listo',
                                    style: TextStyle(color: _C.parchd, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        top: 10, right: 10,
                        child: GestureDetector(
                          onTap: _mostrarOpcionesMedia,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _C.bg0.withOpacity(0.85),
                              border: Border.all(color: _C.border),
                            ),
                            child: const Icon(Icons.edit_rounded, color: _C.parchm, size: 14),
                          ),
                        ),
                      ),
                    ]),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _C.parchd.withOpacity(0.06),
                          border: Border.all(color: _C.border),
                        ),
                        child: Icon(
                          _tipoSeleccionado == 'video'
                              ? Icons.videocam_outlined
                              : Icons.add_photo_alternate_outlined,
                          color: _C.parchd, size: 36,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _tipoSeleccionado == 'video'
                            ? 'Toca para grabar o subir video'
                            : 'Toca para hacer o subir foto',
                        style: const TextStyle(
                            color: _C.parchm, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _destino == 'historia'
                            ? 'La historia estará visible 24 horas'
                            : 'Máx. 10 min para videos',
                        style: const TextStyle(color: _C.parchd, fontSize: 11),
                      ),
                    ],
                  ),
          ),
        ),
        // Aviso de tamaño si hay error
        if (_errorMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_errorMsg,
                style: const TextStyle(color: Color(0xFFE05050), fontSize: 11)),
          ),
      ],
    );
  }

  void _mostrarOpcionesMedia() {
    final esVideo = _tipoSeleccionado == 'video';
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.bg1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x3FCC2222)))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 3,
                margin: const EdgeInsets.only(bottom: 20), color: _C.border),
            Row(children: [
              Container(width: 3, height: 14, color: _C.parchm),
              const SizedBox(width: 10),
              Text(esVideo ? 'SUBIR VIDEO' : 'SUBIR FOTO',
                  style: const TextStyle(
                      color: _C.parch, fontSize: 11,
                      fontWeight: FontWeight.w900, letterSpacing: 2.5)),
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
              icon: esVideo ? Icons.video_library_rounded : Icons.photo_library_rounded,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _C.bg2, border: Border.all(color: _C.border)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: _C.parchd.withOpacity(0.08),
            child: Icon(icon, color: _C.parchm, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                  color: _C.ivory, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: _C.parchd, fontSize: 11)),
            ],
          )),
          const Icon(Icons.chevron_right_rounded, color: _C.parchd, size: 16),
        ]),
      ),
    );
  }

  // ===========================================================================
  // CAMPOS TEXTO
  // ===========================================================================
  Widget _buildSectionLabel(String text) {
    return Row(children: [
      Container(width: 3, height: 12, color: _C.parchm),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(
          color: _C.parchm, fontSize: 9,
          fontWeight: FontWeight.w900, letterSpacing: 2.5)),
    ]);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: _C.ivory, fontSize: 14, height: 1.4),
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _C.parchd, fontSize: 13),
        filled: true,
        fillColor: _C.bg1,
        counterStyle: const TextStyle(color: _C.parchd, fontSize: 10),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0x1FCCCCCC))),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0x1FCCCCCC))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _accentColor.withOpacity(0.6), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        color: _C.parchd.withOpacity(0.04),
        border: Border.all(color: _C.border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            color: _C.parchd.withOpacity(0.08),
            child: const Icon(Icons.lightbulb_outline_rounded, color: _C.parchm, size: 14)),
          const SizedBox(width: 12),
          const Expanded(child: Text(
            'Para videos tipo vlog: edítalos fuera de la app y '
            'súbelos desde la galería. Los posts de carrera con GPS '
            'los puedes compartir directamente desde la pantalla de Resumen.',
            style: TextStyle(color: _C.parchd, fontSize: 12, height: 1.5))),
        ],
      ),
    );
  }

  Widget _buildHistoriaTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.04),
        border: Border.all(color: _accentColor.withOpacity(0.2))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            color: _accentColor.withOpacity(0.08),
            child: Icon(Icons.auto_stories_rounded, color: _accentColor, size: 14)),
          const SizedBox(width: 12),
          Expanded(child: Text(
            'Las historias desaparecen automáticamente a las 24 horas. '
            'Tus amigos verán un anillo de color en tu avatar cuando '
            'tengas una historia activa.',
            style: TextStyle(
                color: _accentColor.withOpacity(0.8), fontSize: 12, height: 1.5))),
        ],
      ),
    );
  }
}