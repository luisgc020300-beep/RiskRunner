import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// =============================================================================
// DESIGN TOKENS
// =============================================================================
class _RR {
  static const parchm = Color(0xFF3C3C43);
  static const parchd = Color(0xFF636366);
  static const bronze = Color(0xFF636366);
}

// =============================================================================
// MODELO STORY
// =============================================================================
class StoryModel {
  final String id;
  final String userId;
  final String userNickname;
  final String? userAvatarBase64;
  final Color userColor;
  final String tipo;
  final String? mediaBase64;
  final String? videoBase64;
  final String? caption;
  final double? distanciaKm;
  final Duration? tiempo;
  final double? velocidadMedia;
  final int? territoriosConquistados;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewedBy;

  StoryModel({
    required this.id,
    required this.userId,
    required this.userNickname,
    this.userAvatarBase64,
    required this.userColor,
    required this.tipo,
    this.mediaBase64,
    this.videoBase64,
    this.caption,
    this.distanciaKm,
    this.tiempo,
    this.velocidadMedia,
    this.territoriosConquistados,
    required this.createdAt,
    required this.expiresAt,
    required this.viewedBy,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isViewedByMe {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && viewedBy.contains(uid);
  }

  factory StoryModel.fromFirestore(DocumentSnapshot doc, Color color) {
    final d          = (doc.data() ?? {}) as Map<String, dynamic>;
    final createdTs  = d['createdAt'] as Timestamp?;
    final expiresTs  = d['expiresAt'] as Timestamp?;
    final viewedList = (d['viewedBy'] as List<dynamic>?) ?? [];
    final tiempoSeg  = (d['tiempoSegundos'] as num?)?.toInt();

    return StoryModel(
      id:                      doc.id,
      userId:                  d['userId']                ?? '',
      userNickname:            d['userNickname']           ?? 'Runner',
      userAvatarBase64:        d['userAvatarBase64']       as String?,
      userColor:               color,
      tipo:                    d['tipo']                   ?? 'photo',
      mediaBase64:             d['mediaBase64']            as String?,
      videoBase64:             d['videoBase64']            as String?,
      caption:                 d['caption']                as String?,
      distanciaKm:             (d['distanciaKm']           as num?)?.toDouble(),
      tiempo:                  tiempoSeg != null ? Duration(seconds: tiempoSeg) : null,
      velocidadMedia:          (d['velocidadMedia']        as num?)?.toDouble(),
      territoriosConquistados: (d['territoriosConquistados'] as num?)?.toInt(),
      createdAt:               createdTs?.toDate()  ?? DateTime.now(),
      expiresAt:               expiresTs?.toDate()  ?? DateTime.now().add(const Duration(hours: 24)),
      viewedBy:                viewedList.map((e) => e.toString()).toList(),
    );
  }
}

// =============================================================================
// GRUPO DE STORIES POR USUARIO
// =============================================================================
class UserStoriesGroup {
  final String userId;
  final String nickname;
  final String? avatarBase64;
  final Color color;
  final List<StoryModel> stories;

  UserStoriesGroup({
    required this.userId,
    required this.nickname,
    this.avatarBase64,
    required this.color,
    required this.stories,
  });
}

// =============================================================================
// STORY VIEWER SCREEN
// =============================================================================
class StoryViewerScreen extends StatefulWidget {
  final List<UserStoriesGroup> groups;
  final int initialGroupIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  late int _groupIdx;
  int _storyIdx = 0;

  late AnimationController _progressCtrl;
  static const Duration _photoDuration = Duration(seconds: 5);
  static const Duration _statsDuration = Duration(seconds: 6);

  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _groupIdx    = widget.initialGroupIndex;
    _progressCtrl = AnimationController(vsync: this);
    _loadStory();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  UserStoriesGroup get _group        => widget.groups[_groupIdx];
  StoryModel       get _story        => _group.stories[_storyIdx];
  int              get _totalStories => _group.stories.length;

  Future<void> _loadStory() async {
    _progressCtrl.stop();
    await _markAsViewed();
    final dur = _story.tipo == 'run_stats' ? _statsDuration : _photoDuration;
    _startProgressTimer(dur);
  }

  void _startProgressTimer(Duration duration) {
    _progressCtrl.duration = duration;
    _progressCtrl.reset();
    _progressCtrl.forward().then((_) {
      if (mounted && !_paused) _nextStory();
    });
    if (mounted) setState(() {});
  }

  Future<void> _markAsViewed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('stories')
          .doc(_story.id)
          .update({'viewedBy': FieldValue.arrayUnion([uid])});
    } catch (_) {}
  }

  void _nextStory() {
    if (_storyIdx < _totalStories - 1) {
      setState(() => _storyIdx++);
      _loadStory();
    } else {
      _nextGroup();
    }
  }

  void _prevStory() {
    if (_storyIdx > 0) {
      setState(() => _storyIdx--);
      _loadStory();
    } else {
      _prevGroup();
    }
  }

  void _nextGroup() {
    if (_groupIdx < widget.groups.length - 1) {
      setState(() { _groupIdx++; _storyIdx = 0; });
      _loadStory();
    } else {
      Navigator.pop(context);
    }
  }

