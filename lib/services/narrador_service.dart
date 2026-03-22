// lib/services/narrador_service.dart
//
// Narrador de carrera — Nivel 1 (mensajes en pantalla)
// Gestiona todos los eventos que disparan mensajes narrativos durante la carrera.
// No requiere audio ni IA — solo lógica de estado + frases pregrabadas.

import 'dart:math';

class MensajeNarrador {
  final String texto;
  final String emoji;
  final NarradorTipo tipo;
  final Duration duracion;

  const MensajeNarrador({
    required this.texto,
    required this.emoji,
    required this.tipo,
    this.duracion = const Duration(seconds: 4),
  });
}

enum NarradorTipo {
  kilometro,    // dorado
  territorio,   // terracota
  refuerzo,     // verde
  rival,        // azul agua
  rendimiento,  // plateado
  conquista,    // dorado brillante
  resistencia,  // naranja
}

class NarradorService {
  final Random _rng = Random();

  // Callback que se llama cada vez que hay un mensaje nuevo
  Function(MensajeNarrador)? onMensaje;

  // Estado interno para evitar repeticiones
  int _ultimoKmNotificado       = 0;
  DateTime? _ultimoMensajeTs;
  double _ritmoUltimos500m      = 0;
  int _mensajesEnviados         = 0;
  bool _mitadNotificada         = false;
  DateTime? _inicioCampana;

  // ── Estado del reto activo ────────────────────────────────────────────────
  String? _tituloRetoActivo;
  double? _objetivoRetoMetros;
  bool _mitadRetoNotificada   = false;
  bool _finalRetoNotificado   = false; // aviso a 200m del final
  bool _retoCompletadoEmitido = false;

  static const Duration _cooldownMinimo = Duration(seconds: 12);

  void iniciar() {
    _inicioCampana = DateTime.now();
    _ultimoKmNotificado = 0;
    _mitadNotificada = false;
    _mensajesEnviados = 0;
    _ultimoMensajeTs = null;
    // No reseteamos el reto aquí — se configura antes de iniciar
  }

  void resetear() {
    _ultimoKmNotificado = 0;
    _mitadNotificada = false;
    _mensajesEnviados = 0;
    _ultimoMensajeTs = null;
    _inicioCampana = null;
    _ritmoUltimos500m = 0;
    _tituloRetoActivo = null;
    _objetivoRetoMetros = null;
    _mitadRetoNotificada = false;
    _finalRetoNotificado = false;
    _retoCompletadoEmitido = false;
  }

  // ── Control de cooldown ───────────────────────────────────────────────────
  bool get _puedeMostrar {
    if (_ultimoMensajeTs == null) return true;
    return DateTime.now().difference(_ultimoMensajeTs!) >= _cooldownMinimo;
  }

  void _emitir(MensajeNarrador msg) {
    if (!_puedeMostrar) return;
    _ultimoMensajeTs = DateTime.now();
    _mensajesEnviados++;
    onMensaje?.call(msg);
  }

  // Emitir ignorando cooldown — para eventos críticos del reto
  void _emitirForzado(MensajeNarrador msg) {
    _ultimoMensajeTs = DateTime.now();
    _mensajesEnviados++;
    onMensaje?.call(msg);
  }

  // ==========================================================================
  // EVENTOS DE RETO — nuevos
  // ==========================================================================

  /// Configura el reto activo. Llamar ANTES de iniciar().
  void configurarReto(String titulo, double objetivoMetros) {
    _tituloRetoActivo   = titulo;
    _objetivoRetoMetros = objetivoMetros;
    _mitadRetoNotificada   = false;
    _finalRetoNotificado   = false;
    _retoCompletadoEmitido = false;
  }

