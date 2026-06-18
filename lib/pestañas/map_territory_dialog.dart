// lib/pestañas/map_territory_dialog.dart
// Diálogo de detalle de territorio y renombrar — extraídos de fullscreen_map_screen.dart.
// ignore_for_file: invalid_use_of_protected_member
part of 'fullscreen_map_screen.dart';

extension _MapTerritoryDialog on _FullscreenMapScreenState {
  // ==========================================================================
  // DIÁLOGO DETALLE TERRITORIO
  // ==========================================================================
  void _mostrarDialogo(_TerDet det, String ownerNick) {
    final esMio = det.ownerId == (_uid ?? '');
    final conquistable = !esMio &&
        det.diasSinVisitar != null &&
        det.diasSinVisitar! >= kDiasParaDeterioroFuncional;
    final centro = det.puntos.isNotEmpty
        ? LatLng(
            det.puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                det.puntos.length,
            det.puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                det.puntos.length)
        : _state.centro;

    String estado = 'activo';
    Color cEstado = _kSafe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= kDiasParaDeterioroFuncional) {
      estado = 'crítico'; cEstado = _kRed;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= kDiasParaDeterioroVisual) {
      estado = 'con desgaste'; cEstado = _kWarn;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        TerritoryData? td;
        try {
          td = _state.territorios.firstWhere((x) => x.docId == det.docId);
        } catch (_) {}
        final Color accent = td?.color ?? cEstado;
        final int hp       = td?.hpActual ?? kHpMax;
        final double hpFrac = (hp / kHpMax).clamp(0.0, 1.0);
        final Color hpColor;
        switch (td?.estadoHp ?? EstadoHp.saludable) {
          case EstadoHp.saludable: hpColor = _kSafe; break;
          case EstadoHp.danado:    hpColor = _kWarn; break;
          case EstadoHp.critico:   hpColor = _kRed;  break;
        }

        return Container(
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(
              top:   BorderSide(color: accent.withValues(alpha: 0.55), width: 2),
              left:  const BorderSide(color: _kBorder2),
              right: const BorderSide(color: _kBorder2),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 32, height: 3,
              decoration: BoxDecoration(
                  color: _kBorder, borderRadius: BorderRadius.circular(2))),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 2, height: 36, color: accent,
                  margin: const EdgeInsets.only(right: 10, top: 2)),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ownerNick.toUpperCase(),
                        style: _raj(14, FontWeight.w900, _kWhite, spacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(
                      det.nombreTerritorio != null && det.nombreTerritorio!.isNotEmpty
                          ? det.nombreTerritorio!
                          : 'Sin nombre asignado',
                      style: _raj(11, FontWeight.w500, _kSub)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cEstado.withValues(alpha: 0.06),
                    border: Border.all(color: cEstado.withValues(alpha: 0.28)),
                    borderRadius: BorderRadius.circular(3)),
                  child: Text(estado.toUpperCase(),
                      style: _raj(8, FontWeight.w800, cEstado, spacing: 0.8))),
              ]),
            ),

            const Divider(height: 1, thickness: 1, color: _kBorder2),

            // Mini map
            if (det.puntos.isNotEmpty)
              SizedBox(
                height: 140,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom)),
                  children: [
                    TileLayer(
                        urlTemplate: _kMapboxUrl,
                        userAgentPackageName: 'com.runner_risk.app',
                        tileDimension: 256,
                        keepBuffer: 4,
                        panBuffer: 1),
                    PolygonLayer(polygons: [
                      Polygon(
                          points: det.puntos,
                          color: accent.withValues(alpha: 0.15),
                          borderColor: accent,
                          borderStrokeWidth: 2),
                    ]),
                  ],
                ),
              ),

            if (det.puntos.isNotEmpty)
              const Divider(height: 1, thickness: 1, color: _kBorder2),

            // HP bar (enemy territories only)
            if (td != null && !esMio)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(children: [
                  Row(children: [
                    Text(estado.toUpperCase(),
                        style: _raj(9, FontWeight.w700, hpColor, spacing: 0.8)),
                    const Spacer(),
                    Text('$hp / $kHpMax HP',
                        style: _raj(9, FontWeight.w500, _kSub)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1.5),
                    child: Stack(children: [
                      Container(height: 3, color: _kBorder2),
                      FractionallySizedBox(
                        widthFactor: hpFrac,
                        child: Container(height: 3, color: hpColor)),
                    ]),
                  ),
                ]),
              ),

            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                _dStat(
                    'SIN VISITAR',
                    det.diasSinVisitar != null ? '${det.diasSinVisitar}d' : '—',
                    _kText),
                Container(width: 1, height: 32, color: _kBorder2),
                _dStat('DISTANCIA',
                    '${det.dist.toStringAsFixed(1)} km', _kText),
                Container(width: 1, height: 32, color: _kBorder2),
                _dStat('VÉRTICES', '${det.puntos.length}', _kText),
              ]),
            ),

            const Divider(height: 1, thickness: 1, color: _kBorder2),
            const SizedBox(height: 8),

            // Action buttons
            if (conquistable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GestureDetector(
                  onTap: () => _ejecutarConquista(det, ownerNick),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.06),
                      border: Border.all(color: _kRed.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sports_kabaddi_rounded,
                              color: _kRed, size: 16),
                          const SizedBox(width: 10),
                          Text('CONQUISTAR TERRITORIO',
                              style: _raj(12, FontWeight.w900, _kRed,
                                  spacing: 1.5)),
                        ]),
                  ),
                ),
              ),
            if (!esMio && !conquistable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 11, horizontal: 14),
                  decoration: BoxDecoration(
                      color: _kSurface2,
                      border: Border.all(color: _kBorder2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: _kSub, size: 13),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Faltan ${kDiasParaDeterioroFuncional - (det.diasSinVisitar ?? 0)} días sin visita para conquistar.',
                      style: _raj(10, FontWeight.w500, _kSub),
                    )),
                  ]),
                ),
              ),
            if (esMio)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _mostrarDialogoRenombrar(det);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.06),
                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_outlined, color: accent, size: 15),
                          const SizedBox(width: 8),
                          Text(
                            det.nombreTerritorio != null &&
                                    det.nombreTerritorio!.isNotEmpty
                                ? 'EDITAR NOMBRE'
                                : 'ASIGNAR NOMBRE',
                            style: _raj(12, FontWeight.w800, accent,
                                spacing: 1.2)),
                        ]),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  Widget _dStat(String l, String v, Color c) =>
      Expanded(child: Column(children: [
        Text(l, style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
        const SizedBox(height: 4),
        Text(v, style: _raj(16, FontWeight.w900, c)),
      ]));

  void _mostrarDialogoRenombrar(_TerDet det) {
    showDialog(
      context: context,
      builder: (_) => _DialogoRenombrar(
        nombreActual: det.nombreTerritorio ?? '',
        onGuardar: (nuevoNombre) async {
          try {
            await TerritoryService.renombrarTerritorio(
                docId: det.docId, nombre: nuevoNombre);
            if (!mounted) return;
            _mostrarExito(
                'âœï¸ Territorio renombrado como "$nuevoNombre"');
            _MapState.invalidarDetallesCache();
            await _state.cargarDetalles(det.ownerId, modo: _state.modoSolitario ? 'solitario' : 'competitivo');
          } on FirebaseFunctionsException catch (e) {
            if (!mounted) return;
            _mostrarError(e.message ?? 'No se pudo renombrar');
          } catch (e, st) {
            FirebaseCrashlytics.instance.recordError(e, st, reason: 'renombrar_territorio');
            if (!mounted) return;
            _mostrarError('Error inesperado.');
          }
        },
      ),
    );
  }
}
