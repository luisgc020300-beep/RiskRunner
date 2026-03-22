// lib/widgets/narrador_overlay.dart
//
// Widget que muestra los mensajes del narrador durante la carrera.
// Se coloca encima del mapa, debajo del HUD.
// Aparece con animación, permanece unos segundos y desaparece solo.
//
// Uso en LiveActivity_screen.dart:
//   NarradorOverlay(mensaje: _mensajeNarrador)

import 'package:flutter/material.dart';
import '../services/narrador_service.dart';

class NarradorOverlay extends StatefulWidget {
  final MensajeNarrador? mensaje;

  const NarradorOverlay({super.key, this.mensaje});

  @override
  State<NarradorOverlay> createState() => _NarradorOverlayState();
}

class _NarradorOverlayState extends State<NarradorOverlay>
    with SingleTickerProviderStateMixin {

  late AnimationController _anim;
  late Animation<double>   _fade;
  late Animation<Offset>   _slide;

  MensajeNarrador? _mensajeActual;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

    if (widget.mensaje != null) _mostrar(widget.mensaje!);
  }

  @override
  void didUpdateWidget(NarradorOverlay old) {
    super.didUpdateWidget(old);
    if (widget.mensaje != null && widget.mensaje != old.mensaje) {
      _mostrar(widget.mensaje!);
    }
  }

  void _mostrar(MensajeNarrador msg) async {
    if (!mounted) return;
    // Si hay uno activo, ocultarlo primero
    if (_anim.isAnimating || _anim.value > 0) {
      await _anim.reverse();
    }
    if (!mounted) return;
    setState(() => _mensajeActual = msg);
    _anim.forward();
    // Auto-hide después de la duración configurada
    await Future.delayed(msg.duracion);
    if (!mounted) return;
    if (_mensajeActual == msg) _anim.reverse();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mensajeActual == null) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: _buildCard(_mensajeActual!),
      ),
    );
  }

  Widget _buildCard(MensajeNarrador msg) {
    final colores = _coloresPorTipo(msg.tipo);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colores.fondo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: colores.sombra.withValues(alpha: 0.45),
            blurRadius: 18, offset: const Offset(0, 4)),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Emoji del evento
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: colores.sombra.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: colores.borde.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(msg.emoji,
                  style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          // Texto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _labelPorTipo(msg.tipo).toUpperCase(),
                  style: TextStyle(
                    color: colores.acento.withValues(alpha: 0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  msg.texto,
                  style: TextStyle(
                    color: colores.texto,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: colores.sombra.withValues(alpha: 0.3),
                        blurRadius: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Indicador lateral
          Container(
            width: 3, height: 36,
            margin: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: colores.acento,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(
                  color: colores.acento.withValues(alpha: 0.6), blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }

  _ColorSet _coloresPorTipo(NarradorTipo tipo) {
    switch (tipo) {
      case NarradorTipo.kilometro:
        return _ColorSet(
          fondo:  const Color(0xFF1E1408),
          borde:  const Color(0xFFD4A84C),
          acento: const Color(0xFFD4A84C),
          texto:  const Color(0xFFEDD98A),
          sombra: const Color(0xFFD4A84C),
        );
      case NarradorTipo.conquista:
        return _ColorSet(
          fondo:  const Color(0xFF1A0F00),
          borde:  const Color(0xFFFFD600),
          acento: const Color(0xFFFFD600),
          texto:  Colors.white,
          sombra: const Color(0xFFFFD600),
        );
      case NarradorTipo.territorio:
        return _ColorSet(
          fondo:  const Color(0xFF1A0800),
          borde:  const Color(0xFFD4722A),
          acento: const Color(0xFFD4722A),
          texto:  const Color(0xFFFFD4A0),
          sombra: const Color(0xFFD4722A),
        );
      case NarradorTipo.refuerzo:
        return _ColorSet(
          fondo:  const Color(0xFF0A1A0A),
          borde:  const Color(0xFF8FAF4A),
          acento: const Color(0xFF8FAF4A),
          texto:  const Color(0xFFD4F0A0),
          sombra: const Color(0xFF8FAF4A),
        );
      case NarradorTipo.rival:
        return _ColorSet(
          fondo:  const Color(0xFF071A1A),
          borde:  const Color(0xFF5BA3A0),
          acento: const Color(0xFF5BA3A0),
          texto:  const Color(0xFFB0F0F0),
          sombra: const Color(0xFF5BA3A0),
        );
      case NarradorTipo.resistencia:
        return _ColorSet(
          fondo:  const Color(0xFF1A0F00),
          borde:  const Color(0xFFFF6D00),
          acento: const Color(0xFFFF6D00),
          texto:  const Color(0xFFFFD4A0),
          sombra: const Color(0xFFFF6D00),
        );
      case NarradorTipo.rendimiento:
        return _ColorSet(
          fondo:  const Color(0xFF111111),
          borde:  const Color(0xFFB0BEC5),
          acento: const Color(0xFFB0BEC5),
          texto:  Colors.white,
          sombra: const Color(0xFFB0BEC5),
        );
    }
  }

  String _labelPorTipo(NarradorTipo tipo) {
    switch (tipo) {
      case NarradorTipo.kilometro:   return 'AVANCE';
      case NarradorTipo.conquista:   return 'CONQUISTA';
      case NarradorTipo.territorio:  return 'ZONA HOSTIL';
      case NarradorTipo.refuerzo:    return 'ZONA PROPIA';
      case NarradorTipo.rival:       return 'CONTACTO';
      case NarradorTipo.resistencia: return 'RESISTENCIA';
      case NarradorTipo.rendimiento: return 'RENDIMIENTO';
    }
  }
}

class _ColorSet {
  final Color fondo, borde, acento, texto, sombra;
  const _ColorSet({
    required this.fondo, required this.borde,
    required this.acento, required this.texto, required this.sombra,
  });
}