import 'package:flutter/material.dart';
import 'map_theme.dart';

// ── Renombrar territorio ──────────────────────────────────────────────────────
class MapDialogoRenombrar extends StatefulWidget {
  final String nombreActual;
  final Future<void> Function(String) onGuardar;
  const MapDialogoRenombrar(
      {super.key, required this.nombreActual, required this.onGuardar});

  @override
  State<MapDialogoRenombrar> createState() => _MapDialogoRenombrarState();
}

class _MapDialogoRenombrarState extends State<MapDialogoRenombrar> {
  late final TextEditingController _ctrl;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nombreActual);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _ctrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío');
      return;
    }
    if (nombre.length > 30) {
      setState(() => _error = 'Máximo 30 caracteres');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.onGuardar(nombre);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kMapSurface,
          border: Border.all(color: kMapGold.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: kMapGold.withValues(alpha: 0.08), blurRadius: 30),
            const BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: kMapGold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: kMapGold.withValues(alpha: 0.4))),
            child: const Icon(Icons.edit_rounded, color: kMapGold, size: 22)),
          const SizedBox(height: 16),
          Text('NOMBRE DEL TERRITORIO',
              style: mapRaj(15, FontWeight.w900, kMapWhite, spacing: 1.5)),
          const SizedBox(height: 6),
          Text(
            'Este nombre será visible para todos en el mapa.',
            textAlign: TextAlign.center,
            style: mapRaj(11, FontWeight.w500, kMapSub, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: kMapBg,
              border: Border.all(
                  color: _error != null
                      ? kMapRed.withValues(alpha: 0.6)
                      : kMapGold.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6)),
            child: TextField(
              controller: _ctrl, maxLength: 30, autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: mapRaj(14, FontWeight.w700, kMapWhite),
              cursorColor: kMapGold,
              decoration: InputDecoration(
                hintText: 'Ej: La Cuesta del Infierno',
                hintStyle: mapRaj(13, FontWeight.w500, kMapDim),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: InputBorder.none,
                counterStyle: mapRaj(10, FontWeight.w500, kMapSub)),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _guardar(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: kMapRed, size: 12),
                const SizedBox(width: 4),
                Text(_error!, style: mapRaj(10, FontWeight.w600, kMapRed)),
              ]),
            ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: kMapBorder, borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('CANCELAR',
                    style: mapRaj(12, FontWeight.w800, kMapText, spacing: 1)))),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: _guardando ? null : _guardar,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: kMapGold.withValues(alpha: 0.15),
                    border: Border.all(color: kMapGold.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(6)),
                child: Center(child: _guardando
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: kMapGold))
                    : Text('GUARDAR',
                        style: mapRaj(12, FontWeight.w900, kMapGold,
                            spacing: 1)))),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ── Confirmar conquista ───────────────────────────────────────────────────────
class MapDialogoConfirmarConquista extends StatelessWidget {
  final String ownerNick;
  final int diasSinVisitar;
  const MapDialogoConfirmarConquista(
      {super.key, required this.ownerNick, required this.diasSinVisitar});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kMapSurface,
          border: Border.all(color: kMapRed.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: kMapRed.withValues(alpha: 0.1), blurRadius: 30),
            const BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: kMapRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: kMapRed.withValues(alpha: 0.4))),
            child: const Icon(Icons.sports_kabaddi_rounded,
                color: kMapRed, size: 24)),
          const SizedBox(height: 16),
          Text('¿CONQUISTAR?',
              style: mapRaj(18, FontWeight.w900, kMapWhite, spacing: 2)),
          const SizedBox(height: 8),
          Text(
            'Territorio de ${ownerNick.toUpperCase()}\n'
            '$diasSinVisitar días sin visitar',
            textAlign: TextAlign.center,
            style: mapRaj(12, FontWeight.w600, kMapSub, height: 1.5)),
          const SizedBox(height: 6),
          Text(
            'Debes estar físicamente a menos\nde 200 m del territorio.',
            textAlign: TextAlign.center,
            style: mapRaj(11, FontWeight.w500, kMapDim, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: kMapBorder, borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('CANCELAR',
                    style: mapRaj(12, FontWeight.w800, kMapText, spacing: 1)))),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: kMapRed.withValues(alpha: 0.15),
                    border: Border.all(color: kMapRed.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('CONQUISTAR',
                    style: mapRaj(12, FontWeight.w900, kMapRed, spacing: 1)))),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ── Conquistando (progress) ───────────────────────────────────────────────────
class MapDialogoConquistando extends StatelessWidget {
  const MapDialogoConquistando({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: kMapSurface,
          border: Border.all(color: kMapBorder2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(strokeWidth: 2, color: kMapRed)),
          const SizedBox(height: 16),
          Text('CONQUISTANDO...',
              style: mapRaj(14, FontWeight.w900, kMapWhite, spacing: 2)),
          const SizedBox(height: 6),
          Text('Verificando posición y condiciones',
              style: mapRaj(10, FontWeight.w500, kMapSub)),
        ]),
      ),
    );
  }
}
