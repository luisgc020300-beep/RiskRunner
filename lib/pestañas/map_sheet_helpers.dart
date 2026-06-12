// lib/pestañas/map_sheet_helpers.dart
// Widget helpers de los bottom sheets — extraídos de fullscreen_map_screen.dart
part of 'fullscreen_map_screen.dart';

extension _MapSheetHelpers on _FullscreenMapScreenState {

  Widget _shHeader({
    required IconData icon,
    required String modeLabel,
    required Color modeColor,
    required String heroValue,
    required String heroLabel,
    String? heroSuffix,
    Widget? trailing,
    Widget? below,
  }) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: modeColor.withValues(alpha: 0.20)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 11, color: modeColor),
              const SizedBox(width: 5),
              Text(modeLabel, style: _raj(9, FontWeight.w700, modeColor, spacing: 1)),
            ]),
          ),
          if (trailing != null) ...[const Spacer(), trailing],
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(heroValue, style: _raj(36, FontWeight.w900, _shText, height: 1)),
          if (heroSuffix != null) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(heroSuffix, style: _raj(16, FontWeight.w600, _kSub)),
            ),
          ],
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(heroLabel, style: _raj(11, FontWeight.w500, _kSub)),
          ),
        ]),
        if (below != null) ...[const SizedBox(height: 10), below],
      ]),
    );

  Widget _shStatBar(List<_ShStat> items) {
    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _shSurf,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(items[i].value, style: _raj(17, FontWeight.w800, _shText, height: 1)),
            const SizedBox(height: 3),
            Text(items[i].label, style: _raj(8, FontWeight.w600, _kSub, spacing: 0.3)),
          ]),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: children),
    );
  }

  Widget _shSectionTitle(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(children: [
      Text(label.toUpperCase(), style: _raj(11, FontWeight.w700, _kSub, spacing: 0.5)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 0.5, color: _shBorder)),
    ]),
  );

  Widget _shPillBadge(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.20)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: _raj(9, FontWeight.w600, color, spacing: 0.3)),
    ]),
  );

  Widget _shStatusBadge(int det, int pel) {
    if (pel > 0) return _shPillBadge('$pel críticos', Icons.warning_rounded, _kSub);
    if (det > 0) return _shPillBadge('$det desgaste', Icons.shield_outlined, _kSub);
    return _shPillBadge('Todo OK', Icons.check_circle_outline_rounded, _kSub);
  }

  Widget _shAlert(int det, int pel) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
    decoration: BoxDecoration(
      color: _shSurf,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _shBorder),
    ),
    child: Row(children: [
      Container(
        width: 3, height: 30,
        decoration: BoxDecoration(color: _kSub, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 10),
      const Icon(Icons.shield_outlined, color: _kSub, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          pel > 0
              ? '$pel ${pel == 1 ? 'territorio puede' : 'territorios pueden'} ser conquistados.'
              : '$det ${det == 1 ? 'territorio debilitado' : 'territorios debilitados'}. Visítalos pronto.',
          style: _raj(11, FontWeight.w500, _kDim),
        ),
      ),
    ]),
  );

  Widget _shEmptyState(IconData icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: _shSurf,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _kSub, size: 22),
      ),
      const SizedBox(height: 12),
      Text(title.toUpperCase(), style: _raj(12, FontWeight.w700, _kSub, spacing: 1)),
      const SizedBox(height: 4),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: _raj(11, FontWeight.w400, _kDim, height: 1.5)),
    ]),
  );

  Widget _shLoading(String title, String subtitle, Color color) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      const SizedBox(height: 12),
      Text(title, style: _raj(12, FontWeight.w600, _kSub)),
      const SizedBox(height: 3),
      Text(subtitle, style: _raj(10, FontWeight.w400, _kDim)),
    ]),
  );

  Widget _shCapacityBar(int current, int max, Color color) {
    final frac = (current / max).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('CAPACIDAD', style: _raj(8, FontWeight.w700, _kSub, spacing: 1)),
        const Spacer(),
        Text('$current / $max', style: _raj(9, FontWeight.w700, _kDim)),
      ]),
      const SizedBox(height: 5),
      Stack(children: [
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: _shBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: frac,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: _kDim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _shBarrioCell(_BarrioData b) {
    final pct = b.porcentajeCubierto;
    const Color color = _kSub;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _moverCamara(b.centro, 13.5);
        if (_sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(0.13,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic);
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _shSurf,
          border: Border.all(color: _shBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 3, height: 32,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.nombre,
                style: _raj(12, FontWeight.w600, _shText),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Stack(children: [
              Container(height: 2,
                  decoration: BoxDecoration(color: _shBorder, borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                widthFactor: pct.clamp(0.0, 1.0),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: _kDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ]),
          ])),
          const SizedBox(width: 12),
          Text(pct >= 1.0 ? '100%' : '${(pct * 100).toInt()}%',
              style: _raj(13, FontWeight.w800, _shText)),
        ]),
      ),
    );
  }

  /// Card de territorio global en la sheet — muestra clausulaKm real
  Widget _globalTerCard(GlobalTerritory t) {
    final Color baseColor = t.isMine
        ? _kGold
        : t.isOwned
            ? (t.ownerColor ?? t.tierColor)
            : t.tierColor;
    final diffColor = _dificultadColor(t.difficultyLevel);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _onGlobalTerritoryTap(t);
        _sheetCtrl.animateTo(0.13,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _shSurf,
          border: Border.all(
              color: t.isMine
                  ? _kGold.withValues(alpha: 0.40)
                  : t.isOwned
                      ? baseColor.withValues(alpha: 0.30)
                      : _shBorder),
          borderRadius: BorderRadius.circular(10),
          boxShadow: t.isMine
              ? [BoxShadow(color: _kGold.withValues(alpha: 0.10), blurRadius: 16)]
              : t.isOwned
                  ? [BoxShadow(color: baseColor.withValues(alpha: 0.07), blurRadius: 12)]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:  baseColor.withValues(alpha: t.isOwned ? 0.12 : 0.06),
              shape:  BoxShape.circle,
              border: Border.all(
                  color: baseColor.withValues(alpha: t.isOwned ? 0.45 : 0.25)),
            ),
            child: Center(
              child: Icon(
                t.tier == TerritoryTier.legendario
                    ? Icons.stars_rounded
                    : t.tier == TerritoryTier.mediano
                        ? Icons.shield_rounded
                        : Icons.flag_rounded,
                color: baseColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.10),
                  border: Border.all(color: baseColor.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(t.tierLabel,
                    style: _raj(7, FontWeight.w900, baseColor, spacing: 1)),
              ),
              const SizedBox(width: 6),
              if (t.isMine)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('TUYO',
                      style: _raj(7, FontWeight.w900, _kGold)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(t.epicName,
                style: _raj(12, FontWeight.w700, _shText),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              if (t.isOwned) ...[
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
                  margin: const EdgeInsets.only(right: 5),
                ),
              ],
              Text(
                t.isOwned && !t.isMine
                    ? t.ownerNickname!
                    : t.isMine
                        ? 'Controlado por ti'
                        : 'Disponible',
                style: _raj(9, FontWeight.w600,
                    t.isMine
                        ? _kGold
                        : (t.isOwned ? baseColor : _kSafe)),
              ),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color:  diffColor.withValues(alpha: 0.10),
                border: Border.all(color: diffColor.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${t.difficultyLevel}/10',
                  style: _raj(10, FontWeight.w900, diffColor)),
            ),
            const SizedBox(height: 6),
            Text('${t.kmRequired.toStringAsFixed(1)} km',
                style: _raj(11, FontWeight.w700, _kCyan)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on_rounded, size: 10, color: _kGoldDim),
              const SizedBox(width: 3),
              Text('+${t.rewardActual}',
                  style: _raj(10, FontWeight.w600, _kGoldDim)),
            ]),
          ]),
        ]),
      ),
    );
  }
}
