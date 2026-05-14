import 'package:flutter/material.dart';

const _kBright  = Color(0xFF1C1C1E);
const _kGrey    = Color(0xFF636366);
const _kBorder2 = Color(0xFFD1D1D6);
const _kGold    = Color(0xFFFFD60A);

class ResumenContextCards extends StatelessWidget {
  final bool esDesdeCarrera;
  final bool modoRuta;
  final bool esGuerraGlobal;
  final int  rachaActual;
  final int  monedasRuta;
  final int  puntosLigaSesion;
  final int  totalPuntosLiga;
  final int  territoriosConquistados;

  const ResumenContextCards({
    super.key,
    required this.esDesdeCarrera,
    required this.modoRuta,
    required this.esGuerraGlobal,
    required this.rachaActual,
    required this.monedasRuta,
    required this.puntosLigaSesion,
    required this.totalPuntosLiga,
    required this.territoriosConquistados,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    if (esDesdeCarrera && rachaActual > 0)
      cards.add(_buildRachaCard());
    if (modoRuta && monedasRuta > 0)
      cards.add(_buildRutaCard());
    if (esDesdeCarrera && puntosLigaSesion > 0)
      cards.add(_buildLigaCard());
    if (esDesdeCarrera && !modoRuta && territoriosConquistados > 0)
      cards.add(_buildConquistaCard());
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(children: [
      const SizedBox(height: 18),
      ...cards.map((c) =>
          Padding(padding: const EdgeInsets.only(bottom: 8), child: c)),
    ]);
  }

  Widget _buildRachaCard() {
    final hitos = [3, 7, 14, 30];
    final hito  = hitos.firstWhere((h) => rachaActual < h, orElse: () => 30);
    final pct   = (rachaActual / hito).clamp(0.0, 1.0);
    return _ContextCard(
      icon:     Icons.local_fire_department_rounded,
      tag:      'RACHA',
      headline: '$rachaActual ${rachaActual == 1 ? 'día' : 'días'} consecutivos',
      sub:      rachaActual < 7
          ? 'Faltan ${7 - rachaActual} días para la semana'
          : '¡Más de una semana sin parar!',
      color:    _kGrey,
      trailing: _Ring(pct, '$rachaActual/$hito', _kGrey),
    );
  }

  Widget _buildRutaCard() => _ContextCard(
    icon:     Icons.route_rounded,
    tag:      'RUTA LIBRE',
    headline: '+$monedasRuta monedas ganadas',
    sub:      'Basado en distancia y ritmo',
    color:    const Color(0xFF6A4A9B),
    trailing: _Ring(1.0, '+$monedasRuta', const Color(0xFF6A4A9B)),
  );

  Widget _buildLigaCard() => _ContextCard(
    icon:     Icons.emoji_events_rounded,
    tag:      'LIGA',
    headline: '+$puntosLigaSesion pts esta sesión',
    sub:      '$totalPuntosLiga pts totales acumulados',
    color:    _kGold,
    trailing: _Ring(
      (totalPuntosLiga % 100) / 100.0,
      '+$puntosLigaSesion',
      _kGold,
    ),
  );

  Widget _buildConquistaCard() => _ContextCard(
    icon:     Icons.shield_rounded,
    tag:      'CONQUISTA',
    headline: '$territoriosConquistados territorio'
        '${territoriosConquistados == 1 ? '' : 's'} arrebatado'
        '${territoriosConquistados == 1 ? '' : 's'}',
    sub:      'El rival ya ha sido notificado',
    color:    _kGrey,
  );
}

class _ContextCard extends StatelessWidget {
  final IconData icon;
  final String   tag;
  final String   headline;
  final String   sub;
  final Color    color;
  final Widget?  trailing;

  const _ContextCard({
    required this.icon,
    required this.tag,
    required this.headline,
    required this.sub,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        Colors.white,
      borderRadius: BorderRadius.circular(12),
      border:       Border.all(color: color.withValues(alpha: 0.25)),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 16),
        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
      ],
    ),
    child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Center(child: Icon(icon, color: color, size: 22)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tag, style: TextStyle(
              color: color, fontSize: 8, fontWeight: FontWeight.w900,
              letterSpacing: 2.5)),
          const SizedBox(height: 3),
          Text(headline, style: const TextStyle(
              color: _kBright, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: _kGrey, fontSize: 11)),
        ],
      )),
      if (trailing != null) ...[
        const SizedBox(width: 10),
        trailing!,
      ],
    ]),
  );
}

class _Ring extends StatelessWidget {
  final double value;
  final String label;
  final Color  color;
  const _Ring(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48, height: 48,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
        value:           value,
        strokeWidth:     2.5,
        backgroundColor: _kBorder2,
        valueColor:      AlwaysStoppedAnimation(color),
      ),
      Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontSize: 7, fontWeight: FontWeight.w900)),
    ]),
  );
}
