import 'package:flutter/material.dart';

const _kBright  = Color(0xFF1C1C1E);
const _kGrey    = Color(0xFF636366);
const _kGreyDim = Color(0xFF8E8E93);
const _kGold    = Color(0xFFFFD60A);
const _kGoldDim = Color(0xFFAEAEB2);
const _kBorder  = Color(0xFFC6C6C8);
const _kBorder2 = Color(0xFFD1D1D6);
const _kSurface = Color(0xFFFFFFFF);
const _kBg      = Color(0xFFE8E8ED);

class ResumenHistorial extends StatelessWidget {
  final List<Map<String, dynamic>> logrosFiltrados;
  final List<Map<String, dynamic>> todosLosLogros;
  final bool                       verTodos;
  final TextEditingController      searchCtrl;
  final int                        paginaActual;
  final int                        paginaTamanio;
  final Map<String, dynamic>?      retoCompletadoEnSesion;
  final ValueChanged<String>       onSearch;
  final VoidCallback               onToggleVerTodos;

  const ResumenHistorial({
    super.key,
    required this.logrosFiltrados,
    required this.todosLosLogros,
    required this.verTodos,
    required this.searchCtrl,
    required this.paginaActual,
    required this.paginaTamanio,
    required this.onSearch,
    required this.onToggleVerTodos,
    this.retoCompletadoEnSesion,
  });

  @override
  Widget build(BuildContext context) {
    final lista = (verTodos || searchCtrl.text.isNotEmpty)
        ? logrosFiltrados
        : logrosFiltrados.take(paginaTamanio * paginaActual).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _SectionLabel('HISTORIAL DE MISIONES')),
        if (todosLosLogros.length > 5)
          GestureDetector(
            onTap: onToggleVerTodos,
            child: Text(
              verTodos ? 'MENOS' : 'TODO',
              style: const TextStyle(
                  color: _kGrey, fontSize: 8,
                  fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
          ),
      ]),
      const SizedBox(height: 12),

      if (retoCompletadoEnSesion != null) ...[
        _BannerRetoCompletado(reto: retoCompletadoEnSesion!),
        const SizedBox(height: 16),
      ],

      if (verTodos) ...[
        TextField(
          controller: searchCtrl,
          onChanged:  onSearch,
          style:      const TextStyle(color: _kBright, fontSize: 13),
          decoration: InputDecoration(
            hintText:   'Buscar carrera...',
            hintStyle:  const TextStyle(color: _kGreyDim, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, color: _kGrey, size: 16),
            filled:     true,
            fillColor:  _kSurface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kGrey, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 10),
      ],

      if (lista.isEmpty)
        const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sin carreras registradas',
              style: TextStyle(color: _kGreyDim, fontSize: 12)),
        ))
      else
        ...lista.asMap().entries.map((e) =>
            TweenAnimationBuilder<double>(
              tween:    Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 280 + e.key * 35),
              curve:    Curves.easeOut,
              builder: (_, v, child) => Opacity(
                opacity: v,
                child:   Transform.translate(
                    offset: Offset(16 * (1 - v), 0), child: child),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child:   _HistorialRow(idx: e.key, data: e.value),
              ),
            )),
    ]);
  }
}

// ── Banner reto completado ────────────────────────────────────────────────────

class _BannerRetoCompletado extends StatelessWidget {
  final Map<String, dynamic> reto;
  const _BannerRetoCompletado({required this.reto});

  @override
  Widget build(BuildContext context) {
    final premio = (reto['premio'] as num?)?.toInt() ?? 0;
    final titulo = reto['titulo']  as String? ?? 'Misión completada';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBg,
        border: Border(
          left:   const BorderSide(color: _kGold, width: 3),
          top:    BorderSide(color: _kGoldDim.withValues(alpha: 0.5)),
          right:  BorderSide(color: _kGoldDim.withValues(alpha: 0.5)),
          bottom: BorderSide(color: _kGoldDim.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(color: _kGold.withValues(alpha: 0.10), blurRadius: 20),
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: Row(children: [
        TweenAnimationBuilder<double>(
          tween:    Tween(begin: 0.7, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve:    Curves.elasticOut,
          builder:  (_, v, child) => Transform.scale(scale: v, child: child),
          child: const Text('', style: TextStyle(fontSize: 32)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MISIÓN COMPLETADA', style: TextStyle(
                color: _kGold, fontSize: 9,
                fontWeight: FontWeight.w900, letterSpacing: 3)),
            const SizedBox(height: 3),
            Text(titulo, style: const TextStyle(
                color: _kBright, fontSize: 15, fontWeight: FontWeight.w800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              'Has completado este reto y se ha sumado a tus logros',
              style: TextStyle(
                  color:      _kGoldDim.withValues(alpha: 0.8),
                  fontSize:   10,
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
        if (premio > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color:  _kGoldDim.withValues(alpha: 0.15),
              border: Border.all(color: _kGoldDim.withValues(alpha: 0.5)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('+$premio', style: const TextStyle(
                  color: _kGold, fontSize: 16,
                  fontWeight: FontWeight.w900, height: 1)),
              const Text('PTS', style: TextStyle(
                  color: _kGoldDim, fontSize: 7,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Fila de historial ─────────────────────────────────────────────────────────

class _HistorialRow extends StatelessWidget {
  final int                  idx;
  final Map<String, dynamic> data;
  const _HistorialRow({required this.idx, required this.data});

  @override
  Widget build(BuildContext context) {
    final dist       = (data['distancia'] as double? ?? 0);
    final recompensa = (data['recompensa'] as int?    ?? 0);
    final isFirst    = idx == 0;
    final modo       = data['modo'] as String? ?? 'competitivo';
    final esGlobal   = modo == 'guerra_global';

    return Container(
      decoration: BoxDecoration(
        color:        _kSurface,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder2),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: esGlobal ? _kGold : (isFirst ? _kGrey : _kGreyDim),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Text(
              '${idx + 1}'.padLeft(2, '0'),
              style: TextStyle(
                  color: esGlobal ? _kGold : (isFirst ? _kGrey : _kGreyDim),
                  fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 0.5),
            ),
          ),
          Container(width: 1, color: _kBorder),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (esGlobal) ...[
                        const Text('', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          data['titulo'] ?? 'Carrera completada',
                          style: TextStyle(
                              color: esGlobal
                                  ? _kGold
                                  : (isFirst ? _kBright
                                      : const Color(0xFF1C1C1E).withValues(alpha: 0.75)),
                              fontSize:   12,
                              fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        _kBorder2.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          border:       Border.all(color: _kBorder2),
                        ),
                        child: Text('${dist.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: _kBright, fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Text(data['fecha'] ?? '--',
                          style: const TextStyle(color: _kGrey, fontSize: 9)),
                    ]),
                  ],
                )),
                if (recompensa > 0) ...[
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment:  MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color:        _kBorder2.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                          border:       Border.all(color: _kBorder2),
                        ),
                        child: Text('+$recompensa', style: const TextStyle(
                            color: _kBright, fontSize: 11,
                            fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(height: 2),
                      const Text('PTS', style: TextStyle(
                          color: _kGreyDim, fontSize: 7,
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ],
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 3, height: 11,
      decoration: BoxDecoration(
          color: _kGrey, borderRadius: BorderRadius.circular(2)),
    ),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(
        color: _kGrey, fontSize: 8,
        fontWeight: FontWeight.w900, letterSpacing: 3)),
  ]);
}
