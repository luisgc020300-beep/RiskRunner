import 'package:RiskRunner/pesta%C3%B1as/story_viewer_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// =============================================================================
// STORY SERVICE
// =============================================================================
class StoryService {
  static final _db = FirebaseFirestore.instance;

  // ── Subir una historia ────────────────────────────────────────────────────
  static Future<void> uploadStory({
    required String tipo, // 'photo' | 'video' | 'run_stats'
    String? mediaBase64,
    String? videoBase64,
    String? caption,
    double? distanciaKm,
    Duration? tiempo,
    double? velocidadMedia,
    int? territoriosConquistados,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final playerDoc = await _db.collection('players').doc(user.uid).get();
    final data = playerDoc.data() ?? {};
    final nickname     = data['nickname']       ?? 'Runner';
    final avatarBase64 = data['foto_base64']    as String?;
    final colorInt     = (data['territorio_color'] as num?)?.toInt();

    final now       = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    await _db.collection('stories').add({
      'userId':                  user.uid,
      'userNickname':            nickname,
      'userAvatarBase64':        avatarBase64,
      'userColorInt':            colorInt,
      'tipo':                    tipo,
      'mediaBase64':             mediaBase64,
      'videoBase64':             videoBase64,
      'caption':                 caption,
      'distanciaKm':             distanciaKm,
      'tiempoSegundos':          tiempo?.inSeconds,
      'velocidadMedia':          velocidadMedia,
      'territoriosConquistados': territoriosConquistados,
      'createdAt':               Timestamp.fromDate(now),
      'expiresAt':               Timestamp.fromDate(expiresAt),
      'viewedBy':                <String>[],
    });
  }

  // ── Obtener historias activas de un conjunto de userIds ───────────────────
  // Usa chunks de 10 para respetar el límite de whereIn de Firestore.
  // Sin orderBy compuesto → no necesita índice compuesto.
  static Future<Map<String, List<StoryModel>>> fetchActiveStoriesForUsers(
    List<String> userIds, {
    Color defaultColor = const Color(0xFFCC7C3A),
  }) async {
    if (userIds.isEmpty) return {};

    final now = Timestamp.fromDate(DateTime.now());
    final Map<String, List<StoryModel>> result = {};

    // Dividir en chunks de 10 (límite de whereIn en Firestore)
    for (int i = 0; i < userIds.length; i += 10) {
      final end   = (i + 10 < userIds.length) ? i + 10 : userIds.length;
      final chunk = userIds.sublist(i, end);

      try {
        final snap = await _db
            .collection('stories')
            .where('userId', whereIn: chunk)
            .where('expiresAt', isGreaterThan: now)
            .get();

        for (final doc in snap.docs) {
          final d        = doc.data();
          final uid      = d['userId'] as String? ?? '';
          if (uid.isEmpty) continue;

          final colorInt = (d['userColorInt'] as num?)?.toInt();
          final color    = colorInt != null ? Color(colorInt) : defaultColor;

          final story = StoryModel.fromFirestore(doc, color);
          result.putIfAbsent(uid, () => []).add(story);
        }
      } catch (e) {
        debugPrint('StoryService.fetchActiveStoriesForUsers error chunk $i: $e');
      }
    }

    // Ordenar cada lista por createdAt descendente (más reciente primero)
    for (final list in result.values) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return result;
  }

  // ── Obtener mis propias historias activas ─────────────────────────────────
  // Sin doble orderBy → no necesita índice compuesto.
  static Future<List<StoryModel>> fetchMyActiveStories({
    Color defaultColor = const Color(0xFFCC7C3A),
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final now = Timestamp.fromDate(DateTime.now());

    try {
      final snap = await _db
          .collection('stories')
          .where('userId', isEqualTo: uid)
          .where('expiresAt', isGreaterThan: now)
          .get();

      final stories = snap.docs.map((doc) {
        final d        = doc.data();
        final colorInt = (d['userColorInt'] as num?)?.toInt();
        final color    = colorInt != null ? Color(colorInt) : defaultColor;
        return StoryModel.fromFirestore(doc, color);
      }).toList();

      // Ordenar por createdAt descendente en cliente
      stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return stories;
    } catch (e) {
      debugPrint('StoryService.fetchMyActiveStories error: $e');
      return [];
    }
  }

  // ── Eliminar historias expiradas (llamar en background) ───────────────────
  static Future<void> purgeExpiredStories() async {
    final now = Timestamp.fromDate(DateTime.now());
    try {
      final snap = await _db
          .collection('stories')
          .where('expiresAt', isLessThan: now)
          .limit(50)
          .get();

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      if (snap.docs.isNotEmpty) await batch.commit();
    } catch (e) {
      debugPrint('StoryService.purgeExpiredStories error: $e');
    }
  }
}