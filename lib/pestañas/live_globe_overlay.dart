// lib/pestañas/live_globe_overlay.dart
// Globe overlay widget builders: overlay, chips, stats, territory rows.
// ignore_for_file: invalid_use_of_protected_member, unqualified_reference_to_static_member_of_extended_type
part of 'LiveActivity_screen.dart';

extension _LiveGlobeOverlay on _LiveActivityScreenState {

  Widget _buildGloboOverlay() {
    return Stack(children: [
      // Estrellas — solo en modo noche
      if (_modoNoche)
        Positioned.fill(
          child: IgnorePointer(
            child: _StarfieldWidget(nightMode: true, globeAnim: _globoAnim),
          ),
        ),

      // Viñeta espacial en los bordes — ahora más azulada
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center, radius: 0.80,
                colors: [
                  Colors.transparent,
                  _modoNoche
                      ? const Color(0xFF020B18).withValues(alpha: 0.40)
                      : const Color(0xFF0A1828).withValues(alpha: 0.58),
                ],
              ),
            ),
          ),
        ),
      ),
      // Título
      Positioned(
        top: 58, left: 0, right: 0,
        child: IgnorePointer(
          child: Column(children: [
            const SizedBox(height: 5),
            Text(
              _seleccionandoGlobal ? 'GUERRA GLOBAL' : 'MAPA EN VIVO',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: _seleccionandoGlobal ? _kGold : Colors.white,
                  shadows: [
                    Shadow(blurRadius: 24, color: Colors.black.withValues(alpha: 0.9)),
                    const Shadow(blurRadius: 8,  color: Colors.black),
                  ]),
            ),
            if (_seleccionandoGlobal)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Elige un territorio para atacar',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.white70, letterSpacing: 0.5)),
              ),
          ]),
        ),
      ),
      // Chips — gestionados por _buildChipsGlobo() fuera de IgnorePointer
      // Stats en la parte inferior — ocultos mientras se selecciona territorio
      if (!_seleccionandoGlobal)
      Positioned(
        bottom: 265, left: 0, right: 0,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _objetivoGlobal != null
                  ? [
                      _globoStat(_session.distanciaTotal.toStringAsFixed(2), 'KM HECHOS', _kGold),
                      _globoStat(
                        (_objetivoGlobal!['kmRequeridos'] as num?)?.toStringAsFixed(1) ?? '?',
                        'KM META', _kWaterLight,
                      ),
                      _globoStat('${(_progresoGlobal * 100).toInt()}%', 'PROGRESO', _kGoldLight),
                      _globoStat(_globalConquistado ? 'OK' : '···', 'ESTADO',
                          _globalConquistado ? _kVerde : _p.terracotta),
                    ]
                  : _modoSolitario && _barriosCercanos.isNotEmpty
                      ? [
                          _globoStat(
                            '${_barriosCercanos.where((b) => b.porcentajeCubierto >= 1.0).length}',
                            'COMPLETAS', const Color(0xFF30D158),
                          ),
                          _globoStat(
                            '${_barriosCercanos.length}',
                            'ZONAS', _kGoldLight,
                          ),
                          _globoStat(
                            '${_territorios.where((t) => t.esMio).length}',
                            'MIS TERR.', _kGold,
                          ),
                          _globoStat(
                            _barriosCercanos.isEmpty ? '0%'
                              : '${(_barriosCercanos.map((b) => b.porcentajeCubierto).reduce((a, b) => a + b) / _barriosCercanos.length * 100).toInt()}%',
                            'MEDIA', _kWaterLight,
                          ),
                        ]
                      : _modoRuta
                          ? [
                              _globoStat('${_rutasPreview.length}', 'MIS RUTAS', _kGold),
                              _globoStat(
                                _rutasPreview.fold(0.0, (s, r) => s + r.distanciaKm).toStringAsFixed(1),
                                'KM TOTAL', _kWaterLight,
                              ),
                              _globoStat(
                                _rutasPreview.isNotEmpty
                                    ? _rutasPreview.map((r) => r.distanciaKm).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)
                                    : '0.0',
                                'MEJOR KM', _kGoldLight,
                              ),
                            ]
                          : [
                              _globoStat('${_territorios.where((t) => t.esMio).length}', 'MIS ZONAS', _kGold),
                              _globoStat('${_jugadoresActivos.length}', 'ACTIVOS', _kWaterLight),
                              _globoStat('${_territorios.length}', 'TOTAL', _kGoldLight),
                              _globoStat('${_territoriosNotificadosEnSesion.length}', 'EN GUERRA', _p.terracotta),
                            ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildChipsGlobo() {
    final miasCount    = _territorios.where((t) => t.esMio).length;
    final amenazaCount = _territorios.where((t) => t.esMio && t.estadoHp == EstadoHp.critico).length;

    String situLabel;
    Color  situColor;
    IconData situIcon;
    if (miasCount == 0) {
      situLabel = 'Sin zonas — sal a conquistar';
      situColor = _kGoldLight;
      situIcon  = CupertinoIcons.location_circle;
    } else if (amenazaCount > 0) {
      situLabel = '$amenazaCount zona${amenazaCount > 1 ? 's' : ''} bajo amenaza';
      situColor = _p.terracotta;
      situIcon  = CupertinoIcons.shield_slash;
    } else {
      situLabel = 'Todo bajo control · $miasCount terr.';
      situColor = const Color(0xFF30D158);
      situIcon  = CupertinoIcons.checkmark_shield;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_modoSolitario) ...[
        _globoChip(CupertinoIcons.map_pin, '${_territorios.where((t) => t.esMio).length} mis zonas', _kGold),
        const SizedBox(height: 6),
        if (_barriosCercanos.isNotEmpty) ...[
          _globoChip(
            CupertinoIcons.map,
            '${_barriosCercanos.where((b) => b.porcentajeCubierto >= 1.0).length}/${_barriosCercanos.length} barrios',
            const Color(0xFF30D158),
          ),
          const SizedBox(height: 6),
          if (_barrioActual != null)
            _globoChip(
              CupertinoIcons.compass,
              '${_barrioActual!.nombre} · ${(_barrioActual!.porcentajeCubierto * 100).toInt()}%',
              _barrioActual!.porcentajeCubierto >= 1.0
                  ? const Color(0xFF30D158)
                  : _barrioActual!.porcentajeCubierto > 0
                      ? const Color(0xFFFF9500)
                      : Colors.white70,
            ),
        ] else
          _globoChip(CupertinoIcons.compass, 'Explora y conquista', Colors.white70),
      ] else if (_objetivoGlobal != null) ...[
        _globoChip(CupertinoIcons.flag,
            _objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio', _p.globalRed),
        const SizedBox(height: 6),
        _globoChip(CupertinoIcons.person,
            '${(_objetivoGlobal!['kmRequeridos'] as num?)?.toStringAsFixed(1) ?? "?"} km requeridos',
            Colors.white70),
        const SizedBox(height: 6),
        _globoChip(CupertinoIcons.circle,
            '+${(_objetivoGlobal!['recompensa'] as num?)?.toInt() ?? 0} el lunes', _kGold),
      ] else if (_modoRuta) ...[
        _globoChip(Icons.route_rounded,
            '${_rutasPreview.length} ${_rutasPreview.length == 1 ? 'ruta guardada' : 'rutas guardadas'}',
            _kGold),
        const SizedBox(height: 6),
        if (_rutasPreview.isNotEmpty) ...[
          _globoChip(Icons.straighten,
              '${_rutasPreview.fold(0.0, (s, r) => s + r.distanciaKm).toStringAsFixed(1)} km totales',
              _kWaterLight),
        ] else
          _globoChip(Icons.add_road, 'Corre tu primera ruta libre', Colors.white70),
      ] else ...[
        _globoChip(CupertinoIcons.shield,
            '${_territoriosNotificadosEnSesion.isNotEmpty ? _territoriosNotificadosEnSesion.length : "—"} invasiones',
            _p.terracotta),
        const SizedBox(height: 6),
        _globoChip(CupertinoIcons.person_2, '${_jugadoresActivos.length} activos ahora', _kWaterLight),
        const SizedBox(height: 6),
        // Chip de territorios — tappable para ver situación
        GestureDetector(
          onTap: () => setState(() => _mostrarSituacion = !_mostrarSituacion),
          child: _globoChip(
            _mostrarSituacion ? CupertinoIcons.chevron_up : CupertinoIcons.map,
            _territoriosCargados
                ? '${_territorios.length} territorios'
                : 'Cargando...',
            _mostrarSituacion ? _kGoldLight : Colors.white70,
          ),
        ),
        if (_mostrarSituacion) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: situColor.withValues(alpha: 0.30)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(situIcon, size: 13, color: situColor),
              const SizedBox(width: 7),
              Text(situLabel,
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.88))),
            ]),
          ),
          if (miasCount > 0) ...[
            const SizedBox(height: 6),
            _buildMisTerritoriasGlobo(),
          ],
        ],
      ],
      if (_retoActivo != null) ...[
        const SizedBox(height: 6),
        _globoChip(CupertinoIcons.bolt, _retoActivo!['titulo'] as String? ?? 'Reto activo', _kGold),
      ],
    ]);
  }

  Widget _globoChip(IconData icon, String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 6),
          Text(texto, style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      );

  Widget _globoStat(String valor, String label, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(valor, style: GoogleFonts.orbitron(
            fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 7,
            fontWeight: FontWeight.w700, letterSpacing: 1.8,
            color: _kGold.withValues(alpha: 0.4))),
      ]);

  Widget _buildMisTerritoriasGlobo() {
    final mias = _territorios.where((t) => t.esMio).toList()
      ..sort((a, b) => a.hpActual.compareTo(b.hpActual));
    final shown = mias.take(5).toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MIS ZONAS',
                style: GoogleFonts.inter(
                    color: _kGold.withValues(alpha: 0.6),
                    fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
            const SizedBox(height: 6),
            ...shown.map(_buildTerritoryRow),
            if (mias.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+ ${mias.length - 5} más',
                    style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 9)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerritoryRow(TerritoryData t) {
    final Color estadoColor = switch (t.estadoHp) {
      EstadoHp.saludable => _kVerde,
      EstadoHp.danado    => _kGold,
      EstadoHp.critico   => _p.globalRed,
    };
    final String nombre = (t.nombreTerritorio?.isNotEmpty == true)
        ? t.nombreTerritorio!
        : t.docId.substring(0, t.docId.length.clamp(0, 6)).toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
                color: estadoColor, shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: estadoColor.withValues(alpha: 0.5), blurRadius: 4)])),
        const SizedBox(width: 6),
        SizedBox(
            width: 110,
            child: Text(nombre,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10, fontWeight: FontWeight.w600))),
        const SizedBox(width: 6),
        SizedBox(
            width: 36, height: 4,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    value: t.hpActual / 100.0,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        estadoColor.withValues(alpha: 0.8)),
                    minHeight: 4))),
        if (t.escudoActivo) ...[
          const SizedBox(width: 4),
          const Icon(Icons.security_rounded,
              color: Colors.lightBlueAccent, size: 9),
        ],
      ]),
    );
  }
}
