import '../services/territory_service.dart';

/// Encapsula el estado de modo de juego de LiveActivity.
/// Invariante: cualquier cambio de modo resetea [territoriosCargados] a false
/// y vacía [territorios], garantizando que la UI muestre "Cargando..." en lugar
/// de un recuento obsoleto.
class GameModeController {
  bool modoSolitario     = false;
  bool modoRuta          = false;
  bool territoriosCargados = false;
  List<TerritoryData> territorios = [];
  Map<String, dynamic>? objetivoGlobal;
  bool seleccionandoGlobal = false;

  bool get isCompetitivo =>
      !modoSolitario && !modoRuta && objetivoGlobal == null;
  bool get isGlobal => objetivoGlobal != null;

  void switchToCompetitivo() {
    modoSolitario      = false;
    modoRuta           = false;
    objetivoGlobal     = null;
    territorios        = [];
    territoriosCargados = false;
    seleccionandoGlobal = false;
  }

  void switchToSolitario() {
    modoSolitario      = true;
    modoRuta           = false;
    objetivoGlobal     = null;
    territorios        = [];
    territoriosCargados = false;
    seleccionandoGlobal = false;
  }

  void switchToRuta() {
    modoRuta           = true;
    modoSolitario      = false;
    objetivoGlobal     = null;
    territorios        = [];
    territoriosCargados = false;
    seleccionandoGlobal = false;
  }

  /// Inicia el flujo de selección de objetivo global (el selector en globo).
  /// [objetivoGlobal] se asigna luego con [setObjetivoGlobal].
  void switchToGlobal() {
    seleccionandoGlobal = true;
    modoRuta            = false;
    modoSolitario       = false;
    territoriosCargados = false;
  }

  void setObjetivoGlobal(Map<String, dynamic> objetivo) {
    objetivoGlobal      = objetivo;
    seleccionandoGlobal = false;
  }

  /// Lllamado cuando la carga de territorios completa con éxito.
  void onTerritoriosCargados(List<TerritoryData> lista) {
    territorios         = lista;
    territoriosCargados = true;
  }
}
