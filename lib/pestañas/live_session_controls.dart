// lib/pestañas/live_session_controls.dart
// HUD, chip builders, botonera, control buttons, global territory management.
// ignore_for_file: invalid_use_of_protected_member, unqualified_reference_to_static_member_of_extended_type
part of 'LiveActivity_screen.dart';

extension _LiveSessionControls on _LiveActivityScreenState {

  Widget _buildHUD() {
    if (!_session.isTracking) return const SizedBox.shrink();
    if (_hudMinimizado && !_session.isPaused) return _buildHUDMiniClasico();
    return _buildHUDClasico();
  }

  Widget _buildHUDClasico() {
    return GestureDetector(
      onTap: () => setState(() => _hudMinimizado = true),
      child: FadeTransition(
      opacity: _hudFade,
      child: AnimatedBuilder(
        animation: _pulsoAnim,
        builder: (_, child) => Container(
          margin:  const EdgeInsets.fromLTRB(14, 50, 14, 0),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.10 + _pulso.value * 0.06),
                width: 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.40), blurRadius: 12),
            ],
          ),
          child: child,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _hudStat('KM', _session.distanciaTotal.toStringAsFixed(2), _kGold),
            _hudDivider(),
            _hudStat('MIN/KM', _ritmoStr, _kWaterLight),
            _hudDivider(),
            _buildStatTimer(),
            if (_objetivoGlobal != null) ...[
              _hudDivider(),
              _hudStat('META', '${(_progresoGlobal * 100).toInt()}%',
                  _globalConquistado ? _kVerde : _p.globalRed),
            ] else if (_rutaGuiada != null) ...[
              _hudDivider(),
              _hudStat('RUTA', '${(_session.porcentajeRuta * 100).toInt()}%',
                  _session.rutaCompletada ? _kVerde : _kWaterLight),
            ] else if (_modoSolitario) ...[
              _hudDivider(),
              _hudStat(
                'ZONA',
                _barrioActual != null
                    ? '${(_barrioActual!.porcentajeCubierto * 100).toInt()}%'
                    : '--',
                _kVerde,
              ),
            ] else if (!_modoRuta) ...[
              _hudDivider(),
              _hudStat('ZONAS', '${_territoriosVisitadosEnSesion.length}', _kWaterLight),
            ],
            if (_boostXpActivo) ...[
              _hudDivider(),
              _hudStat('BOOST', '×2', _kGoldLight),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildHUDMiniClasico() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 50, 18, 0),
        child: GestureDetector(
          onTap: () => setState(() => _hudMinimizado = false),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(_session.distanciaTotal.toStringAsFixed(2),
                    style: GoogleFonts.rajdhani(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 18,
                        letterSpacing: 0.5,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                Text(' km', style: GoogleFonts.rajdhani(
                    color: AppColors.gold.withValues(alpha: 0.65),
                    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.15)),
                Text(_ritmoStr,
                    style: GoogleFonts.rajdhani(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 18,
                        letterSpacing: 0.5,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                Text(' /km', style: GoogleFonts.rajdhani(
                    color: AppColors.gold.withValues(alpha: 0.65),
                    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                if (_objetivoGlobal != null) ...[
                  Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.15)),
                  Text('${(_progresoGlobal * 100).toInt()}%',
                      style: TextStyle(color: _globalConquistado ? _kVerde : Colors.white,
                          fontWeight: FontWeight.w300, fontSize: 15)),
                ] else if (_rutaGuiada != null) ...[
                  Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.15)),
                  Text('${(_session.porcentajeRuta * 100).toInt()}%',
                      style: TextStyle(color: _session.rutaCompletada ? _kVerde : Colors.white,
                          fontWeight: FontWeight.w300, fontSize: 15)),
                ] else if (_modoSolitario) ...[
                  Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.15)),
                  Text(
                    _barrioActual != null
                        ? '${(_barrioActual!.porcentajeCubierto * 100).toInt()}%'
                        : 'SOLO',
                    style: const TextStyle(color: Color(0xFF30D158),
                        fontWeight: FontWeight.w500, fontSize: 11, letterSpacing: 0.8)),
                ] else if (!_modoRuta) ...[
                  Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.15)),
                  Text('${_territoriosVisitadosEnSesion.length}',
                      style: const TextStyle(color: _kWaterLight,
                          fontWeight: FontWeight.w300, fontSize: 15)),
                ],
                Icon(CupertinoIcons.chevron_down, color: Colors.white.withValues(alpha: 0.35), size: 14),
              ],
            ),
          ),
        ),
      );

  Widget _hudStat(String label, String valor, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.rajdhani(
            color: AppColors.gold.withValues(alpha: 0.65),
            fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const SizedBox(height: 2),
        Text(valor, style: GoogleFonts.rajdhani(
            color: color,
            fontSize: valor.length > 5 ? 16 : 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontFeatures: const [FontFeature.tabularFigures()])),
      ]);

  Widget _hudDivider() =>
      Container(width: 1, height: 32, color: _p.goldDim.withValues(alpha: 0.35));

  Widget _buildStatTimer() => CustomTimer(
        controller: _timerController,
        builder: (state, remaining) {
          final str = _session.isTracking
              ? '${remaining.hours}:${remaining.minutes.toString().padLeft(2,'0')}:${remaining.seconds.toString().padLeft(2,'0')}'
              : '--:--:--';
          return _hudStat('TIEMPO', str, _session.isPaused ? _p.goldDim : _kWaterLight);
        },
      );

  Widget _buildTimerGrande() => IgnorePointer(
        child: CustomTimer(
          controller: _timerController,
          builder: (_, remaining) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Text(
              '${remaining.hours.toString().padLeft(2,'0')}:${remaining.minutes.toString().padLeft(2,'0')}:${remaining.seconds.toString().padLeft(2,'0')}',
              style: GoogleFonts.rajdhani(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );

  Widget _buildChips() {
    if (!_session.isTracking) return const SizedBox.shrink();
    if (_modoRuta) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_rutaGuiada != null) ...[
          _chip('${(_session.porcentajeRuta * 100).toInt()}% completado', _kVerde, Icons.route_rounded),
          const SizedBox(height: 8),
          _chip('${_rutaGuiada!.distanciaKm.toStringAsFixed(1)} km total', _kWaterLight, Icons.straighten),
        ] else ...[
          _chip('Ruta libre', _kWaterLight, Icons.route_rounded),
          if (_session.distanciaTotal > 0) ...[
            const SizedBox(height: 8),
            _chip('${_session.distanciaTotal.toStringAsFixed(2)} km', _kVerde, Icons.straighten),
          ],
        ],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!_modoRuta && routePoints.length >= 3) ...[
        _chip(
          _zonaValida ? 'Zona válida' : 'Zona pequeña',
          _zonaValida ? _kVerde : const Color(0xFF636366),
          _zonaValida ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded,
        ),
        const SizedBox(height: 8),
      ],
      if (_territoriosCargados)
        _chip('${_territorios.length} territorios', _kGold, Icons.map_rounded),
      if (!_modoSolitario && _jugadoresActivos.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_jugadoresActivos.length} cerca', _kWater, Icons.directions_run_rounded),
      ],
      if (_territoriosVisitadosEnSesion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_territoriosVisitadosEnSesion.length} reforzados', _kVerde, Icons.shield_rounded),
      ],
      if (!_modoSolitario && _territoriosNotificadosEnSesion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_territoriosNotificadosEnSesion.length} invadidos', _p.terracotta, Icons.warning_amber_rounded),
      ],
      if (_globalConquistado) ...[
        const SizedBox(height: 8),
        _chip('Conquistado', _kVerde, Icons.flag_rounded),
      ],
    ]);
  }

  Widget _chip(String texto, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 5),
          Text(texto, style: GoogleFonts.inter(color: Colors.white,
              fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _buildBotonesMapa() => Column(children: [
        _botonMapa(_modoNoche ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
            _modoNoche ? _kGoldLight : _kGold, _toggleModoNoche),
        if (_session.isTracking) ...[
          const SizedBox(height: 10),
          _botonMapa(Icons.my_location_rounded, _p.terracotta, () {
            if (_currentPosition != null) {
              _moverCamara(lat: _currentPosition!.latitude,
                  lng: _currentPosition!.longitude,
                  zoom:    _session.isPaused ? _kZoomPausado  : _kZoomCorrer,
                  pitch:   _session.isPaused ? _kPitchPausado : _kPitchCorrer,
                  bearing: _bearing, forzar: true);
            }
          }),
        ],
      ]);

  Widget _botonMapa(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _p.parchment.withValues(alpha: 0.90),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10),
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
            ],
          ),
          child: Center(child: Icon(icon, color: color, size: 20)),
        ),
      );

  Widget _buildCuentaAtras() => Positioned.fill(
        child: IgnorePointer(
          child: Container(
            color: Colors.black.withValues(alpha: 0.55),
            child: Center(
              child: ScaleTransition(
                scale: _cuentaAtrasScale,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_cuentaAtras > 0) ...[
                    Text(
                      '$_cuentaAtras',
                      style: GoogleFonts.inter(
                        fontSize: 120,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -4,
                        shadows: [
                          Shadow(
                              blurRadius: 40,
                              color: _kGold.withValues(alpha: 0.6)),
                          const Shadow(blurRadius: 6, color: Colors.black),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final active = i < _cuentaAtras;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ] else
                    Text(
                      _modoSolitario ? '🗺️'
                          : _objetivoGlobal != null ? '⚔️' : '⚔️',
                      style: const TextStyle(fontSize: 80),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _buildBotonera() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, 18, 20, _session.isTracking ? 38 : 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [
                  _session.isTracking
                      ? Colors.black.withValues(alpha: 0.72)
                      : _kUniverseBg.withValues(alpha: 0.97),
                  _session.isTracking
                      ? Colors.black.withValues(alpha: 0.35)
                      : _kUniverseBg.withValues(alpha: 0.80),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: SafeArea(
              top: false,
              bottom: _session.isTracking,
              child: !_session.isTracking ? _buildSelectorModo() : _buildBotonesControl(),
            ),
          ),
          if (!_session.isTracking) const CustomBottomNavbar(currentIndex: 1),
        ],
      );

  Future<void> _elegirTerritorioGlobal() async {
    HapticFeedback.mediumImpact();
    _modoAnteriorGlobal = _modoSolitario ? 'solitario' : 'competitivo';
    _limpiarRutasPreview();
    _limpiarCapasBarrios();
    setState(() => _modeCtrl.switchToGlobal());
    if (_terrGlobales.isEmpty && !_cargandoGlobales) {
      await _cargarGlobales();
    }
    await _actualizarGlobalesEnGlobo(visible: true);
    if (!kIsWeb && _mapboxMap != null) {
      await _moverCamara(lat: 15, lng: 10, zoom: 1.0, pitch: 0, bearing: 0, animated: true, forzar: true);
    }
  }

  Future<void> _cargarGlobales() async {
    if (!mounted) return;

    // Usar cache compartido si sigue siendo válido
    final cached = GameStateService.instance.getGlobalTerritories();
    if (cached != null && mounted) {
      setState(() { _terrGlobales = List<GlobalTerritory>.from(cached); _cargandoGlobales = false; });
      return;
    }

    setState(() => _cargandoGlobales = true);
    try {
      final list = await TerritoryService.cargarGlobalesActivos();
      if (!mounted) return;
      if (list.isEmpty) list.addAll(buildSampleGlobalTerritories());
      GameStateService.instance.setGlobalTerritories(list);
      if (mounted) setState(() { _terrGlobales = list; _cargandoGlobales = false; });
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'cargar_territorios_globales');
      debugPrint('Error cargando globales: $e');
      if (mounted) setState(() { _terrGlobales = buildSampleGlobalTerritories(); _cargandoGlobales = false; });
    }
  }

  Future<void> _actualizarGlobalesEnGlobo({required bool visible}) async {
    if (kIsWeb || _mapboxMap == null) return;
    try {
      final vis = visible ? 'visible' : 'none';
      if (!_globalesLayerCreated) {
        if (!visible || _terrGlobales.isEmpty) return;
        final feats = _terrGlobales.map((t) {
          final ch = _colorToHex(t.displayColor);
          return '{"type":"Feature","properties":{"color":"$ch"},'
              '"geometry":{"type":"Point","coordinates":[${t.center.longitude},${t.center.latitude}]}}';
        }).join(',');
        final gj = '{"type":"FeatureCollection","features":[$feats]}';
        await _mapboxMap!.style.addSource(mapbox.GeoJsonSource(id: _LiveActivityScreenState._globalesSourceId, data: gj));
        await _mapboxMap!.style.addLayer(mapbox.CircleLayer(id: _LiveActivityScreenState._globalesLayerId, sourceId: _LiveActivityScreenState._globalesSourceId));
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-color', '#08080B');
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-opacity', 0.90);
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-radius',
            ['interpolate', ['linear'], ['zoom'], 0, 4.0, 3, 8.0, 6, 7.0, 18, 6.0]);
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-stroke-width', 2.0);
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-stroke-color', ['get', 'color']);
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-stroke-opacity', 0.92);
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'circle-blur', 0.0);
        _globalesLayerCreated = true;
      } else {
        if (visible && _terrGlobales.isNotEmpty) {
          final feats = _terrGlobales.map((t) {
            final ch = _colorToHex(t.displayColor);
            return '{"type":"Feature","properties":{"color":"$ch"},'
                '"geometry":{"type":"Point","coordinates":[${t.center.longitude},${t.center.latitude}]}}';
          }).join(',');
          final gj = '{"type":"FeatureCollection","features":[$feats]}';
          final src = await _mapboxMap!.style.getSource(_LiveActivityScreenState._globalesSourceId) as mapbox.GeoJsonSource?;
          await src?.updateGeoJSON(gj);
        }
        await _mapboxMap!.style.setStyleLayerProperty(_LiveActivityScreenState._globalesLayerId, 'visibility', vis);
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'globales_globo');
    }
  }

  Future<void> _actualizarGlobalSeleccionado(GlobalTerritory? t) async {
    if (kIsWeb || _mapboxMap == null) return;
    _globalesPulseTimer?.cancel();
    _globalesPulseTimer = null;

    if (t == null) {
      if (_globalesSelLayerCreated) {
        try {
          await _mapboxMap!.style.setStyleLayerProperty(
              _LiveActivityScreenState._globalesSelLayerId, 'visibility', 'none');
        } catch (_) {}
      }
      return;
    }

    final ch  = _colorToHex(t.displayColor);
    final gj  = '{"type":"FeatureCollection","features":['
        '{"type":"Feature","properties":{"color":"$ch"},'
        '"geometry":{"type":"Point","coordinates":[${t.center.longitude},${t.center.latitude}]}}]}';

    try {
      if (!_globalesSelLayerCreated) {
        try { await _mapboxMap!.style.removeStyleLayer(_LiveActivityScreenState._globalesSelLayerId); } catch (_) {}
        try { await _mapboxMap!.style.removeStyleSource(_LiveActivityScreenState._globalesSelSourceId); } catch (_) {}
        await _mapboxMap!.style.addSource(
            mapbox.GeoJsonSource(id: _LiveActivityScreenState._globalesSelSourceId, data: gj));
        await _mapboxMap!.style.addLayer(
            mapbox.CircleLayer(id: _LiveActivityScreenState._globalesSelLayerId, sourceId: _LiveActivityScreenState._globalesSelSourceId));
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-color', 'rgba(0,0,0,0)');
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-stroke-color', ['get', 'color']);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-stroke-width', 2.5);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-blur', 0.2);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-radius', 14.0);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-stroke-opacity', 0.7);
        _globalesSelLayerCreated = true;
      } else {
        final src = await _mapboxMap!.style
            .getSource(_LiveActivityScreenState._globalesSelSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(gj);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-stroke-color', ['get', 'color']);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'visibility', 'visible');
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'sel_globales_layer');
      return;
    }

    // Pulse animation via periodic timer
    _globalesPulseT = 0.0;
    _globalesPulseTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!mounted || _mapboxMap == null || _globalesPulseUpdating) return;
      _globalesPulseUpdating = true;
      _globalesPulseT += 0.44;
      final r  = 14.0 + 6.0 * math.sin(_globalesPulseT);
      final op = 0.50 + 0.40 * math.sin(_globalesPulseT);
      try {
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-radius', r);
        await _mapboxMap!.style.setStyleLayerProperty(
            _LiveActivityScreenState._globalesSelLayerId, 'circle-stroke-opacity', op.clamp(0.0, 1.0));
      } catch (_) {}
      _globalesPulseUpdating = false;
    });
  }

  Future<void> _flyToTerritorioGlobal(GlobalTerritory t) async {
    HapticFeedback.selectionClick();
    setState(() => _terrPreviseleccionado = t);
    if (!kIsWeb && _mapboxMap != null) {
      await _moverCamara(lat: t.center.latitude, lng: t.center.longitude, zoom: 3.5, pitch: 0, bearing: 0, animated: true, forzar: true);
    }
    _actualizarGlobalSeleccionado(t);
  }

  void _seleccionarTerritorioGlobal(GlobalTerritory t) {
    HapticFeedback.mediumImpact();
    _actualizarGlobalSeleccionado(null);
    GameStateService.instance.currentMode = 'global';
    _modeCtrl.setObjetivoGlobal({
      'territorioId':     t.id,
      'territorioNombre': t.epicName,
      'kmRequeridos':     t.kmRequired,
      'recompensa':       t.rewardActual,
      'ownerUid':         t.ownerUid,
    });
    _modeCtrl.resetConquistaGlobal();
    setState(() {
      _seleccionandoGlobal   = false;
      _terrPreviseleccionado = null;
      _modoSolitario         = false;
    });
    _actualizarGlobalesEnGlobo(visible: false);
    final kmReq = t.kmRequired;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _narrador.anunciarReto('⚔️ Objetivo: conquistar ${t.epicName} — ${kmReq.toStringAsFixed(1)} km');
    });
  }

  void _cancelarSeleccionGlobal() {
    _actualizarGlobalSeleccionado(null);
    setState(() {
      _seleccionandoGlobal = false;
      _terrPreviseleccionado = null;
    });
    _actualizarGlobalesEnGlobo(visible: false);
    _restaurarModoAnteriorGlobal();
  }

  Future<void> _restaurarModoAnteriorGlobal() async {
    final modo = _modoAnteriorGlobal;
    GameStateService.instance.currentMode = modo;
    if (modo == 'solitario') {
      setState(() => _modeCtrl.switchToSolitario());
    } else {
      setState(() => _modeCtrl.switchToCompetitivo());
    }
    _dibujarTerritoriosEnMapa();
    final centro = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : null;
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios(
              centro: centro, modo: modo)
          .timeout(const Duration(seconds: 20));
      if (!mounted || GameStateService.instance.currentMode != modo) return;
      setState(() => _modeCtrl.onTerritoriosCargados(lista));
      if (modo == 'solitario') {
        GameStateService.instance.setSolitarioTerritories(lista);
      } else {
        GameStateService.instance.setCompetitiveTerritories(lista);
      }
      _dibujarTerritoriosEnMapa();
    } catch (_) {
      if (mounted && GameStateService.instance.currentMode == modo) {
        setState(() => _modeCtrl.onTerritoriosCargados([]));
      }
    }
  }

  Widget _buildBotonesControl() => Row(children: [
        GestureDetector(
          onTap: togglePause,
          child: Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              color: _p.parchMid, shape: BoxShape.circle,
              border: Border.all(color: _p.goldDim.withValues(alpha: 0.55), width: 1.5),
              boxShadow: [
                BoxShadow(color: _kGold.withValues(alpha: 0.12), blurRadius: 12),
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 5),
              ],
            ),
            child: Center(
                child: Icon(
                  _session.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: _p.ink, size: 28)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: GestureDetector(
            onTap: stopTracking,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 19),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Center(
                child: Text(
                  _modoSolitario ? 'Finalizar'
                      : _objetivoGlobal != null
                          ? (_globalConquistado ? 'Misión cumplida' : 'Retirada')
                          : 'Retirada',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600,
                      color: Colors.white, letterSpacing: 0.3),
                ),
              ),
            ),
          ),
        ),
      ]);
}

