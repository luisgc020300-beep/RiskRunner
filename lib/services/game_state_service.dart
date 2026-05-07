// lib/services/game_state_service.dart
//
// Singleton que actúa como fuente de verdad compartida entre
// LiveActivityScreen y FullscreenMapScreen para que ambas pantallas
// muestren siempre la misma información (modo, territorios).
//
import 'territory_service.dart';

class GameStateService {
  static final GameStateService instance = GameStateService._();
  GameStateService._();

  static const _kGlobalTtl    = Duration(minutes: 10);
  static const _kTerritoryTtl = Duration(minutes: 2);

  // ── Modo activo ───────────────────────────────────────────────────────────
  // 'competitivo' | 'solitario' | 'global'
  String currentMode = 'competitivo';

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
