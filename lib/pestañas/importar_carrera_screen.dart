// lib/pestañas/importar_carrera_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/gpx_import_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';

// ── Estado de la pantalla ─────────────────────────────────────────────────────
enum _Phase { idle, parsed, processing, done, error }

// =============================================================================
class ImportarCarreraScreen extends StatefulWidget {
  const ImportarCarreraScreen({super.key});

  @override
  State<ImportarCarreraScreen> createState() => _ImportarCarreraScreenState();
}

class _ImportarCarreraScreenState extends State<ImportarCarreraScreen> {
  _Phase        _phase   = _Phase.idle;
  GpxData?      _gpxData;
  ImportResult? _result;
  String        _errorMsg = '';
  String        _fileName = '';

  // ── Paso 1: seleccionar archivo GPX ─────────────────────────────────────────
  Future<void> _seleccionarArchivo() async {
    HapticFeedback.lightImpact();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final content = await File(path).readAsString();
      final parsed  = GpxImportService.parseGpx(content);

      if (parsed == null || parsed.puntos.isEmpty) {
        setState(() {
          _phase    = _Phase.error;
          _errorMsg = 'El archivo no contiene una ruta GPS válida.';
        });
        return;
      }

      setState(() {
        _gpxData  = parsed;
        _fileName = result.files.single.name;
        _phase    = _Phase.parsed;
      });
    } catch (e) {
      setState(() {
        _phase    = _Phase.error;
        _errorMsg = 'No se pudo leer el archivo: $e';
      });
    }
  }

  // ── Paso 2: procesar territorios ─────────────────────────────────────────────
  Future<void> _procesarTerritorios() async {
    if (_gpxData == null) return;
    setState(() => _phase = _Phase.processing);

    try {
      final res = await GpxImportService.procesarImportacion(_gpxData!);
      HapticFeedback.heavyImpact();
      setState(() {
        _result = res;
        _phase  = _Phase.done;
      });
    } catch (e) {
      setState(() {
        _phase    = _Phase.error;
        _errorMsg = 'Error al procesar: $e';
      });
    }
  }

  // ── Resetear ─────────────────────────────────────────────────────────────────
  void _reset() => setState(() {
        _phase    = _Phase.idle;
        _gpxData  = null;
        _result   = null;
        _errorMsg = '';
        _fileName = '';
      });

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('IMPORTAR CARRERA',
            style: AppTypography.label(AppColors.textPrimary)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.idle       => _buildIdle(),
          _Phase.parsed     => _buildParsed(),
          _Phase.processing => _buildProcessing(),
          _Phase.done       => _buildDone(),
          _Phase.error      => _buildError(),
        },
      ),
    );
  }

  // ── IDLE ─────────────────────────────────────────────────────────────────────
  Widget _buildIdle() {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(children: [
        const SizedBox(height: 40),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.upload_file_rounded,
              color: AppColors.red, size: 32),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        Text('Importar carrera desde GPX',
            style: AppTypography.heading(AppColors.textPrimary),
            textAlign: TextAlign.center),
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          'Exporta tu carrera desde Strava, Garmin Connect o Komoot '
          'como archivo GPX y procesa los territorios que atravesaste.',
          style: AppTypography.body(AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTokens.spaceXl),
        _buildHowToRow(Icons.directions_run_rounded, AppColors.red,
            'Strava', 'Actividad → ⋯ → Exportar GPX'),
        const SizedBox(height: AppTokens.spaceSm),
        _buildHowToRow(Icons.watch_rounded, AppColors.gold,
            'Garmin', 'Actividades → Exportar original'),
        const SizedBox(height: AppTokens.spaceSm),
        _buildHowToRow(Icons.explore_rounded, AppColors.green,
            'Komoot', 'Tour → Descargar GPX'),
        const Spacer(),
        AppButton.primary(
          label: 'SELECCIONAR ARCHIVO GPX',
          icon: Icons.folder_open_rounded,
          onTap: _seleccionarArchivo,
        ),
      ]),
    );
  }

  Widget _buildHowToRow(IconData icon, Color color, String app, String pasos) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceSm + 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: AppTokens.iconMd),
          const SizedBox(width: AppTokens.spaceSm),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app, style: AppTypography.label(AppColors.textPrimary, size: 12)),
            Text(pasos, style: AppTypography.body(AppColors.textTertiary, size: 11)),
          ]),
        ]),
      );

  // ── PARSED: preview de la ruta ───────────────────────────────────────────────
  Widget _buildParsed() {
    final d = _gpxData!;
    final mins = d.duracion.inMinutes;
    final secs = d.duracion.inSeconds % 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceSm + 4, vertical: AppTokens.spaceSm + 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            const Icon(Icons.insert_drive_file_rounded,
                color: AppColors.gold, size: AppTokens.iconSm),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Text(_fileName,
                  style: AppTypography.body(AppColors.textPrimary,
                      weight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.check_circle_rounded,
                color: AppColors.green, size: AppTokens.iconSm),
          ]),
        ),
        const SizedBox(height: AppTokens.spaceMd),

        Row(children: [
          _statCell('${d.distanciaKm.toStringAsFixed(2)} km', 'DISTANCIA',
              Icons.straighten_rounded, AppColors.red),
          const SizedBox(width: AppTokens.spaceSm),
          _statCell(
              '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
              'TIEMPO', Icons.timer_rounded, AppColors.gold),
          const SizedBox(width: AppTokens.spaceSm),
          _statCell('${d.velocidadMediaKmh.toStringAsFixed(1)} km/h', 'VELOCIDAD',
              Icons.speed_rounded, AppColors.green),
        ]),
        const SizedBox(height: AppTokens.spaceMd),

        if (d.puntos.length > 1)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            child: SizedBox(
              height: 220,
              child: FlutterMap(
                options: MapOptions(
                  backgroundColor: const Color(0xFF1A1A1A),
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(d.puntos),
                    padding: const EdgeInsets.all(32),
                  ),
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.tuapp.juego',
                  ),
                  PolylineLayer(polylines: [
                    Polyline(
                        points: d.puntos,
                        color: AppColors.red,
                        strokeWidth: 3),
                  ]),
                ],
              ),
            ),
          ),

        const SizedBox(height: AppTokens.spaceSm),
        Text('${d.puntos.length} puntos GPS detectados.',
            style: AppTypography.body(AppColors.textTertiary, size: 11)),
        const SizedBox(height: AppTokens.spaceLg),

        AppButton.primary(
          label: 'PROCESAR TERRITORIOS',
          icon: Icons.flag_rounded,
          onTap: _procesarTerritorios,
        ),
        const SizedBox(height: AppTokens.spaceSm),
        AppButton.secondary(
          label: 'CAMBIAR ARCHIVO',
          icon: Icons.folder_open_rounded,
          color: AppColors.textTertiary,
          onTap: _reset,
        ),
      ]),
    );
  }

  Widget _statCell(String val, String label, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(AppTokens.spaceSm + 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: AppTokens.iconXs),
            const SizedBox(height: 6),
            Text(val,
                style: AppTypography.body(AppColors.textPrimary,
                    size: 13, weight: FontWeight.w700)),
            Text(label, style: AppTypography.caption(AppColors.textTertiary)),
          ]),
        ),
      );

  // ── PROCESSING ───────────────────────────────────────────────────────────────
  Widget _buildProcessing() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: AppColors.red, strokeWidth: 2),
        const SizedBox(height: AppTokens.spaceMd),
        Text('Analizando territorios…',
            style: AppTypography.heading(AppColors.textPrimary)),
        const SizedBox(height: AppTokens.spaceXs),
        Text('Comprobando ${_gpxData!.puntos.length} puntos GPS',
            style: AppTypography.body(AppColors.textTertiary)),
      ]),
    );
  }

  // ── DONE ─────────────────────────────────────────────────────────────────────
  Widget _buildDone() {
    final r = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: AppTokens.spaceSm),
        Container(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(
              color: r.conquistados > 0
                  ? AppColors.red.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 3, height: 20, color: AppColors.red),
              const SizedBox(width: AppTokens.spaceSm),
              Text('RESULTADO DE IMPORTACION',
                  style: AppTypography.label(AppColors.textPrimary)),
            ]),
            const SizedBox(height: AppTokens.spaceMd),
            Row(children: [
              _resultCell(r.conquistados.toString(), 'CONQUISTADOS', AppColors.red),
              _resultCell(r.danados.toString(), 'DANADOS', AppColors.gold),
              _resultCell(r.sinCambio.toString(), 'SIN CAMBIO', AppColors.textTertiary),
            ]),
          ]),
        ),

        const SizedBox(height: AppTokens.spaceMd),

        if (r.mensajes.isNotEmpty) ...[
          Text('DETALLE', style: AppTypography.caption(AppColors.textTertiary)),
          const SizedBox(height: AppTokens.spaceSm),
          ...r.mensajes.map((msg) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                msg.startsWith('Conquistado')
                    ? Icons.flag_rounded
                    : msg.startsWith('Daño')
                        ? Icons.flash_on_rounded
                        : Icons.info_outline_rounded,
                color: msg.startsWith('Conquistado')
                    ? AppColors.red
                    : msg.startsWith('Daño')
                        ? AppColors.gold
                        : AppColors.textTertiary,
                size: AppTokens.iconXs,
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(msg,
                    style: AppTypography.body(AppColors.textPrimary,
                        weight: FontWeight.w500)),
              ),
            ]),
          )),
          const SizedBox(height: AppTokens.spaceMd),
        ],

        Text('CARRERA IMPORTADA',
            style: AppTypography.caption(AppColors.textTertiary)),
        const SizedBox(height: AppTokens.spaceSm),
        Row(children: [
          _statCell('${r.datos.distanciaKm.toStringAsFixed(2)} km', 'DISTANCIA',
              Icons.straighten_rounded, AppColors.red),
          const SizedBox(width: AppTokens.spaceSm),
          _statCell(
              '${r.datos.duracion.inMinutes.toString().padLeft(2, '0')}'
              ':${(r.datos.duracion.inSeconds % 60).toString().padLeft(2, '0')}',
              'TIEMPO', Icons.timer_rounded, AppColors.gold),
          const SizedBox(width: AppTokens.spaceSm),
          _statCell('${r.datos.velocidadMediaKmh.toStringAsFixed(1)} km/h',
              'VELOCIDAD', Icons.speed_rounded, AppColors.green),
        ]),

        const SizedBox(height: AppTokens.spaceXl),
        AppButton.primary(
          label: 'IMPORTAR OTRA CARRERA',
          icon: Icons.upload_file_rounded,
          onTap: _reset,
        ),
        const SizedBox(height: AppTokens.spaceSm),
        AppButton.ghost(
          label: 'CERRAR',
          icon: Icons.close_rounded,
          onTap: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  Widget _resultCell(String val, String label, Color color) =>
      Expanded(child: Column(children: [
        Text(val, style: AppTypography.display(color)),
        Text(label, style: AppTypography.caption(AppColors.textTertiary)),
      ]));

  // ── ERROR ────────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline_rounded,
            color: AppColors.red, size: 48),
        const SizedBox(height: AppTokens.spaceMd),
        Text('Error al importar',
            style: AppTypography.heading(AppColors.textPrimary)),
        const SizedBox(height: AppTokens.spaceSm),
        Text(_errorMsg,
            style: AppTypography.body(AppColors.textTertiary),
            textAlign: TextAlign.center),
        const SizedBox(height: AppTokens.spaceXl),
        AppButton.primary(
          label: 'INTENTAR DE NUEVO',
          icon: Icons.refresh_rounded,
          onTap: _reset,
        ),
      ]),
    );
  }
}
