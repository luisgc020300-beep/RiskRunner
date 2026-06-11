import 'package:flutter/foundation.dart';

import 'narrador_service.dart';

/// Holds all mutable metrics for an active running session.
/// Lives outside the LiveActivity widget so the HUD can rebuild independently
/// of the map layer, and session logic is independently testable.
class RunSessionNotifier extends ChangeNotifier {
  // ── Session state ────────────────────────────────────────────────────────
  bool isTracking = false;
  bool isPaused   = false;

  // ── Running metrics ──────────────────────────────────────────────────────
  double distanciaTotal  = 0.0;
  double velocidadKmh    = 0.0;
  double velocidadMaxKmh = 0.0;
  double elevacionGanada  = 0.0;
  double elevacionPerdida = 0.0;

  // ── Split tracking ───────────────────────────────────────────────────────
  final List<double> splits       = [];
  int    kmUltimoSplit             = 0;
  double tiempoUltimoSplitSeg     = 0.0;

  // ── Route guidance ───────────────────────────────────────────────────────
  double porcentajeRuta = 0.0;
  bool   fueraDeRuta    = false;
  bool   rutaCompletada = false;

  // ── Narrator ─────────────────────────────────────────────────────────────
  MensajeNarrador? mensajeNarrador;

  // ── Computed ─────────────────────────────────────────────────────────────
  String get ritmoStr {
    if (velocidadKmh < 0.5 || !isTracking || isPaused) return '--:--';
    final mpk = 60.0 / velocidadKmh;
    final min = mpk.floor();
    final seg = ((mpk - min) * 60).round();
    return "$min'${seg.toString().padLeft(2, '0')}\"";
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  void startSession() {
    isTracking      = true;
    isPaused        = false;
    distanciaTotal  = 0.0;
    velocidadKmh    = 0.0;
    velocidadMaxKmh = 0.0;
    elevacionGanada  = 0.0;
    elevacionPerdida = 0.0;
    splits.clear();
    kmUltimoSplit        = 0;
    tiempoUltimoSplitSeg = 0.0;
    porcentajeRuta = 0.0;
    fueraDeRuta    = false;
    rutaCompletada = false;
    mensajeNarrador = null;
    notifyListeners();
  }

  void stopSession() {
    isTracking   = false;
    isPaused     = false;
    velocidadKmh = 0.0;
    notifyListeners();
  }

  void setPaused(bool value) {
    isPaused = value;
    if (value) velocidadKmh = 0.0;
    notifyListeners();
  }

  /// Called after restoring a session from GameStateService.
  void resumeSession(double distanciaKm) {
    distanciaTotal = distanciaKm;
    isTracking     = true;
    isPaused       = true;
    notifyListeners();
  }

  // ── Updates ──────────────────────────────────────────────────────────────
  void updateGpsMetrics({
    required double distanciaTotal,
    required double velocidadKmh,
    required double velocidadMaxKmh,
    required double elevacionGanada,
    required double elevacionPerdida,
  }) {
    this.distanciaTotal  = distanciaTotal;
    this.velocidadKmh    = velocidadKmh;
    this.velocidadMaxKmh = velocidadMaxKmh;
    this.elevacionGanada  = elevacionGanada;
    this.elevacionPerdida = elevacionPerdida;
    notifyListeners();
  }

  void addSplit(double minutos) {
    splits.add(minutos);
    notifyListeners();
  }

  void updateRuta({double? porcentaje, bool? fuera, bool? completada}) {
    if (porcentaje != null) porcentajeRuta = porcentaje;
    if (fuera != null)      fueraDeRuta    = fuera;
    if (completada != null) rutaCompletada = completada;
    notifyListeners();
  }

  void setNarratorMessage(MensajeNarrador? msg) {
    mensajeNarrador = msg;
    notifyListeners();
  }
}
