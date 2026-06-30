// lib/pestañas/live_territory_ui.dart
// Radar, barrio chip, notifications, snackbars, shield, save route, challenge dialog, global war widgets.
// ignore_for_file: invalid_use_of_protected_member, unqualified_reference_to_static_member_of_extended_type
part of 'LiveActivity_screen.dart';

extension _LiveTerritoryUi on _LiveActivityScreenState {
  Widget _buildRadarTerritoriosProximos() {
    if (_modoSolitario || !_session.isTracking || _session.isPaused) return const SizedBox.shrink();
    if (_territoriosRivalesCercanos.isEmpty && _territorioActualBajoPie == null) {
      return const SizedBox.shrink();
    }
    final todos = [
      if (_territorioActualBajoPie != null) _territorioActualBajoPie!,
      ..._territoriosRivalesCercanos
          .where((t) => t.docId != _territorioActualBajoPie?.docId),
    ].take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: todos.map((t) {
        final bool bajoPie = t.docId == _territorioActualBajoPie?.docId;
        final Color estadoColor;
        final String estadoLabel;
        switch (t.estadoHp) {
          case EstadoHp.saludable:
            estadoColor = _kVerde; estadoLabel = 'FUERTE';
          case EstadoHp.danado:
            estadoColor = _kGold; estadoLabel = 'MEDIO';
          case EstadoHp.critico:
            estadoColor = _p.globalRed; estadoLabel = 'LEVE';
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bajoPie
                ? estadoColor.withValues(alpha: 0.18)
                : _p.parchment.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: estadoColor.withValues(alpha: bajoPie ? 0.9 : 0.45),
                width: bajoPie ? 1.5 : 1.0),
            boxShadow: bajoPie
                ? [BoxShadow(color: estadoColor.withValues(alpha: 0.3), blurRadius: 12)]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle_rounded, color: estadoColor, size: 11),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Text(bajoPie ? '¡PISANDO!' : 'CERCA',
                  style: GoogleFonts.inter(
                      color: bajoPie ? estadoColor : _p.goldDim,
                      fontSize: 8, fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (t.tieneRey) ...[
                  const Icon(Icons.workspace_premium_rounded, color: _kGoldLight, size: 9),
                  const SizedBox(width: 3),
                ],
                if (t.escudoVigente) ...[
                  const Icon(Icons.security_rounded, color: Colors.lightBlueAccent, size: 9),
                  const SizedBox(width: 3),
                ],
                Text(t.ownerNickname.length > 10
                    ? '${t.ownerNickname.substring(0, 9)}…'
                    : t.ownerNickname,
                    style: GoogleFonts.inter(
                        color: bajoPie
                            ? _kGoldLight
                            : _kGoldLight.withValues(alpha: 0.7),
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ]),
            const SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: estadoColor.withValues(alpha: 0.15),
                  border: Border.all(color: estadoColor.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(estadoLabel,
                    style: GoogleFonts.inter(color: estadoColor,
                        fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              if (t.escudoVigente && t.escudoExpira != null) ...[
                const SizedBox(height: 2),
                Text(
                  'escudo ${_horasRestantes(t.escudoExpira!)}h',
                  style: GoogleFonts.inter(
                      color: Colors.lightBlueAccent,
                      fontSize: 7, fontWeight: FontWeight.w700),
                ),
              ],
            ]),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildChipBarrioActual() {
    if (!_modoSolitario || !_session.isTracking || _barrioActual == null) {
      return const SizedBox.shrink();
    }
    final barrio = _barrioActual!;
    final pct    = barrio.porcentajeCubierto;
    final pctInt = (pct * 100).toInt();
    final Color color;
    final IconData icon;
    if (pct >= 1.0)      { color = _kVerde;      icon = Icons.emoji_events_rounded; }
    else if (pct >= 0.5) { color = _kGold;        icon = Icons.explore_rounded; }
    else if (pct > 0)    { color = _p.terracotta; icon = Icons.location_on_rounded; }
    else                 { color = _p.goldDim;    icon = Icons.explore_rounded; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _p.parchment.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 12)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(barrio.nombre,
              style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SizedBox(
            width: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value:           pct,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor:      AlwaysStoppedAnimation(color),
                minHeight:       4,
              ),
            ),
          ),
        ]),
        const SizedBox(width: 8),
        Text('$pctInt%',
            style: GoogleFonts.orbitron(color: color,
                fontSize: 12, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  void _mostrarNotificacionBarrioCompletado(_BarrioData barrio, int bonusMonedas) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), () { if (mounted) HapticFeedback.heavyImpact(); });
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) HapticFeedback.heavyImpact(); });
    Future.delayed(const Duration(milliseconds: 450), () { if (mounted) HapticFeedback.heavyImpact(); });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A3A1A), Color(0xFF4CAF50)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kVerde, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _kVerde.withValues(alpha: 0.55), blurRadius: 28)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏆', style: TextStyle(fontSize: 42)),
          const SizedBox(height: 8),
          Text('¡BARRIO CONQUISTADO!', textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 16,
                  fontWeight: FontWeight.w900, letterSpacing: 2.5)),
          const SizedBox(height: 4),
          Text(barrio.nombre.toUpperCase(), textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white,
                  fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Has conquistado el 100% de este barrio',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              border: Border.all(color: _kVerde.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on_rounded, color: _kGoldLight, size: 20),
              const SizedBox(width: 8),
              Text('+$bonusMonedas BONUS',
                  style: GoogleFonts.orbitron(color: _kGoldLight,
                      fontSize: 16, fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
            ]),
          ),
        ]),
      ),
    ));
  }

  int _horasRestantes(DateTime expira) =>
      expira.difference(DateTime.now()).inHours.clamp(0, 999);

  void _mostrarSnackRefuerzo(TerritoryData territorio) {
    if (!mounted) return;
    final String mensaje;
    final IconData icono;
    switch (territorio.estadoHp) {
      case EstadoHp.critico:
        mensaje = '¡Territorio estabilizado a estado Medio!'; icono = Icons.build_rounded;
      case EstadoHp.danado:
        mensaje = '¡Territorio reforzado a estado Fuerte!'; icono = Icons.security_rounded;
      case EstadoHp.saludable:
        mensaje = '¡Territorio en perfecto estado!'; icono = Icons.check_circle_rounded;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: territorio.escudoVigente ? 2 : 5),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).padding.bottom + 110),
      content: _snackWrap(
        color:  _p.parchMid,
        border: Border.all(color: _kGold.withValues(alpha: 0.55)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(icono, color: _kGoldLight, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje,
                style: const TextStyle(color: _kGoldLight,
                    fontWeight: FontWeight.bold, fontSize: 13))),
            if (territorio.escudoVigente && territorio.escudoExpira != null) ...[
              const Icon(Icons.security_rounded, color: Colors.lightBlueAccent, size: 14),
              const SizedBox(width: 4),
              Text('${_horasRestantes(territorio.escudoExpira!)}h',
                  style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ]),
          if (!territorio.escudoVigente) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.security_rounded, color: Colors.lightBlueAccent, size: 12),
              const SizedBox(width: 6),
              Text('Proteger con escudo:',
                  style: GoogleFonts.inter(
                      color: _p.goldDim, fontSize: 10, fontWeight: FontWeight.w700)),
              const Spacer(),
              ...TerritoryService.kPreciosEscudo.entries.map((e) =>
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () async {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      await _activarEscudo(territorio.docId, e.key, e.value);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: _p.goldDim.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _kGold.withValues(alpha: 0.5)),
                      ),
                      child: Text('${e.key}h · ${e.value} pts',
                          style: GoogleFonts.inter(
                              color: _kGold,
                              fontSize: 9,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    ));
  }

  Future<void> _activarEscudo(
      String territorioId, int horas, int precio) async {
    if (!mounted) return;
    try {
      await TerritoryService.activarEscudo(
          territorioId: territorioId, horas: horas);
      if (!mounted) return;
      final nuevos = await TerritoryService.cargarTodosLosTerritorios(
          modo: _modoSolitario ? 'solitario' : 'competitivo');
      if (_modoSolitario) {
        GameStateService.instance.setSolitarioTerritories(nuevos);
      } else {
        GameStateService.instance.setCompetitiveTerritories(nuevos);
      }
      if (!mounted) return;
      setState(() => _territorios = nuevos);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: _snackWrap(
          color: const Color(0xFF0D1A2A),
          border: Border.all(
              color: Colors.lightBlueAccent.withValues(alpha: 0.6)),
          child: Row(children: [
            const Icon(Icons.security_rounded, color: Colors.lightBlueAccent, size: 18),
            const SizedBox(width: 10),
            Text('¡Escudo activado $horas horas por $precio pts!',
                style: const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
        ),
      ));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _mostrarError(e.message ?? 'Error al activar el escudo.');
    }
  }

  // ==========================================================================
  // GUARDAR RUTA LIBRE (modo Ruta)
  // ==========================================================================
  Future<void> _guardarRutaLibre(
      List<LatLng> ruta, Duration tiempo, double distanciaKm) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || distanciaKm <= 0) {
      _stopping = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sesión no guardada: inicia sesión para registrar tu actividad.'),
          backgroundColor: Colors.red,
        ));
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
      return;
    }

    final ritmoMinKm = tiempo.inSeconds > 0 && distanciaKm > 0
        ? (tiempo.inSeconds / 60.0) / distanciaKm
        : 0.0;
    final esPremium  = SubscriptionService.currentStatus.isPremium;
    final recompensa = RouteService.calcularRecompensa(
      distanciaKm: distanciaKm,
      ritmoMinKm:  ritmoMinKm,
      esPremium:   esPremium,
      boostActivo: _boostXpActivo,
    );

    // Popup para nombrar la ruta (opcional)
    String? nombreElegido;
    if (mounted) {
      final ctrl = TextEditingController();
      await showCupertinoDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('¿Cómo llamamos a esta ruta?'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CupertinoTextField(
              controller: ctrl,
              placeholder: 'Nombre opcional',
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sin nombre'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                nombreElegido = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
                Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    }

    String? routeId;
    try {
      routeId = await RouteService.guardarRuta(
        userId:        user.uid,
        ownerNickname: _miNickname,
        color:         _colorTerritorio,
        coords:        ruta,
        distanciaKm:   distanciaKm,
        tiempoSeg:     tiempo.inSeconds,
        ritmoMinKm:    ritmoMinKm,
        monedas:       recompensa.monedas,
        puntosLiga:    recompensa.puntosLiga,
        nombre:        nombreElegido,
      );
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'guardar_ruta');
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Error al guardar la ruta'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }

    if (recompensa.puntosLiga > 0) {
      LeagueService.sumarPuntosLiga(user.uid, recompensa.puntosLiga)
          .catchError((Object e, StackTrace st) {
            debugPrint('LeagueService ruta: $e');
            FirebaseCrashlytics.instance.recordError(e, st, reason: 'sumarPuntosLiga_ruta');
            return null;
          });
    }

    if (_retoActivo != null) {
      DesafiosService.acumularPuntos(
        uid:                     user.uid,
        distanciaKm:             distanciaKm,
        territoriosConquistados: 0,
      );
      DesafiosService.verificarExpirados(user.uid);
    }

    await HealthService.registrarCarrera(
      inicio: DateTime.now().subtract(tiempo),
      fin:    DateTime.now(),
      distanciaKm: distanciaKm,
    );

    // Si era una ruta guiada, registrar que fue corrida
    if (_rutaGuiada != null) {
      RouteService.registrarCorrida(_rutaGuiada!.id)
          .catchError((Object e, StackTrace st) {
            debugPrint('registrarCorrida: $e');
            FirebaseCrashlytics.instance.recordError(e, st, reason: 'registrarCorrida_ruta');
          });
    }

    _stopping = false;

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/resumen', arguments: {
        'distancia':            distanciaKm,
        'tiempo':               tiempo,
        'ruta':                 ruta,
        'esDesdeCarrera':       true,
        'territoriosConquistados': 0,
        'puntosLigaGanados':    recompensa.puntosLiga,
        'modoRuta':             true,
        'modoInicial':          'ruta',
        'routeId':              routeId,
        'monedasRuta':          recompensa.monedas,
        'splitsPorKm':          List<double>.from(_session.splits),
        'velocidadMaxima':      _session.velocidadMaxKmh,
        'elevacionGanada':      _session.elevacionGanada,
        'elevacionPerdida':     _session.elevacionPerdida,
      });
    }
  }

  // Muestra dialog de confirmación antes de salir del modo ruta con reto activo.
  // Devuelve true si el cambio debe proceder (sin reto o usuario confirmó cancelarlo).
  Future<bool> _confirmarCancelacionReto(String modoLabel) async {
    if (_retoActivo == null) return true;
    final titulo = _retoActivo!['titulo'] as String? ?? 'Reto activo';
    final confirmar = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Cambiar de modo'),
        content: Text('Si cambias a $modoLabel, el reto "$titulo" se cancelará.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Quedarse en Ruta'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cambiar a $modoLabel'),
          ),
        ],
      ),
    ) ?? false;
    if (confirmar && mounted) setState(() => _retoActivo = null);
    return confirmar;
  }

  Widget _snackWrap({
    Widget? child, Gradient? gradient, Color? color,
    BoxBorder? border, Color shadow = Colors.transparent,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: gradient, color: color,
          borderRadius: BorderRadius.circular(14), border: border,
          boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.4), blurRadius: 12)],
        ),
        child: child,
      );

  // ==========================================================================
  // GUERRA GLOBAL — widgets
  // ==========================================================================
  Widget _buildChipObjetivoGlobal() {
    final nombre      = _objetivoGlobal?['territorioNombre'] as String? ?? 'Territorio';
    final progreso    = _progresoGlobal;

    if (_globalConquistado) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _kVerde.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kVerde.withValues(alpha: 0.7)),
          boxShadow: [BoxShadow(color: _kVerde.withValues(alpha: 0.35), blurRadius: 16)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('✅', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Text('¡$nombre CONQUISTADO!',
              style: GoogleFonts.cinzel(color: _kVerde, fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ]),
      );
    }

    if (_globalKmAlcanzados) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _kGold.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGold.withValues(alpha: 0.8)),
          boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.40), blurRadius: 18)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏁', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text('¡META ALCANZADA!',
                style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 11,
                    fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            Text('Finaliza la carrera para reclamar',
                style: GoogleFonts.inter(color: _kGold, fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ]),
        ]),
      );
    }

    final kmRestantes = _kmRestantesGlobal;
    final restanteStr = kmRestantes >= 1
        ? '${kmRestantes.toStringAsFixed(2)} km'
        : '${(kmRestantes * 1000).toInt()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _p.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _p.globalRed.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: _p.globalRed.withValues(alpha: 0.25), blurRadius: 14)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.flash_on_rounded, color: _p.globalRed, size: 13),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(nombre, style: GoogleFonts.inter(color: _kGoldLight,
              fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progreso,
                backgroundColor: _p.globalRed.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(_p.globalRed),
                minHeight: 4,
              ),
            ),
          ),
        ]),
        const SizedBox(width: 8),
        Text(restanteStr,
            style: GoogleFonts.orbitron(color: _kGoldLight,
                fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _buildConquistadoOverlay() => Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: _p.ink,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kGold.withValues(alpha: 0.5)),
              boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.2), blurRadius: 30)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 36, height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kGold)),
              const SizedBox(height: 16),
              Text('CONQUISTANDO...',
                  style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 14,
                      fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text(_objetivoGlobal?['territorioNombre'] as String? ?? '',
                  style: GoogleFonts.inter(color: _kGold, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  // ==========================================================================
  // CHIP RETO ACTIVO
  // ==========================================================================
  Widget _buildChipRetoActivo() {
    final objetivoMetros  = (_retoActivo!['objetivo_valor'] as num?)?.toDouble() ?? 0;
    final distanciaMetros = _session.distanciaTotal * 1000;
    final progreso = objetivoMetros > 0
        ? (distanciaMetros / objetivoMetros).clamp(0.0, 1.0)
        : 0.0;
    final restanteM   = (objetivoMetros - distanciaMetros).clamp(0.0, objetivoMetros);
    final restanteStr = restanteM >= 1000
        ? '${(restanteM / 1000).toStringAsFixed(2)} km'
        : '${restanteM.toInt()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _p.parchment.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.20), blurRadius: 12)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('⚡', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(_retoActivo!['titulo'] as String? ?? 'Reto activo',
              style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progreso,
                backgroundColor: _p.goldDim.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(_kGold),
                minHeight: 4,
              ),
            ),
          ),
        ]),
        const SizedBox(width: 8),
        Text(restanteStr,
            style: GoogleFonts.orbitron(color: _kGoldLight,
                fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}