  void _prevGroup() {
    if (_groupIdx > 0) {
      setState(() { _groupIdx--; _storyIdx = 0; });
      _loadStory();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final x = d.globalPosition.dx;
          final w = MediaQuery.of(context).size.width;
          if (x < w * 0.35) { _prevStory(); } else { _nextStory(); }
        },
        onLongPressStart: (_) {
          _paused = true;
          _progressCtrl.stop();
          setState(() {});
        },
        onLongPressEnd: (_) {
          _paused = false;
          _progressCtrl.forward().then((_) {
            if (mounted && !_paused) _nextStory();
          });
          setState(() {});
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildStoryContent(),

            // Gradiente superior
            Positioned(
              top: 0, left: 0, right: 0, height: 160,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Gradiente inferior
            Positioned(
              bottom: 0, left: 0, right: 0, height: 160,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Barras de progreso
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12, right: 12,
              child: _buildProgressBars(),
            ),

            // Header usuario
            Positioned(
              top: MediaQuery.of(context).padding.top + 26,
              left: 14, right: 14,
              child: _buildUserHeader(),
            ),

            // Caption
            if (_story.caption != null && _story.caption!.isNotEmpty)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 32,
                left: 20, right: 20,
                child: Text(
                  _story.caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              ),

            // Pausa overlay
            if (_paused)
              const Center(
                child: Icon(Icons.pause_circle_filled,
                    color: Colors.white54, size: 64),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBars() {
    return Row(
      children: List.generate(_totalStories, (i) {
        return Expanded(
          child: Container(
            height: 2.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedBuilder(
              animation: _progressCtrl,
              builder: (_, __) {
                double progress = 0;
                if (i < _storyIdx)      progress = 1.0;
                else if (i == _storyIdx) progress = _progressCtrl.value;
                return LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white30,
                  valueColor: AlwaysStoppedAnimation<Color>(_group.color),
                  borderRadius: BorderRadius.circular(2),
                );
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _buildUserHeader() {
    final timeAgo = _formatTimeAgo(_story.createdAt);
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _group.color, width: 2),
        ),
        child: ClipOval(
          child: _group.avatarBase64 != null
              ? Image.memory(base64Decode(_group.avatarBase64!), fit: BoxFit.cover)
              : Container(
                  color: _group.color.withOpacity(0.2),
                  child: Center(
                    child: Text(
                      _group.nickname[0].toUpperCase(),
                      style: TextStyle(
                          color: _group.color,
                          fontWeight: FontWeight.w900,
                          fontSize: 18),
                    ),
                  ),
                ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _group.nickname.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          Text(timeAgo,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      ),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
        ),
      ),
    ]);
  }

  Widget _buildStoryContent() {
    final story = _story;
    switch (story.tipo) {
      case 'photo':
        if (story.mediaBase64 != null) {
          return Image.memory(
            base64Decode(story.mediaBase64!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
        return _buildColorBg(story.userColor);

      case 'video':
        if (story.mediaBase64 != null) {
          return Image.memory(
            base64Decode(story.mediaBase64!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
        return _buildColorBg(story.userColor);

      case 'run_stats':
        return _buildRunStatsContent(story);

      default:
        return _buildColorBg(story.userColor);
    }
  }

  Widget _buildColorBg(Color color) => Container(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [color.withOpacity(0.25), Colors.black],
      ),
    ),
  );

  Widget _buildRunStatsContent(StoryModel story) {
    String? tiempoStr;
    if (story.tiempo != null) {
      final h = story.tiempo!.inHours;
      final m = story.tiempo!.inMinutes.remainder(60);
      final s = story.tiempo!.inSeconds.remainder(60);
      tiempoStr = h > 0
          ? '${h}h ${m.toString().padLeft(2, '0')}m'
          : '${m}m ${s.toString().padLeft(2, '0')}s';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black,
            story.userColor.withOpacity(0.15),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: story.userColor, width: 2),
                  color: story.userColor.withOpacity(0.08),
                ),
                child: Icon(Icons.directions_run_rounded,
                    color: story.userColor, size: 34),
              ),
              const SizedBox(height: 24),

              // Título
              Text(
                'CARRERA COMPLETADA',
                style: TextStyle(
                  color: story.userColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),

              // Nickname
              Text(
                story.userNickname.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),

              // Stats
              Row(children: [
                if (story.distanciaKm != null)
                  _statCard(
                    value: story.distanciaKm!.toStringAsFixed(2),
                    unit: 'KM',
                    color: story.userColor,
                    big: true,
                  ),
                if (tiempoStr != null) ...[
                  const SizedBox(width: 12),
                  _statCard(value: tiempoStr, unit: 'TIEMPO', color: _RR.parchm),
                ],
                if (story.velocidadMedia != null) ...[
                  const SizedBox(width: 12),
                  _statCard(
                    value: story.velocidadMedia!.toStringAsFixed(1),
                    unit: 'KM/H',
                    color: _RR.bronze,
                  ),
                ],
              ]),

              // Territorios
              if (story.territoriosConquistados != null &&
                  story.territoriosConquistados! > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: story.userColor.withOpacity(0.10),
                    border: Border.all(color: story.userColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag_rounded,
                          color: story.userColor, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        '${story.territoriosConquistados} '
                        'TERRITORIO${story.territoriosConquistados! > 1 ? 'S' : ''} '
                        'CONQUISTADO${story.territoriosConquistados! > 1 ? 'S' : ''}',
                        style: TextStyle(
                          color: story.userColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String value,
    required String unit,
    required Color color,
    bool big = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: big ? 32 : 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              shadows: [Shadow(color: color.withOpacity(0.4), blurRadius: 12)],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: const TextStyle(
              color: _RR.parchd,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ]),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours   < 24) return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }
}