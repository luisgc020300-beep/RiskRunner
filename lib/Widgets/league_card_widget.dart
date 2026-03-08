// lib/widgets/league_card_widget.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/league_service.dart';

class LeagueCard extends StatefulWidget {
  final String userId;
  const LeagueCard({super.key, required this.userId});

  @override
  State<LeagueCard> createState() => _LeagueCardState();
}

class _LeagueCardState extends State<LeagueCard> {
  Map<String, dynamic> _datos = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final datos = await LeagueService.obtenerDatosLiga(widget.userId);
      if (mounted) setState(() { _datos = datos; _loading = false; });
    } catch (e) {
      debugPrint('LeagueCard error cargando: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
        ),
      );
    }

    if (_datos.isEmpty) return const SizedBox.shrink();

    final LeagueInfo? liga = _datos['liga'] as LeagueInfo?;
    if (liga == null) return const SizedBox.shrink();

    // ★ FIX: casts seguros — evita crash si algún valor llega null
    final int monedas = (_datos['monedas'] as num?)?.toInt() ?? 0;
    final double progreso = (_datos['progreso'] as num?)?.toDouble() ?? 0.0;
    final int monedasParaSiguiente = (_datos['monedasParaSiguiente'] as num?)?.toInt() ?? 0;
    final proteccionTs = _datos['proteccionHasta'] as Timestamp?;

    int diasProteccion = 0;
    if (proteccionTs != null) {
      final hasta = proteccionTs.toDate();
      if (hasta.isAfter(DateTime.now())) {
        diasProteccion = hasta.difference(DateTime.now()).inDays + 1;
      }
    }

    final int indiceActual =
        LeagueSystem.ligas.indexWhere((l) => l.id == liga.id);
    final bool esUltima = indiceActual == LeagueSystem.ligas.length - 1;
    final LeagueInfo? siguienteLiga =
        esUltima ? null : LeagueSystem.ligas[indiceActual + 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.military_tech_rounded, color: liga.color, size: 18),
          const SizedBox(width: 8),
          const Text('LIGA', style: TextStyle(
            color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w800, letterSpacing: 2,
          )),
        ]),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: liga.color.withValues(alpha: 0.35)),
            boxShadow: [BoxShadow(
              color: liga.color.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: liga.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: liga.color.withValues(alpha: 0.4)),
                  ),
                  child: Column(children: [
                    Text(liga.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 4),
                    Text(liga.name.toUpperCase(),
                      style: TextStyle(
                        color: liga.color, fontSize: 10,
                        fontWeight: FontWeight.w900, letterSpacing: 1.5,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(liga.descripcion,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text('$monedas 🪙',
                      style: TextStyle(
                        color: liga.color, fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (!esUltima && siguienteLiga != null)
                      Text(
                        'Faltan $monedasParaSiguiente para ${siguienteLiga.emoji} ${siguienteLiga.name}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      )
                    else
                      const Text('🏆 Rango máximo alcanzado',
                        style: TextStyle(
                          color: Colors.amber, fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                )),
              ]),

              const SizedBox(height: 16),

              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progreso,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(liga.color),
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(liga.name,
                  style: TextStyle(
                    color: liga.color.withValues(alpha: 0.7),
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
                if (!esUltima && siguienteLiga != null)
                  Text(siguienteLiga.name,
                    style: TextStyle(
                      color: siguienteLiga.color.withValues(alpha: 0.7),
                      fontSize: 10, fontWeight: FontWeight.w700,
                    ),
                  ),
              ]),

              if (diasProteccion > 0) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(children: [
                    const Text('🛡️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MODO PROTECCIÓN ACTIVO',
                          style: TextStyle(
                            color: Colors.greenAccent, fontSize: 10,
                            fontWeight: FontWeight.w800, letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'Tu territorio no puede ser robado durante '
                          '$diasProteccion día${diasProteccion == 1 ? '' : 's'} más',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    )),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}