  /// Anuncia el reto al arrancar la carrera.
  void anunciarReto(String titulo) {
    final frases = [
      'Misión activa: $titulo. El campo de batalla te espera.',
      'Reto iniciado: $titulo. Sin excusas, sin rodeos.',
      '$titulo en marcha. Demuestra de qué estás hecho.',
      'Objetivo: $titulo. Sal y conquístalo.',
    ];
    _emitirForzado(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '⚡',
      tipo: NarradorTipo.conquista,
      duracion: const Duration(seconds: 5),
    ));
  }

  /// Notifica cuando el jugador lleva el 50% de la distancia del reto.
  void eventoMitadReto(double distanciaMetros) {
    if (_objetivoRetoMetros == null || _mitadRetoNotificada) return;
    final mitad = _objetivoRetoMetros! / 2;
    if (distanciaMetros < mitad) return;
    _mitadRetoNotificada = true;

    final restanteStr = _objetivoRetoMetros! >= 2000
        ? '${((_objetivoRetoMetros! - distanciaMetros) / 1000).toStringAsFixed(1)} km'
        : '${(_objetivoRetoMetros! - distanciaMetros).toInt()} m';

    final frases = [
      'Mitad del reto. Quedan $restanteStr. No aflajes.',
      'La mitad está hecha. $restanteStr para completar la misión.',
      'A medio camino del reto. $restanteStr más y es tuyo.',
      '50% completado. Solo $restanteStr te separan del objetivo.',
    ];
    _emitirForzado(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '⚑',
      tipo: NarradorTipo.kilometro,
      duracion: const Duration(seconds: 5),
    ));
  }

  /// Aviso de tensión cuando quedan 200m o menos para completar el reto.
  void eventoFinalReto(double distanciaMetros) {
    if (_objetivoRetoMetros == null || _finalRetoNotificado) return;
    final restante = _objetivoRetoMetros! - distanciaMetros;
    if (restante > 200 || restante <= 0) return;
    _finalRetoNotificado = true;

    final restanteStr = '${restante.toInt()} m';
    final frases = [
      '¡$restanteStr para completar el reto! ¡Todo lo que tienes ahora!',
      'Solo $restanteStr. No pares. Está ahí.',
      '$restanteStr. El objetivo está a la vista. ¡Ciérralo!',
      '¡Casi! $restanteStr y el reto es tuyo. ¡Aprieta!',
    ];
    _emitirForzado(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '🎯',
      tipo: NarradorTipo.resistencia,
      duracion: const Duration(seconds: 5),
    ));
  }

  /// Anuncia que el reto ha sido completado.
  void anunciarRetoCompletado(String titulo) {
    if (_retoCompletadoEmitido) return;
    _retoCompletadoEmitido = true;

    final frases = [
      '¡$titulo completado! El mapa recuerda esto.',
      '¡Reto superado! $titulo ya es historia tuya.',
      'Misión cumplida: $titulo. Puedes seguir o recoger tus puntos.',
      '¡$titulo conquistado! Los puntos son tuyos. Tú decides si paras.',
    ];
    _emitirForzado(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '🏆',
      tipo: NarradorTipo.conquista,
      duracion: const Duration(seconds: 6),
    ));
  }

  // ==========================================================================
  // EVENTOS ORIGINALES — sin cambios
  // ==========================================================================

  void eventoKilometro(int km) {
    if (km <= _ultimoKmNotificado) return;
    _ultimoKmNotificado = km;

    final frases = _frasesKilometro(km);
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '📍',
      tipo: NarradorTipo.kilometro,
      duracion: const Duration(seconds: 5),
    ));
  }

  List<String> _frasesKilometro(int km) {
    if (km == 1) return [
      '$km km conquistado. El territorio empieza a ser tuyo.',
      '$km km. El campo de batalla se extiende.',
      'Primer kilómetro. Solo el inicio de la campaña.',
    ];
    if (km == 2) return [
      '$km km. Buen ritmo, soldado.',
      '$km kilómetros en campaña. El enemigo ya te conoce.',
      '$km km. Cada paso es territorio ganado.',
    ];
    if (km == 5) return [
      '5km. Estás forjando una leyenda.',
      '5 kilómetros. Los débiles ya se rindieron.',
      '5km completados. Tu resistencia es tu arma.',
    ];
    if (km == 10) return [
      '10km. Eres una máquina de conquista.',
      'Diez kilómetros. El mapa te pertenece.',
      '10km. Pocos llegan hasta aquí.',
    ];
    return [
      '$km km. Sigues en pie. El territorio te lo agradece.',
      '$km kilómetros. Imparable.',
      '$km km completados. La campaña continúa.',
    ];
  }

  void eventoTerritorioRival(String? ownerNickname) {
    final nombre = ownerNickname ?? 'el enemigo';
    final frases = [
      'Zona hostil. Territorio de $nombre detectado.',
      'Pisas territorio de $nombre. Actúa con decisión.',
      'Área de $nombre. ¿Vas a dejarlo pasar?',
      'Zona enemiga. $nombre no esperaba visita.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '⚔️',
      tipo: NarradorTipo.territorio,
      duracion: const Duration(seconds: 5),
    ));
  }

  void eventoTerritorioPropio() {
    final frases = [
      'Territorio asegurado. Nadie te lo quita hoy.',
      'Zona propia reforzada. Buen trabajo.',
      'Tu territorio, tu ley. Sigue adelante.',
      'Zona asegurada. El enemigo tendrá que sudar para quitártela.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '🛡️',
      tipo: NarradorTipo.refuerzo,
      duracion: const Duration(seconds: 4),
    ));
  }

  void eventoRivalCerca(String? nickname, double distanciaMetros) {
    final nombre = nickname ?? 'alguien';
    final dist   = distanciaMetros.round();
    final frases = [
      'Operativo detectado. $nombre a ${dist}m de tu posición.',
      'Alerta. $nombre está operando cerca. Cuidado con tus territorios.',
      '$nombre a ${dist} metros. Puede estar mirando lo mismo que tú.',
      'Contacto visual. $nombre en la zona.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '👁️',
      tipo: NarradorTipo.rival,
      duracion: const Duration(seconds: 5),
    ));
  }

  void eventoResistencia(int minutos) {
    final frases = [
      '$minutos minutos en campaña. Tu resistencia es tu ventaja.',
      '$minutos min. Mientras tú corres, el mapa cambia a tu favor.',
      '$minutos minutos. Pocos aguantan tanto en campo abierto.',
      '$minutos min sin rendirte. Eso se llama dominio.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '🔥',
      tipo: NarradorTipo.resistencia,
      duracion: const Duration(seconds: 4),
    ));
  }

  void eventoRitmoBajando() {
    final frases = [
      'Ritmo cayendo. Respira. El territorio te espera.',
      'Perdiendo velocidad. Normal — pero no te pares.',
      'El cuerpo pide tregua. Aguanta un poco más.',
      'Ritmo bajo. El enemigo tampoco va rápido.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '💨',
      tipo: NarradorTipo.rendimiento,
      duracion: const Duration(seconds: 4),
    ));
  }

  void eventoRitimoMejorando() {
    final frases = [
      'Acelerando. Así se conquista territorio.',
      'Ritmo en aumento. El mapa no sabe lo que se le viene.',
      'Velocidad recuperada. Imparable.',
      'Más rápido. El enemigo no puede seguirte.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '⚡',
      tipo: NarradorTipo.rendimiento,
      duracion: const Duration(seconds: 4),
    ));
  }

  void eventoConquista(String? ownerNickname) {
    final nombre = ownerNickname ?? 'el rival';
    final frases = [
      '¡Territorio de $nombre capturado! El mapa es tuyo.',
      '¡Conquista completada! $nombre acaba de perder terreno.',
      'Zona tomada. $nombre no lo verá venir hasta que sea tarde.',
      '¡Territorio arrebatado a $nombre! La campaña avanza.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '🏴',
      tipo: NarradorTipo.conquista,
      duracion: const Duration(seconds: 6),
    ));
  }

  void eventoMitad(double distanciaKm) {
    if (_mitadNotificada) return;
    _mitadNotificada = true;
    final dist = distanciaKm.toStringAsFixed(1);
    final frases = [
      '$dist km. La mitad del camino. Ahora empieza lo bueno.',
      '$dist km recorridos. Queda lo mismo — pero ya sabes que puedes.',
      'Mitad de campaña. $dist km. No mires atrás.',
    ];
    _emitir(MensajeNarrador(
      texto: frases[_rng.nextInt(frases.length)],
      emoji: '⚑',
      tipo: NarradorTipo.kilometro,
      duracion: const Duration(seconds: 5),
    ));
  }

  void analizarRitmo(double velocidadActualKmh) {
    if (_ritmoUltimos500m == 0) {
      _ritmoUltimos500m = velocidadActualKmh;
      return;
    }
    final diff = velocidadActualKmh - _ritmoUltimos500m;
    if (diff < -1.5 && velocidadActualKmh > 0.5) eventoRitmoBajando();
    if (diff > 1.5)                               eventoRitimoMejorando();
    _ritmoUltimos500m = velocidadActualKmh;
  }
}