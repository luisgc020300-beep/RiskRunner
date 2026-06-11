import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'anticheat_service.dart';
import 'run_session_notifier.dart';

// ── Events ─────────────────────────────────────────────────────────────────────

sealed class TrackingEvent {}

class GpsPointEvent extends TrackingEvent {
  final Position position;
  final LatLng punto;
  final double bearing;

  GpsPointEvent({
    required this.position,
    required this.punto,
    required this.bearing,
  });
}

class AntiCheatCancelEvent extends TrackingEvent {
  final String motivo;
  AntiCheatCancelEvent(this.motivo);
}

class GpsErrorEvent extends TrackingEvent {}

// ── Service ────────────────────────────────────────────────────────────────────

class TrackingService {
  final RunSessionNotifier _session;
  final AntiCheatService _antiCheat;

  LatLng? _lastPoint;
  Position? _lastPosForSpeed;
  double? _lastAltitude;
  double _lastBearing = 0.0;

  static const _kGpsSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 8,
  );

  final _controller = StreamController<TrackingEvent>.broadcast();
  Stream<TrackingEvent> get events => _controller.stream;

  StreamSubscription<Position>? _sub;

  final Stream<Position> Function() _positionStreamFactory;

  TrackingService({
    required RunSessionNotifier session,
    required AntiCheatService antiCheat,
    Stream<Position> Function()? positionStreamFactory,
  })  : _session = session,
        _antiCheat = antiCheat,
        _positionStreamFactory = positionStreamFactory ??
            (() => Geolocator.getPositionStream(locationSettings: _kGpsSettings));

  void start() {
    _sub?.cancel();
    _sub = _positionStreamFactory()
        .listen(_onPosition, onError: (_) => _controller.add(GpsErrorEvent()));
  }

  void pause() {
    _sub?.cancel();
    _sub = null;
  }

  void resume() => start();

  void stop() {
    _sub?.cancel();
    _sub = null;
    _lastPoint = null;
    _lastPosForSpeed = null;
    _lastAltitude = null;
    _lastBearing = 0.0;
  }

  void dispose() {
    stop();
    _controller.close();
  }

  void _onPosition(Position pos) {
    if (_session.isPaused) return;

    final acResultado = _antiCheat.analizarPunto(pos);
    if (!acResultado.esValido) {
      if (_antiCheat.sesionCancelada) {
        _controller.add(AntiCheatCancelEvent(
          acResultado.detalle ?? 'Actividad sospechosa detectada',
        ));
      }
      return;
    }

    final newPt   = LatLng(pos.latitude, pos.longitude);
    double newDist    = _session.distanciaTotal;
    double newVel     = _session.velocidadKmh;
    double newVMax    = _session.velocidadMaxKmh;
    double newEG      = _session.elevacionGanada;
    double newEP      = _session.elevacionPerdida;
    double newBearing = _lastBearing;

    if (_lastPoint != null) {
      final dist = Geolocator.distanceBetween(
        _lastPoint!.latitude, _lastPoint!.longitude,
        newPt.latitude, newPt.longitude,
      );
      newDist   += dist / 1000;
      newBearing = _calcularBearing(_lastPoint!, newPt);

      if (_lastPosForSpeed != null) {
        final dt = pos.timestamp
                .difference(_lastPosForSpeed!.timestamp)
                .inMilliseconds /
            3600000.0;
        if (dt > 0) {
          final vel = (dist / 1000) / dt;
          newVel = (newVel * 0.6 + vel * 0.4).clamp(0, 40);
          if (newVel > newVMax) newVMax = newVel;
        }
      }

      final alt = pos.altitude;
      if (_lastAltitude != null) {
        final delta = alt - _lastAltitude!;
        if (delta > 0.5) {
          newEG += delta;
        } else if (delta < -0.5) {
          newEP += delta.abs();
        }
      }
      _lastAltitude = alt;
    }

    _session.updateGpsMetrics(
      distanciaTotal:   newDist,
      velocidadKmh:     newVel,
      velocidadMaxKmh:  newVMax,
      elevacionGanada:  newEG,
      elevacionPerdida: newEP,
    );

    _lastPoint       = newPt;
    _lastPosForSpeed = pos;
    _lastBearing     = newBearing;

    _controller.add(GpsPointEvent(
      position: pos,
      punto:    newPt,
      bearing:  newBearing,
    ));
  }

  static double _calcularBearing(LatLng a, LatLng b) {
    final lat1 = a.latitude  * math.pi / 180;
    final lat2 = b.latitude  * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
