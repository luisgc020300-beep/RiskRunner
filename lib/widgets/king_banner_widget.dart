// lib/widgets/king_banner_widget.dart
//
// Widget reutilizable que muestra el banner de "Rey del Territorio".
// Se usa en:
//   - Mapa (sobre el territorio con corona)
//   - Perfil del jugador (lista de reinos)
//   - Home (sección de reyes destacados)
//
// Uso básico:
//   KingBannerWidget(territory: miTerritoryData)
//
// Uso en lista:
//   KingBannerWidget.compact(territory: miTerritoryData)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/territory_service.dart';

// ── Paleta ────────────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF090807);
const _kSurface   = Color(0xFF0F0D0A);
const _kBorder    = Color(0xFF2A2218);
const _kGold      = Color(0xFFD4A84C);
const _kGoldLight = Color(0xFFEDD98A);
const _kGoldDim   = Color(0xFF7A5E28);
const _kDim       = Color(0xFF5A5040);

// =============================================================================
// WIDGET PRINCIPAL — versión completa (para perfil / home)
// =============================================================================
class KingBannerWidget extends StatelessWidget {
  final TerritoryData territory;
  final VoidCallback? onTap;

  const KingBannerWidget({
    super.key,
    required this.territory,
    this.onTap,
  });

  // ── Constructor alternativo compacto (para listas) ────────────────────────
  static Widget compact({
    required TerritoryData territory,
    VoidCallback? onTap,
  }) {
    return _KingBannerCompact(territory: territory, onTap: onTap);
  }

  // ── Constructor para notificación de coronación ───────────────────────────
  static Widget coronation({
    required String nickname,
    required Color color,
    required int diasControlado,
  }) {
    return _KingCoronationWidget(
      nickname:        nickname,
      color:           color,
      diasControlado:  diasControlado,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!territory.tieneRey) return const SizedBox.shrink();

    final color    = territory.color;
    final diasRey  = territory.diasComoRey;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: Container(
        margin:  const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.08),
              _kGold.withValues(alpha: 0.04),
              color.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _kGold.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color:      _kGold.withValues(alpha: 0.10),
              blurRadius: 16,
              offset:     const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          // Corona animada
          _AnimatedCrown(color: color),
          const SizedBox(width: 14),

          // Info del reinado
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    'REY DEL TERRITORIO',
                    style: GoogleFonts.inter(
                      color:        _kGold,
                      fontSize:     9,
                      fontWeight:   FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:        _kGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border:       Border.all(
                          color: _kGold.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${diasRey}d',
                      style: GoogleFonts.orbitron(
                        color:      _kGoldLight,
                        fontSize:   9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  territory.reyNickname ?? 'Desconocido',
                  style: GoogleFonts.inter(
                    color:      Colors.white,
                    fontSize:   16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitulo(diasRey),
                  style: GoogleFonts.inter(
                      color: _kDim, fontSize: 11),
                ),
              ],
            ),
          ),

          // Escudo con color del territorio
          Container(
            width:  40,
            height: 40,
            decoration: BoxDecoration(
              color:  color.withValues(alpha: 0.12),
              shape:  BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text('🏰',
                  style: TextStyle(fontSize: 18)),
            ),
          ),
        ]),
      ),
    );
  }

  String _subtitulo(int dias) {
    if (dias < 7)  return 'Reinado reciente';
    if (dias < 30) return 'Reinado consolidado ($dias días)';
    if (dias < 90) return 'Reinado veterano ($dias días)';
    return 'Leyenda viva — $dias días en el trono';
  }
}

// =============================================================================
// VERSIÓN COMPACTA — para listas y chips en el mapa
// =============================================================================
class _KingBannerCompact extends StatelessWidget {
  final TerritoryData territory;
  final VoidCallback? onTap;

  const _KingBannerCompact({required this.territory, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!territory.tieneRey) return const SizedBox.shrink();

    final color = territory.color;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        _kGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: _kGold.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
                color: _kGold.withValues(alpha: 0.08), blurRadius: 8),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('👑', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            territory.reyNickname ?? '?',
            style: GoogleFonts.inter(
              color:      _kGoldLight,
              fontSize:   12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '· ${territory.diasComoRey}d',
            style: GoogleFonts.inter(
                color: _kGoldDim, fontSize: 10),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// WIDGET DE CORONACIÓN — overlay/snack al ser coronado Rey
// =============================================================================
class _KingCoronationWidget extends StatefulWidget {
  final String nickname;
  final Color  color;
  final int    diasControlado;

  const _KingCoronationWidget({
    required this.nickname,
    required this.color,
    required this.diasControlado,
  });

  @override
  State<_KingCoronationWidget> createState() =>
      _KingCoronationWidgetState();
}

class _KingCoronationWidgetState extends State<_KingCoronationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin:  const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.color.withValues(alpha: 0.12),
                _kGold.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kGold.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(
                color:      _kGold.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('👑', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              '¡CORONADO REY!',
              style: GoogleFonts.cinzel(
                color:        _kGoldLight,
                fontSize:     20,
                fontWeight:   FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.diasControlado} días dominando esta zona',
              style: GoogleFonts.inter(
                color:      _kGold,
                fontSize:   14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tu corona aparecerá en el mapa para que todos la vean',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: _kDim, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// CORONA ANIMADA — icono con pulso de brillo dorado
// =============================================================================
class _AnimatedCrown extends StatefulWidget {
  final Color color;
  const _AnimatedCrown({required this.color});

  @override
  State<_AnimatedCrown> createState() => _AnimatedCrownState();
}

class _AnimatedCrownState extends State<_AnimatedCrown>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.2, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width:  52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color:      _kGold.withValues(alpha: _glow.value * 0.5),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            '👑',
            style: TextStyle(
              fontSize: 30,
              shadows: [
                Shadow(
                  color:      _kGold.withValues(alpha: _glow.value),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BARRA DE PROGRESO HACIA EL REINADO
// Se muestra en el perfil para territorios propios que aún no tienen Rey.
// =============================================================================
class KingProgressBar extends StatelessWidget {
  /// Fecha desde la que el jugador es el dueño actual sin interrupciones.
  final DateTime fechaDesdeDueno;
  final Color    color;

  const KingProgressBar({
    super.key,
    required this.fechaDesdeDueno,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dias     = DateTime.now().difference(fechaDesdeDueno).inDays;
    final progreso = (dias / kDiasParaSerRey).clamp(0.0, 1.0);
    final faltan   = (kDiasParaSerRey - dias).clamp(0, kDiasParaSerRey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '👑 Progreso hacia el reinado',
              style: GoogleFonts.inter(
                color:      _kGoldDim,
                fontSize:   11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              progreso >= 1.0 ? '¡Listo!' : 'Faltan $faltan días',
              style: GoogleFonts.inter(
                color:      progreso >= 1.0 ? _kGoldLight : _kDim,
                fontSize:   10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value:           progreso,
            minHeight:       6,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation<Color>(
              progreso >= 1.0 ? _kGoldLight : color,
            ),
          ),
        ),
        if (progreso >= 1.0) ...[
          const SizedBox(height: 6),
          Text(
            '¡Visita el territorio para ser coronado Rey!',
            style: GoogleFonts.inter(
              color:      _kGoldLight,
              fontSize:   11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}