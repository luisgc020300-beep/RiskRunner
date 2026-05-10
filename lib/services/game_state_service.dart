// lib/services/game_state_service.dart
//
// Singleton que actúa como fuente de verdad compartida entre
// LiveActivityScreen y FullscreenMapScreen para que ambas pantallas
// muestren siempre la misma información (modo, territorios).
//
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'territory_service.dart';

class GameStateService {
  static final GameStateService instance = GameStateService._();
  GameStateService._();

  static const _kGlobalTtl    = Duration(minutes: 10);
  static const _kTerritoryTtl = Duration(minutes: 2);
  static const _kModeKey      = 'gss_current_mode';
  static const _kSessionKey   = 'gss_session';

  // ── Modo activo con persistencia ──────────────────────────────────────────
  // 'competitivo' | 'solitario' | 'global' | 'ruta'
  String _currentMode = 'competitivo';
  String get currentMode => _currentMode;
  set currentMode(String v) {
    _currentMode = v;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kModeKey, v))
        .catchError((_) => false);
  }

  /// Carga el modo guardado desde SharedPreferences. Llamar en main() antes de runApp.
  Future<void> initAsync() async {
    try {
      final p = await SharedPreferences.getInstance();
      _currentMode = p.getString(_kModeKey) ?? 'competitivo';
    } catch (_) {}
  }

  // ── Session persistence ────────────────────────────────────────────────────
  // Guarda el estado de una carrera en progreso para recuperarla si la app se cierra.

  Future<void> saveSession({
    required String mode,
    required List<Map<String, double>> points,
    required double distanciaKm,
    required int elapsedSeconds,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSessionKey, jsonEncode({
        'mode':           mode,
        'points':         points,
        'distanciaKm':    distanciaKm,
        'elapsedSeconds': elapsedSeconds,
        'savedAt':        DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  /// Devuelve la sesión guardada si existe y tiene menos de 12 horas. Null si no hay o expiró.
  Future<Map<String, dynamic>?> restoreSession() async {
    try {
      final p   = await SharedPreferences.getInstance();
      final raw = p.getString(_kSessionKey);
      if (raw == null) return null;
      final data    = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = (data['savedAt'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - savedAt > 12 * 3600 * 1000) {
        await clearSession();
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kSessionKey);
    } catch (_) {}
  }

  // ── Territorios globales ──────────────────────────────────────────────────
  List<GlobalTerritory>? _globalTerritories;
  DateTime?              _globalAt;

  bool get _globalValid =>
      _globalTerritories != null &&
      _globalAt != null &&
      DateTime.now().difference(_globalAt!) < _kGlobalTtl;

  List<GlobalTerritory>? getGlobalTerritories() =>
      _globalValid ? List.unmodifiable(_globalTerritories!) : null;

  void setGlobalTerritories(List<GlobalTerritory> list) {
    _globalTerritories = List.of(list);
    _globalAt          = DateTime.now();
  }

  void invalidateGlobal() {
    _globalTerritories = null;
    _globalAt          = null;
  }

  // ── Territorios competitivos ──────────────────────────────────────────────
  List<TerritoryData>? _competitiveTerritories;
  DateTime?            _competitiveAt;

  bool get _competitiveValid =>
      _competitiveTerritories != null &&
      _competitiveAt != null &&
      DateTime.now().difference(_competitiveAt!) < _kTerritoryTtl;

  List<TerritoryData>? getCompetitiveTerritories() =>
      _competitiveValid ? List.unmodifiable(_competitiveTerritories!) : null;

  void setCompetitiveTerritories(List<TerritoryData> list) {
    _competitiveTerritories = List.of(list);
    _competitiveAt          = DateTime.now();
  }

  void invalidateCompetitive() {
    _competitiveTerritories = null;
    _competitiveAt          = null;
  }

  // ── Territorios solitario ─────────────────────────────────────────────────
  List<TerritoryData>? _solitarioTerritories;
  DateTime?            _solitarioAt;

  bool get _solitarioValid =>
      _solitarioTerritories != null &&
      _solitarioAt != null &&
      DateTime.now().difference(_solitarioAt!) < _kTerritoryTtl;

  List<TerritoryData>? getSolitarioTerritories() =>
      _solitarioValid ? List.unmodifiable(_solitarioTerritories!) : null;

  void setSolitarioTerritories(List<TerritoryData> list) {
    _solitarioTerritories = List.of(list);
    _solitarioAt          = DateTime.now();
  }

  void invalidateSolitario() {
    _solitarioTerritories = null;
    _solitarioAt          = null;
  }

  /// Invalida los caches competitivo y solitario — llamar junto a TerritoryService.invalidarCache().
  void invalidateTerritories() {
    invalidateCompetitive();
    invalidateSolitario();
  }

  /// Invalida todo — usar al cerrar sesión.
  void reset() {
    currentMode             = 'competitivo';
    _globalTerritories      = null;
    _globalAt               = null;
    _competitiveTerritories = null;
    _competitiveAt          = null;
    _solitarioTerritories   = null;
    _solitarioAt            = null;
  }
}
