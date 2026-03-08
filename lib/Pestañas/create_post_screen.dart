import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  final TextEditingController _tituloCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  String _tipoSeleccionado = 'video';
  File? _mediaFile;
  String? _mediaBase64;
  bool _publicando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarMedia(ImageSource source, bool esVideo) async {
    try {
      final picker = ImagePicker();
      XFile? file;
      if (esVideo) {
        file = await picker.pickVideo(
            source: source, maxDuration: const Duration(minutes: 10));
      } else {
        file = await picker.pickImage(
            source: source, imageQuality: 75, maxWidth: 1080);
      }
      if (file == null) return;
      final bytes = await File(file.path).readAsBytes();
      if (mounted) {
        setState(() {
          _mediaFile = File(file!.path);
          _mediaBase64 = base64Encode(bytes);
          _tipoSeleccionado = esVideo ? 'video' : 'foto';
        });
      }
    } catch (e) {
      debugPrint('Error seleccionando media: $e');
    }
  }

  Future<void> _publicar() async {
    if (userId == null) return;
    if (_tituloCtrl.text.trim().isEmpty && _mediaBase64 == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(_snackOrange('Añade un título o contenido multimedia'));
      return;
    }
    setState(() => _publicando = true);
    try {
      final playerDoc = await FirebaseFirestore.instance
          .collection('players')
          .doc(userId)
          .get();
      final pd = playerDoc.data() ?? {};
      final String nick = pd['nickname'] ?? 'Runner';
      final int niv = (pd['nivel'] as num?)?.toInt() ?? 1;
      final String? avatarB64 = pd['foto_base64'] as String?;

      await FirebaseFirestore.instance.collection('posts').add({
        'userId': userId,
        'userNickname': nick,
        'userNivel': niv,
        'userAvatarBase64': avatarB64,
        'tipo': _tipoSeleccionado,
        'titulo': _tituloCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
        'mediaBase64': _mediaBase64,
        'likes': [],
        'saved': [],
        'comentariosCount': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(_snackOrange('¡Publicado en el feed! 🚀'));
      }
    } catch (e) {
      debugPrint('Error publicando: $e');
      if (mounted) setState(() => _publicando = false);
    }
  }

  SnackBar _snackOrange(String msg) {
    return SnackBar(
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Text(msg,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'NUEVA PUBLICACIÓN',
          style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
            child: _publicando
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.orange, strokeWidth: 2))
                : GestureDetector(
                    onTap: _publicar,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(20)),
                      child: const Text('Publicar',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 13)),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTipoSelector(),
            const SizedBox(height: 24),
            if (_tipoSeleccionado != 'texto') _buildMediaArea(),
            if (_tipoSeleccionado != 'texto') const SizedBox(height: 24),
            _buildLabel('Título'),
            const SizedBox(height: 8),
            TextField(
              controller: _tituloCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration:
                  _inputDecoration('Ej: Mi ruta favorita por Granada...'),
              maxLength: 80,
            ),
            const SizedBox(height: 16),
            _buildLabel('Descripción'),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDecoration(
                  'Cuéntale a la comunidad sobre esta carrera, ruta, experiencia...'),
              maxLines: 4,
              maxLength: 400,
            ),
            const SizedBox(height: 32),
            _buildInfoTip(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoSelector() {
    final tipos = [
      {'id': 'video', 'label': 'Video', 'icon': Icons.videocam_rounded},
      {'id': 'foto', 'label': 'Foto', 'icon': Icons.photo_camera_rounded},
      {'id': 'texto', 'label': 'Texto', 'icon': Icons.edit_rounded},
    ];
    return Row(
      children: tipos.map((t) {
        final isActive = _tipoSeleccionado == t['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _tipoSeleccionado = t['id'] as String;
              _mediaFile = null;
              _mediaBase64 = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.orange.withValues(alpha: 0.12)
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isActive ? Colors.orange : Colors.white12,
                    width: isActive ? 1.5 : 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t['icon'] as IconData,
                      color: isActive ? Colors.orange : Colors.white38,
                      size: 22),
                  const SizedBox(height: 4),
                  Text(t['label'] as String,
                      style: TextStyle(
                          color: isActive ? Colors.orange : Colors.white38,
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w800
                              : FontWeight.w500)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMediaArea() {
    return GestureDetector(
      onTap: _mostrarOpcionesMedia,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _mediaBase64 != null
                  ? Colors.orange.withValues(alpha: 0.4)
                  : Colors.white12),
        ),
        child: _mediaBase64 != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(fit: StackFit.expand, children: [
                  if (_tipoSeleccionado == 'foto')
                    Image.memory(base64Decode(_mediaBase64!), fit: BoxFit.cover)
                  else
                    Container(
                      color: const Color(0xFF0F0F0F),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_rounded,
                                color: Colors.orange, size: 48),
                            SizedBox(height: 8),
                            Text('Video listo',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: _mostrarOpcionesMedia,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.edit_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ]),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _tipoSeleccionado == 'video'
                          ? Icons.videocam_outlined
                          : Icons.add_photo_alternate_outlined,
                      color: Colors.white24,
                      size: 42),
                  const SizedBox(height: 10),
                  Text(
                      _tipoSeleccionado == 'video'
                          ? 'Toca para grabar o subir video'
                          : 'Toca para hacer o subir foto',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('Máx. 10 min para videos',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 11)),
                ],
              ),
      ),
    );
  }

  void _mostrarOpcionesMedia() {
    final esVideo = _tipoSeleccionado == 'video';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    esVideo
                        ? Icons.videocam_rounded
                        : Icons.camera_alt_rounded,
                    color: Colors.orange),
              ),
              title: Text(esVideo ? 'Grabar video' : 'Hacer foto',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: const Text('Usa la cámara ahora',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _seleccionarMedia(ImageSource.camera, esVideo);
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    esVideo
                        ? Icons.video_library_rounded
                        : Icons.photo_library_rounded,
                    color: Colors.white70),
              ),
              title: Text(
                  esVideo ? 'Subir desde galería' : 'Elegir de galería',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: const Text('Vlog, clips de carrera, etc.',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _seleccionarMedia(ImageSource.gallery, esVideo);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: Colors.orange, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Para videos tipo vlog (intro + carrera + despedida): '
              'edítalos fuera de la app y súbelos desde la galería. '
              'Los posts de carrera con GPS los puedes compartir '
              'directamente desde la pantalla de Resumen.',
              style: TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF0F0F0F),
      counterStyle: const TextStyle(color: Colors.white24),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.orange, width: 1.5)),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5));
  }
}