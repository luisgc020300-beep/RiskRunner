// lib/pestañas/map_feed.dart
// Feed de actividad reciente, historial de conquistas — extraídos de fullscreen_map_screen.dart.
// ignore_for_file: invalid_use_of_protected_member
part of 'fullscreen_map_screen.dart';

extension _MapFeed on _FullscreenMapScreenState {
  // ==========================================================================
  // FEED DE ACTIVIDAD RECIENTE
  // ==========================================================================
  Widget _buildFeedActividad() {
    return FutureBuilder<List<ActivityEntry>>(
      future: _feedFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _kSub),
              ),
            ),
          );
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) return const SizedBox(height: 12);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kSub.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kSub.withValues(alpha: 0.20)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bolt_rounded, size: 11, color: _kSub),
                    const SizedBox(width: 4),
                    Text('ACTIVIDAD RECIENTE',
                        style: _raj(8, FontWeight.w800, _kSub, spacing: 1.5)),
                  ]),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await ActivityService.invalidarCache();
                    if (mounted) {
                      setState(() {
                        _feedFuture = ActivityService.obtenerFeedReciente();
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _shSurf,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _shBorder),
                    ),
                    child: const Icon(Icons.refresh_rounded, size: 12, color: _kSub),
                  ),
                ),
              ]),
            ),
            ...entries.map(_buildFeedItem),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildFeedItem(ActivityEntry e) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      decoration: BoxDecoration(
        color: _shSurf,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: e.color, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: e.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: e.color.withValues(alpha: 0.30)),
            ),
            child: Center(child: Icon(
              e.mode == 'solitario'
                  ? Icons.explore_rounded
                  : Icons.shield_rounded,
              size: 14,
              color: e.color,
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text('@${e.userNick}',
                    style: _raj(11, FontWeight.w800, _shText),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                Text('conquistó', style: _raj(10, FontWeight.w400, _kSub)),
              ]),
              const SizedBox(height: 2),
              Text(e.territoryName,
                  style: _raj(11, FontWeight.w700, e.color),
                  overflow: TextOverflow.ellipsis),
              if (e.previousOwnerNick != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text('â† @${e.previousOwnerNick}',
                      style: _raj(9, FontWeight.w500, _kDim),
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _shBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _shBorder),
            ),
            child: Text(e.timeAgo, style: _raj(9, FontWeight.w500, _kDim)),
          ),
        ]),
      ),
    );
  }

  // ==========================================================================
  // HISTORIAL DE CONQUISTAS (tarjeta de territorio)
  // ==========================================================================
  Widget _buildCardHistorial(String docId) {
    Widget wrap(List<Map<String, dynamic>> entries) {
      if (entries.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        decoration: BoxDecoration(
          color: _shSurf,
          borderRadius: BorderRadius.circular(6),
        ),
        child: _historialContent(entries),
      );
    }

    final cached = _historialCache[docId];
    if (cached != null) return wrap(cached);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ActivityService.obtenerHistorialTerritorio(docId),
      builder: (ctx, snap) {
        // Sin placeholder gris mientras carga — el card no muestra área vacía
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final entries = snap.data ?? [];
        if (entries.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_historialCache.containsKey(docId)) {
              setState(() => _historialCache[docId] = entries);
            }
          });
        }
        return wrap(entries);
      },
    );
  }

  Widget _historialContent(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
          child: Row(children: [
            Container(width: 2, height: 9, color: _kSub,
                margin: const EdgeInsets.only(right: 6)),
            Text('HISTORIAL', style: _raj(8, FontWeight.w800, _kSub, spacing: 1.5)),
          ]),
        ),
        ...entries.take(3).map((e) {
          final nick   = e['ownerNickname'] as String? ?? '?';
          final prev   = e['previousOwner'] as String?;
          final colorV = (e['ownerColor'] as num?)?.toInt();
          final color  = colorV != null ? Color(colorV) : _kSub;
          final ts     = (e['conquista_ts'] as Timestamp?)?.toDate();
          final ago    = ts != null ? _timeAgoStr(ts) : '';
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
            child: Row(children: [
              Container(width: 5, height: 5, margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
              Text('@$nick', style: _raj(9, FontWeight.w700, _shText)),
              if (prev != null)
                Text(' â† @$prev', style: _raj(9, FontWeight.w500, _kSub)),
              const Spacer(),
              Text(ago, style: _raj(9, FontWeight.w500, _kSub)),
            ]),
          );
        }),
        const SizedBox(height: 6),
      ],
    );
  }

  String _timeAgoStr(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours   < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
