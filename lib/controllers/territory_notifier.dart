import 'package:flutter/material.dart';

import '../services/territory_service.dart';

/// Holds all territory-related state for a LiveActivity session.
/// Extends ChangeNotifier so ListenableBuilder widgets rebuild only when
/// territory state changes, independently of the Mapbox map subtree.
class TerritoryNotifier extends ChangeNotifier {
  // ── Modo de juego ──────────────────────────────────────────────────────────
  bool modoSolitario       = false;
  bool modoRuta            = false;
  bool territoriosCargados = false;
  List<TerritoryData> territorios = [];
  Map<String, dynamic>? objetivoGlobal;
  bool seleccionandoGlobal = false;

  // ── Conquista global ───────────────────────────────────────────────────────
  bool    globalConquistado  = false;
  bool    globalConquistando = false;
  bool    globalKmAlcanzados = false;
  double? nuevaClausula;

  // ── Estado de sesión activa ────────────────────────────────────────────────
  bool  mapaDesactualizado = false;
  bool  zonaValida         = false;
  bool  retoCompletado     = false;
  Color colorTerritorio    = const Color(0xFF636366);

  // ── Computed ───────────────────────────────────────────────────────────────
  bool get isCompetitivo =>
      !modoSolitario && !modoRuta && objetivoGlobal == null;
  bool get isGlobal => objetivoGlobal != null;

  // ── Modo switches ──────────────────────────────────────────────────────────
  void switchToCompetitivo() {
    modoSolitario       = false;
    modoRuta            = false;
    objetivoGlobal      = null;
    territorios         = [];
    territoriosCargados = false;
    seleccionandoGlobal = false;
    notifyListeners();
  }

  void switchToSolitario() {
    modoSolitario       = true;
    modoRuta            = false;
    objetivoGlobal      = null;
    territorios         = [];
    territoriosCargados = false;
    seleccionandoGlobal = false;
    notifyListeners();
  }

  void switchToRuta() {
    modoRuta            = true;
    modoSolitario       = false;
    objetivoGlobal      = null;
    territorios         = [];
    territoriosCargados = false;
    seleccionandoGlobal = false;
    notifyListeners();
  }

  void switchToGlobal() {
    seleccionandoGlobal = true;
    modoRuta            = false;
    modoSolitario       = false;
    territoriosCargados = false;
    notifyListeners();
  }

  void setObjetivoGlobal(Map<String, dynamic> objetivo) {
    objetivoGlobal      = objetivo;
    seleccionandoGlobal = false;
    notifyListeners();
  }

  void onTerritoriosCargados(List<TerritoryData> lista) {
    territorios         = lista;
    territoriosCargados = true;
    notifyListeners();
  }

  // ── Conquista global ───────────────────────────────────────────────────────
  void setGlobalConquistando(bool value) {
    globalConquistando = value;
    notifyListeners();
  }

  void setConquistaGlobalExito({required double? nuevaCl}) {
    globalConquistado = true;
    nuevaClausula     = nuevaCl;
    notifyListeners();
  }

  void setGlobalKmAlcanzados() {
    globalKmAlcanzados = true;
    notifyListeners();
  }

  // ── Estado de sesión ───────────────────────────────────────────────────────
  void setMapaDesactualizado(bool value) {
    if (mapaDesactualizado == value) return;
    mapaDesactualizado = value;
    notifyListeners();
  }

  void setZonaValida(bool value) {
    if (zonaValida == value) return;
    zonaValida = value;
    notifyListeners();
  }

  void setRetoCompletado() {
    retoCompletado = true;
    notifyListeners();
  }

  void setColorTerritorio(Color color) {
    colorTerritorio = color;
    notifyListeners();
  }

  // ── Resets compuestos ──────────────────────────────────────────────────────
  /// Llamado al iniciar una nueva sesión de tracking.
  void resetParaSesion() {
    globalKmAlcanzados = false;
    globalConquistado  = false;
    globalConquistando = false;
    nuevaClausula      = null;
    retoCompletado     = false;
    zonaValida         = false;
    notifyListeners();
  }

  /// Llamado cuando se asigna un nuevo objetivo global sin iniciar sesión.
  void resetConquistaGlobal() {
    globalConquistado  = false;
    globalConquistando = false;
    notifyListeners();
  }
}
