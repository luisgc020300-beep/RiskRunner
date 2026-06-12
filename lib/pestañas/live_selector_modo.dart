// lib/pestañas/live_selector_modo.dart
// Selector de modo, shimmer, botón de modo y selector de estilo de mapa.
// ignore_for_file: invalid_use_of_protected_member
part of 'liveactivity_screen.dart';

extension _LiveSelectorModo on _LiveActivityScreenState {

  Widget _buildSelectorModo() {
    // ── Selección de territorio global en el globo ──────────────────────────
    if (_seleccionandoGlobal) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          GestureDetector(
            onTap: _cancelarSeleccionGlobal,
            child: const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
            ),
          ),
          Text('ELIGE TU OBJETIVO', style: GoogleFonts.inter(
              color: _kGold, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 10),
        if (_cargandoGlobales)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CupertinoActivityIndicator(color: Colors.white),
          )
        else if (_terrGlobales.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Sin territorios disponibles',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12)),
          )
        else ...[
          SizedBox(
            height: 160,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _terrGlobales.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final t = _terrGlobales[i];
                final isMine = t.ownerUid != null && t.ownerUid == uid;
                final isPrev = _terrPreviseleccionado?.id == t.id;
                return GestureDetector(
                  onTap: () => _flyToTerritorioGlobal(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isPrev
                          ? t.displayColor.withValues(alpha: 0.15)
                          : t.displayColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: t.displayColor.withValues(alpha: isPrev ? 0.50 : 0.25),
                        width: isPrev ? 1.5 : 1.0,
                      ),
                      boxShadow: isPrev
                          ? [BoxShadow(color: t.displayColor.withValues(alpha: 0.15), blurRadius: 8)]
                          : null,
                    ),
                    child: Row(children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: t.displayColor.withValues(alpha: isPrev ? 0.15 : 0.07),
                          shape: BoxShape.circle,
                          border: Border.all(color: t.displayColor.withValues(alpha: isPrev ? 0.45 : 0.22)),
                        ),
                        child: Center(
                          child: Icon(
                            t.kmRequired >= 10
                                ? Icons.stars_rounded
                                : t.kmRequired >= 7
                                    ? Icons.shield_rounded
                                    : Icons.flag_rounded,
                            color: t.displayColor.withValues(alpha: 0.75),
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.epicName, style: GoogleFonts.inter(
                            color: isPrev ? Colors.white : Colors.white60,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                        if (t.ownerNickname != null)
                          Text(isMine ? 'Tuyo' : t.ownerNickname!,
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 9)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${t.kmRequired.toStringAsFixed(1)} km',
                            style: GoogleFonts.inter(
                                color: t.displayColor.withValues(alpha: 0.70), fontSize: 11, fontWeight: FontWeight.w700)),
                        Text('+${t.rewardActual}',
                            style: GoogleFonts.inter(color: _kGold.withValues(alpha: 0.70), fontSize: 9, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (_terrPreviseleccionado != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _seleccionarTerritorioGlobal(_terrPreviseleccionado!),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)],
                ),
                child: Center(
                  child: Text('CONQUISTAR ${_terrPreviseleccionado!.name.toUpperCase()}',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ),
              ),
            ),
          ],
        ],
      ]);
    }

    if (_objetivoGlobal != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _p.ink.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _p.globalRed.withValues(alpha: 0.5)),
            boxShadow: [BoxShadow(color: _p.globalRed.withValues(alpha: 0.15), blurRadius: 16)],
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GUERRA GLOBAL', style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 2),
              Text(_objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio',
                  style: GoogleFonts.inter(color: _kGold, fontSize: 11,
                      fontWeight: FontWeight.w700)),
              Text('Corre ${(_objetivoGlobal!['kmRequeridos'] as num?)?.toStringAsFixed(1) ?? "?"} km para conquistar',
                  style: GoogleFonts.inter(color: _p.goldDim, fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('+${(_objetivoGlobal!['recompensa'] as num?)?.toInt() ?? 0}',
                  style: GoogleFonts.orbitron(color: _kGold, fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text('pts el lunes',
                  style: GoogleFonts.inter(color: _p.goldDim, fontSize: 10)),
            ]),
          ]),
        ),
        GestureDetector(
          onTap: _mostrandoCuentaAtras ? null : _iniciarCuentaAtras,
          child: AnimatedBuilder(
            animation: _pulsoAnim,
            builder: (_, child) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12 + _pulso.value * 0.06),
                    width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12),
                ],
              ),
              child: child,
            ),
            child: Center(
              child: Text('INICIAR CONQUISTA',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white,
                      fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _objetivoGlobal = null),
          child: Text('cambiar objetivo',
              style: GoogleFonts.inter(
                  color: _p.goldDim, fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline)),
        ),
      ]);
    }

    final bool isCompetitivo = !_modoSolitario && !_modoRuta && _objetivoGlobal == null;
    final bool isGlobal      = _objetivoGlobal != null;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!_territoriosCargados && !_modoRuta) ...[
        Shimmer.fromColors(
          baseColor: const Color(0xFF2C2C2E),
          highlightColor: const Color(0xFF48484A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBar(width: 130),
              const SizedBox(height: 6),
              _shimmerBar(width: 96),
              const SizedBox(height: 6),
              _shimmerBar(width: 112),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      Row(children: [
        _modeButton(
          icon: CupertinoIcons.person_2_fill,
          label: 'Competitivo',
          active: isCompetitivo,
          activeColor: const Color(0xFF4A7A9B),
          onTap: () async {
            if (!await _confirmarCancelacionReto('Competitivo')) return;
            HapticFeedback.selectionClick();
            GameStateService.instance.currentMode = 'competitivo';
            setState(() => _modeCtrl.switchToCompetitivo());
            _limpiarCapasBarrios();
            _dibujarTerritoriosEnMapa();
            _limpiarRutasPreview();
            TerritoryService.invalidarCache();
            GameStateService.instance.invalidateSolitario();
            final centro = _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : null;
            try {
              final lista = await TerritoryService.cargarTodosLosTerritorios(
                  centro: centro, modo: 'competitivo')
                  .timeout(const Duration(seconds: 20));
              if (!mounted || GameStateService.instance.currentMode != 'competitivo') return;
              setState(() => _modeCtrl.onTerritoriosCargados(lista));
              GameStateService.instance.setCompetitiveTerritories(lista);
              _dibujarTerritoriosEnMapa();
              _aplicarTerritoriosFantasma();
            } catch (_) {
              if (mounted && GameStateService.instance.currentMode == 'competitivo') {
                setState(() => _modeCtrl.onTerritoriosCargados([]));
              }
            }
          },
        ),
        const SizedBox(width: 8),
        _modeButton(
          icon: CupertinoIcons.person_fill,
          label: 'Solitario',
          active: _modoSolitario,
          activeColor: const Color(0xFF4A7A5A),
          onTap: () async {
            if (!await _confirmarCancelacionReto('Solitario')) return;
            HapticFeedback.selectionClick();
            GameStateService.instance.currentMode = 'solitario';
            setState(() => _modeCtrl.switchToSolitario());
            _dibujarTerritoriosEnMapa();
            _limpiarRutasPreview();
            TerritoryService.invalidarCache();
            GameStateService.instance.invalidateCompetitive();
            final centro = _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : null;
            try {
              final lista = await TerritoryService.cargarTodosLosTerritorios(
                  centro: centro, modo: 'solitario')
                  .timeout(const Duration(seconds: 20));
              if (!mounted || GameStateService.instance.currentMode != 'solitario') return;
              setState(() => _modeCtrl.onTerritoriosCargados(lista));
              GameStateService.instance.setSolitarioTerritories(lista);
              _dibujarTerritoriosEnMapa();
            } catch (_) {
              if (mounted && GameStateService.instance.currentMode == 'solitario') {
                setState(() => _modeCtrl.onTerritoriosCargados([]));
              }
            }
          },
        ),
        const SizedBox(width: 8),
        _modeButton(
          icon: Icons.route_rounded,
          label: 'Ruta',
          active: _modoRuta,
          activeColor: const Color(0xFF6A4A9B),
          onTap: () async {
            HapticFeedback.selectionClick();
            GameStateService.instance.currentMode = 'ruta';
            setState(() => _modeCtrl.switchToRuta());
            _limpiarCapasBarrios();
            await _limpiarCapasTerritoriosForzado();
            _cargarYDibujarRutasPreview();
          },
        ),
        const SizedBox(width: 8),
        _modeButton(
          icon: CupertinoIcons.globe,
          label: 'Global',
          active: isGlobal,
          activeColor: const Color(0xFF7A3A3A),
          onTap: () async {
            if (!await _confirmarCancelacionReto('Global')) return;
            _elegirTerritorioGlobal();
          },
        ),
      ]),
      const SizedBox(height: 14),
      if (SubscriptionService.estilosMapaActivos) ...[
        _buildSelectorEstiloMapa(),
        const SizedBox(height: 14),
      ],
      GestureDetector(
        onTap: _mostrandoCuentaAtras ? null : _confirmarYComenzar,
        child: AnimatedBuilder(
          animation: _pulsoAnim,
          builder: (_, child) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12 + _pulso.value * 0.06),
                  width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12),
              ],
            ),
            child: child,
          ),
          child: Center(
            child: Text('CORRER',
                style: GoogleFonts.inter(fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w700, letterSpacing: 2.0)),
          ),
        ),
      ),
    ]);
  }

  Widget _shimmerBar({double width = double.infinity}) => Container(
    height: 11,
    width: width,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
    ),
  );

  Widget _modeButton({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? activeColor.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.10),
                width: active ? 1.5 : 1.0,
              ),
              boxShadow: active
                  ? [BoxShadow(
                      color: activeColor.withValues(alpha: 0.20),
                      blurRadius: 12, spreadRadius: 0)]
                  : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                size: 18,
                color: active ? Colors.white : Colors.white.withValues(alpha: 0.40),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.40),
                  letterSpacing: 0.3,
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _buildSelectorEstiloMapa() {
    final estilos = [
      {'id': 'normal',   'icon': Icons.map_rounded,           'label': 'Normal'},
      {'id': 'satelite', 'icon': Icons.satellite_alt_rounded, 'label': 'Satélite'},
      {'id': 'militar',  'icon': Icons.military_tech_rounded, 'label': 'Militar'},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Row(children: [
          Icon(Icons.layers_rounded, color: _p.goldDim, size: 10),
          const SizedBox(width: 5),
          Text('ESTILO DE MAPA', style: GoogleFonts.inter(color: _p.goldDim,
              fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
          color: _p.parchMid.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _p.goldDim.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: estilos.map((e) {
            final selected = _estiloMapa == e['id'];
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_estiloMapa == e['id']) return;
                  setState(() => _estiloMapa = e['id'] as String);
                  _buildings3dCreated       = false;
                  _territoriosLayersCreated = false;
                  _centrosLayerCreated      = false;
                  _globalesLayerCreated     = false;
                  _puntosGloboLayerCreated  = false;
                  _actualizandoGloboLayer   = false;
                  _dibujandoTerritorios     = false;
                  _styleLoaded              = false;
                  _mapboxMap?.loadStyleURI(_mapUriParaEstilo(e['id'] as String));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? _p.goldDim.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(e['icon'] as IconData,
                        color: selected ? _p.goldDim : _p.goldDim.withValues(alpha: 0.4),
                        size: 16),
                    const SizedBox(height: 3),
                    Text(e['label'] as String,
                        style: GoogleFonts.inter(
                            color: selected ? _p.goldDim : _p.goldDim.withValues(alpha: 0.4),
                            fontSize: 9, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  String _mapUriParaEstilo(String estilo) {
    switch (estilo) {
      case 'satelite': return mapbox.MapboxStyles.SATELLITE_STREETS;
      case 'militar':  return mapbox.MapboxStyles.DARK;
      default: return _modoNoche ? mapbox.MapboxStyles.DARK : _kEstiloPersonalizado;
    }
  }
}
