import 'package:flutter/material.dart';

import 'social_theme.dart';
import 'social_shared.dart';

class SocialErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const SocialErrorState({super.key, required this.onRetry});
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
        decoration: BoxDecoration(color: kSocAccent.withValues(alpha: 0.05),
          border: Border.all(color: kSocAccent.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(14)),
        child: Icon(Icons.wifi_off_rounded, color: kSocAccent.withValues(alpha: 0.5), size: 24)),
      const SizedBox(height: 16),
      Text('Error de conexión', style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      Text('No se pudo cargar la información', style: TextStyle(color: p.text2, fontSize: 12, fontStyle: FontStyle.italic)),
      const SizedBox(height: 20),
      SocialPress(onTap: onRetry, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(color: p.surface3, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.refresh_rounded, color: p.text2, size: 14), const SizedBox(width: 7),
          Text('Reintentar', style: TextStyle(color: p.text2, fontSize: 12, fontWeight: FontWeight.w700)),
        ]))),
    ]));
  }
}

class SocialEmptyState extends StatelessWidget {
  final IconData icon; final String titulo, subtitulo;
  final String? accionLabel; final VoidCallback? onAccion;
  const SocialEmptyState({super.key, required this.icon, required this.titulo, required this.subtitulo, this.accionLabel, this.onAccion});
  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: p.surface2,
                border: Border.all(color: p.line2),
                borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: p.dim, size: 24)),
            const SizedBox(height: 16),
            Text(titulo, style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            Text(subtitulo,
              style: TextStyle(color: p.text2, fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center),
            if (accionLabel != null && onAccion != null) ...[
              const SizedBox(height: 20),
              SocialPress(
                onTap: onAccion,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.surface3,
                    border: Border.all(color: p.line2),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(accionLabel!,
                    style: TextStyle(color: p.text2, fontSize: 12, fontWeight: FontWeight.w700)))),
            ],
          ],
        ),
      ),
    );
  }
}

class SocialChatErrorState extends StatelessWidget {
  final Object? error;
  const SocialChatErrorState({super.key, this.error});
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 60, height: 60,
          decoration: BoxDecoration(color: kSocAccent.withValues(alpha: 0.04),
            border: Border.all(color: kSocAccent.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.wifi_off_rounded, color: kSocAccent.withValues(alpha: 0.5), size: 26)),
        const SizedBox(height: 16),
        Text('Error de conexión', style: TextStyle(color: p.text1, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        Text('No se pudieron cargar los mensajes.', style: TextStyle(color: p.text2, fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: p.dim, size: 12), const SizedBox(width: 8),
            Expanded(child: Text(error?.toString() ?? 'Error desconocido',
              style: TextStyle(color: p.subtext, fontSize: 10), maxLines: 3, overflow: TextOverflow.ellipsis)),
          ])),
      ])));
  }
}
