// lib/Pestañas/clan_ranking_screen.dart
//
// Pantalla de ranking de clanes: semanal y total acumulado.
// Se accede desde la ClanScreen con un botón de trofeo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/clan_service.dart';
import '../widgets/custom_navbar.dart';

// ── Paleta iOS ───────────────────────────────────────────────────────────────���
const _kSurface = Color(0xFFFFFFFF);
const _kSep     = Color(0xFFC6C6C8);
const _kDim     = Color(0xFFAEAEB2);
const _kWhite   = Color(0xFF1C1C1E);
const _kBlue    = Color(0xFFE02020);
const _kGold    = Color(0xFFFFD60A);

TextStyle _dm(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.dmSans(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

TextStyle _raj(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

// ── Modelo de entrada de ranking ──────────────────────────────────────────────
class _ClanRankEntry {
  final int posicion;
  final ClanData clan;
  final int puntosSemana;

  const _ClanRankEntry({
    required this.posicion,
    required this.clan,
    required this.puntosSemana,
  });
}

// =============================================================================
// PANTALLA PRINCIPAL
// =============================================================================
class ClanRankingScreen extends StatefulWidget {
  const ClanRankingScreen({super.key});

  @override
  State<ClanRankingScreen> createState() => _ClanRankingScreenState();
}

class _ClanRankingScreenState extends State<ClanRankingScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Ranking de clanes', style: _dm(15, FontWeight.w600, Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kBlue,
          indicatorWeight: 2,
          labelColor: Colors.white,
          unselectedLabelColor: _kDim,
          labelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w400),
          tabs: const [
            Tab(text: 'Semanal'),
            Tab(text: 'Total'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _RankingTab(modo: _RankingModo.semanal),
          _RankingTab(modo: _RankingModo.total),
        ],
      ),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 3),
    );
  }
}

// =============================================================================
// ENUM MODO
// =============================================================================
enum _RankingModo { semanal, total }

// =============================================================================
// TAB DE RANKING
// =============================================================================
class _RankingTab extends StatelessWidget {
  final _RankingModo modo;
  const _RankingTab({super.key, required this.modo});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClanData>>(
      stream: ClanService.topClanes(limit: 50),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
                color: _kGold, strokeWidth: 2),
          );
        }
        if (!snap.hasData || snap.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, color: _kDim, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Todavía no hay clanes\nen el ranking',
                  textAlign: TextAlign.center,
                  style: _dm(15, FontWeight.w400, _kDim),
                ),
              ],
            ),
          );
        }

        // Para el ranking semanal necesitamos leer puntos_semana de Firestore.
        // Por simplicidad, el modo semanal usa puntos_semana si existe,
        // y si no, muestra los puntos totales (ambos se ven igual hasta que
        // el reset semanal esté implementado con Cloud Function).
        final clanes = snap.data!;

        if (modo == _RankingModo.semanal) {
          return _buildRankingSemanal(clanes);
        } else {
          return _buildRankingTotal(clanes);
        }
      },
    );
  }

  Widget _buildRankingTotal(List<ClanData> clanes) {
    // Ordenar por puntos totales descendente (ya viene ordenado del stream)
    final entries = clanes.asMap().entries.map((e) => _ClanRankEntry(
          posicion:       e.key + 1,
          clan:           e.value,
          puntosSemana:   0, // no aplica en total
        )).toList();

    return _buildLista(entries, usarPuntosTotal: true);
  }

  Widget _buildRankingSemanal(List<ClanData> clanes) {
    // Para el ranking semanal leemos puntos_semana del documento del clan.
    // Si no existe ese campo (clanes antiguos), usamos 0.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('clans')
          .orderBy('puntos_semana', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kGold, strokeWidth: 2),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          // Fallback: usar la lista de clanes con puntos_semana = 0
          final entries = clanes.asMap().entries.map((e) => _ClanRankEntry(
                posicion:     e.key + 1,
                clan:         e.value,
                puntosSemana: 0,
              )).toList();
          return _buildLista(entries, usarPuntosTotal: false);
        }

        final entries = docs.asMap().entries.map((e) {
          final data = e.value.data() as Map<String, dynamic>;
          final clan = ClanData.fromDoc(e.value);
          return _ClanRankEntry(
            posicion:     e.key + 1,
            clan:         clan,
            puntosSemana: (data['puntos_semana'] as num?)?.toInt() ?? 0,
          );
        }).toList();

        return _buildLista(entries, usarPuntosTotal: false);
      },
    );
  }

  Widget _buildLista(List<_ClanRankEntry> entries,
      {required bool usarPuntosTotal}) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: entries.length,
      separatorBuilder: (_, __) =>
          ColoredBox(color: _kSurface,
              child: Container(height: 0.5, color: _kSep,
                  margin: const EdgeInsets.only(left: 68))),
      itemBuilder: (context, i) {
        final entry = entries[i];
        final puntos = usarPuntosTotal ? entry.clan.puntos : entry.puntosSemana;
        final isFirst = i == 0;
        final isLast  = i == entries.length - 1;
        return _ClanRankCard(
          entry: entry, puntos: puntos, esTotal: usarPuntosTotal,
          isFirst: isFirst, isLast: isLast,
        );
      },
    );
  }
}

