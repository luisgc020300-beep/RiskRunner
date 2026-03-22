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

// ── Paleta (coherente con el resto de la app) ─────────────────────────────────
const _kBg         = Color(0xFF090807);
const _kSurface    = Color(0xFF0F0D0A);
const _kBorder     = Color(0xFF2A2218);
const _kGold       = Color(0xFFD4A84C);
const _kGoldLight  = Color(0xFFEDD98A);
const _kGoldDim    = Color(0xFF7A5E28);
const _kTerracotta = Color(0xFFD4722A);
const _kDim        = Color(0xFF5A5040);

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
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _kGold, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'RANKING DE CLANES',
          style: GoogleFonts.rajdhani(
            color:        _kGoldLight,
            fontSize:     15,
            fontWeight:   FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kTerracotta,
          indicatorWeight: 2,
          labelColor: _kGoldLight,
          unselectedLabelColor: _kDim,
          labelStyle: GoogleFonts.rajdhani(
              fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
          unselectedLabelStyle: GoogleFonts.rajdhani(
              fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: '⚔️  SEMANAL'),
            Tab(text: '🏆  TOTAL'),
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
                const Text('⚔️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'Todavía no hay clanes\nen el ranking',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rajdhani(
                      color: _kDim, fontSize: 15, fontWeight: FontWeight.w600),
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final puntos = usarPuntosTotal
            ? entry.clan.puntos
            : entry.puntosSemana;
        return _ClanRankCard(
          entry:   entry,
          puntos:  puntos,
          esTotal: usarPuntosTotal,
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

  const _ClanRankCard({
    required this.entry,
    required this.puntos,
    required this.esTotal,
  });

  @override
  Widget build(BuildContext context) {
    final clan     = entry.clan;
    final pos      = entry.posicion;
    final clanColor = clan.colorObj;
    final esPodio  = pos <= 3;

    // Colores y estilos del podio
    final podioColor = pos == 1
        ? const Color(0xFFFFD700) // oro
        : pos == 2
            ? const Color(0xFFB0BEC5) // plata
            : const Color(0xFFBF8B5E); // bronce
    final podioEmoji = pos == 1 ? '🥇' : pos == 2 ? '🥈' : '🥉';

    return GestureDetector(
      onTap: () => HapticFeedback.selectionClick(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: esPodio
              ? podioColor.withValues(alpha: 0.06)
              : _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: esPodio
                ? podioColor.withValues(alpha: 0.4)
                : _kBorder,
            width: esPodio ? 1.5 : 1,
          ),
          boxShadow: esPodio
              ? [
                  BoxShadow(
                    color:      podioColor.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset:     const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(children: [
          // ── Posición ────────────────────────────────────────────────────
          SizedBox(
            width: 40,
            child: esPodio
                ? Text(podioEmoji,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22))
                : Text(
                    '#$pos',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.orbitron(
                      color:      _kDim,
                      fontSize:   13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 10),

          // ── Emoji + color del clan ────────────────────────────────────
          Container(
            width:  44,
            height: 44,
            decoration: BoxDecoration(
              color:        clanColor.withValues(alpha: 0.12),
              shape:        BoxShape.circle,
              border: Border.all(
                  color: clanColor.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Center(
              child: Text(clan.emoji,
                  style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),

          // ── Nombre y tag ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    '[${clan.tag}]',
                    style: GoogleFonts.rajdhani(
                      color:        clanColor,
                      fontSize:     11,
                      fontWeight:   FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      clan.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.rajdhani(
                        color:      Colors.white,
                        fontSize:   14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    '${clan.miembros.length} miembros',
                    style: GoogleFonts.rajdhani(
                        color: _kDim, fontSize: 11),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${clan.victorias}V / ${clan.derrotas}D',
                    style: GoogleFonts.rajdhani(
                        color: _kGoldDim, fontSize: 11),
                  ),
                ]),
              ],
            ),
          ),

          // ── Puntos ────────────────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPuntos(puntos),
                style: GoogleFonts.orbitron(
                  color:      esPodio ? podioColor : _kGold,
                  fontSize:   18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                esTotal ? 'pts totales' : 'pts semana',
                style: GoogleFonts.rajdhani(
                    color: _kDim, fontSize: 9, letterSpacing: 1),
              ),
            ],
          ),
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