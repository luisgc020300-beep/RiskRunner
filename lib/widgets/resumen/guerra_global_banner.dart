import 'package:flutter/material.dart';

const _kBright   = Color(0xFF1C1C1E);
const _kGrey     = Color(0xFF636366);
const _kGold     = Color(0xFFFFD60A);
const _kGoldDim  = Color(0xFFAEAEB2);
const _kBorder2  = Color(0xFFD1D1D6);
const _kGlobalRed    = Color(0xFFCC2222);
const _kGlobalRedDim = Color(0xFF7A1414);

class GuerraGlobalBanner extends StatelessWidget {
  final Map<String, dynamic> objetivoGlobal;
  final bool   globalConquistado;
  final double distancia;
  final double? nuevaClausula;

  const GuerraGlobalBanner({
    super.key,
    required this.objetivoGlobal,
    required this.globalConquistado,
    required this.distancia,
    this.nuevaClausula,
  });

  @override
  Widget build(BuildContext context) {
    final nombre     = objetivoGlobal['territorioNombre'] as String? ?? 'Territorio';
    final kmReq      = (objetivoGlobal['kmRequeridos'] as num?)?.toDouble() ?? 0;
    final recompensa = (objetivoGlobal['recompensa']   as num?)?.toInt()   ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: globalConquistado
              ? [const Color(0xFF1A1000), const Color(0xFF3A2800)]
              : [const Color(0xFF1A0000), const Color(0xFF2A0808)],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: globalConquistado
              ? _kGold.withValues(alpha: 0.5)
              : _kGlobalRed.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (globalConquistado ? _kGold : _kGlobalRed).withValues(alpha: 0.15),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GUERRA GLOBAL',
                    style: TextStyle(
                      color:         globalConquistado ? _kGold : _kGlobalRed,
                      fontSize:      9,
                      fontWeight:    FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(nombre,
                      style: const TextStyle(
                          color: _kBright, fontSize: 16, fontWeight: FontWeight.w900)),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (globalConquistado ? _kGold : _kGlobalRed).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (globalConquistado ? _kGold : _kGlobalRed).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  globalConquistado ? 'CONQUISTADO' : 'NO COMPLETADO',
                  style: TextStyle(
                    color:         globalConquistado ? _kGold : _kGlobalRed,
                    fontSize:      9,
                    fontWeight:    FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 16),
            Container(height: 1, color: _kBorder2),
            const SizedBox(height: 16),

            Row(children: [
              _stat('KM RECORRIDOS', distancia.toStringAsFixed(2), _kBright),
              _divider(),
              _stat('KM REQUERIDOS', kmReq.toStringAsFixed(1), _kGrey),
              _divider(),
              _stat(
                'PROGRESO',
                kmReq > 0
                    ? '${((distancia / kmReq).clamp(0, 1) * 100).toInt()}%'
                    : '--',
                globalConquistado ? _kGold : _kGlobalRed,
              ),
            ]),

            const SizedBox(height: 12),
            Stack(children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                    color: _kBorder2, borderRadius: BorderRadius.circular(3)),
              ),
              FractionallySizedBox(
                widthFactor: kmReq > 0 ? (distancia / kmReq).clamp(0.0, 1.0) : 0,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: globalConquistado
                          ? [_kGoldDim, _kGold]
                          : [_kGlobalRedDim, _kGlobalRed],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (globalConquistado ? _kGold : _kGlobalRed)
                            .withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ]),

            if (globalConquistado && nuevaClausula != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGoldDim.withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: _kGrey, fontSize: 11),
                        children: [
                          const TextSpan(text: 'Próxima cláusula: '),
                          TextSpan(
                            text: '${nuevaClausula!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: _kGold, fontWeight: FontWeight.w900),
                          ),
                          const TextSpan(
                              text: ' — el siguiente en conquistarlo necesitará recorrer esta distancia.'),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ],

            if (globalConquistado) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGoldDim.withValues(alpha: 0.5)),
                ),
                child: Row(children: [
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('+$recompensa monedas reservadas',
                          style: const TextStyle(
                              color: _kGold, fontSize: 13, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        'Las recompensas se entregan al final de la semana si sigues siendo el dueño.',
                        style: TextStyle(
                            color: _kGoldDim.withValues(alpha: 0.85), fontSize: 10),
                      ),
                    ],
                  )),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(
            color: _kGrey, fontSize: 7, fontWeight: FontWeight.w700,
            letterSpacing: 1.5),
            textAlign: TextAlign.center),
      ]));

  Widget _divider() => Container(
      width: 1, height: 36, color: _kBorder2,
      margin: const EdgeInsets.symmetric(horizontal: 8));
}