// =============================================================================
// TARJETA DE CLAN EN EL RANKING
// =============================================================================
class _ClanRankCard extends StatelessWidget {
  final _ClanRankEntry entry;
  final int puntos;
  final bool esTotal;
  final bool isFirst;
  final bool isLast;

  const _ClanRankCard({
    required this.entry,
    required this.puntos,
    required this.esTotal,
    this.isFirst = false,
    this.isLast  = false,
  });

  @override
  Widget build(BuildContext context) {
    final clan     = entry.clan;
    final pos      = entry.posicion;
    final clanColor = clan.colorObj;
    final esPodio  = pos <= 3;

    final podioColor = pos == 1
        ? const Color(0xFFFFD60A)  // iOS gold
        : pos == 2
            ? const Color(0xFFAEAEB2)  // iOS secondary
            : const Color(0xFFBF8B5E); // bronze

    final radius = BorderRadius.vertical(
      top:    isFirst ? const Radius.circular(12) : Radius.zero,
      bottom: isLast  ? const Radius.circular(12) : Radius.zero,
    );
    return GestureDetector(
      onTap: () => HapticFeedback.selectionClick(),
      child: Container(
        decoration: BoxDecoration(color: _kSurface, borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // ── Posición ─────────────────────────────────────────────────
          SizedBox(
            width: 36,
            child: Text(
              '$pos',
              textAlign: TextAlign.center,
              style: _raj(15, FontWeight.w700,
                  esPodio ? podioColor : _kDim),
            ),
          ),
          const SizedBox(width: 8),

          // ── Emoji del clan ────────────────────────────────────────────
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: clanColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(clan.emoji,
                style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),

          // ── Nombre y tag ──────────────────────────────────────────────
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('[${clan.tag}]', style: _dm(11, FontWeight.w600, clanColor)),
                const SizedBox(width: 6),
                Flexible(child: Text(clan.nombre, overflow: TextOverflow.ellipsis,
                    style: _dm(14, FontWeight.w500, _kWhite))),
              ]),
              const SizedBox(height: 2),
              Text('${clan.miembros.length} miembros  ·  ${clan.victorias}V ${clan.derrotas}D',
                  style: _dm(11, FontWeight.w400, _kDim)),
            ]),
          ),

          // ── Puntos ────────────────────────────────────────────────────
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_formatPuntos(puntos),
                style: _raj(18, FontWeight.w700,
                    esPodio ? podioColor : _kGold)),
            Text(esTotal ? 'pts totales' : 'pts semana',
                style: _dm(10, FontWeight.w400, _kDim)),
          ]),
        ]),
      ),
    );
  }

  String _formatPuntos(int p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}M';
    if (p >= 1000)    return '${(p / 1000).toStringAsFixed(1)}K';
    return p.toString();
  }
}