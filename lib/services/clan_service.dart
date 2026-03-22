// lib/services/clan_service.dart
// ═══════════════════════════════════════════════════════════
//  CLAN SERVICE — lógica central de clanes y guerras
// ═══════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─── Roles ───────────────────────────────────────────────────
enum ClanRol { lider, capitan, miembro }

extension ClanRolExt on ClanRol {
  String get nombre {
    switch (this) {
      case ClanRol.lider:   return 'LÍDER';
      case ClanRol.capitan: return 'CAPITÁN';
      case ClanRol.miembro: return 'MIEMBRO';
    }
  }
  String get id {
    switch (this) {
      case ClanRol.lider:   return 'lider';
      case ClanRol.capitan: return 'capitan';
      case ClanRol.miembro: return 'miembro';
    }
  }
  static ClanRol fromString(String s) {
    switch (s) {
      case 'lider':   return ClanRol.lider;
      case 'capitan': return ClanRol.capitan;
      default:        return ClanRol.miembro;
    }
  }
}

// ─── Estado de guerra ────────────────────────────────────────
enum WarEstado { activa, finalizada, cancelada }

// ─── Modelos ─────────────────────────────────────────────────

class ClanMiembro {
  final String uid;
  final String nickname;
  final ClanRol rol;
  final int puntosAportados;
  final String? fotoBase64;

  const ClanMiembro({
    required this.uid,
    required this.nickname,
    required this.rol,
    this.puntosAportados = 0,
    this.fotoBase64,
  });

  factory ClanMiembro.fromMap(Map<String, dynamic> m) => ClanMiembro(
    uid:              m['uid'] as String,
    nickname:         m['nickname'] as String? ?? '?',
    rol:              ClanRolExt.fromString(m['rol'] as String? ?? 'miembro'),
    puntosAportados:  (m['puntosAportados'] as num? ?? 0).toInt(),
    fotoBase64:       m['fotoBase64'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'uid':             uid,
    'nickname':        nickname,
    'rol':             rol.id,
    'puntosAportados': puntosAportados,
    if (fotoBase64 != null) 'fotoBase64': fotoBase64,
  };

  ClanMiembro copyWith({int? puntosAportados, ClanRol? rol}) => ClanMiembro(
    uid: uid, nickname: nickname, fotoBase64: fotoBase64,
    rol: rol ?? this.rol,
    puntosAportados: puntosAportados ?? this.puntosAportados,
  );
}

class ClanData {
  final String clanId;
  final String nombre;
  final String tag;
  final String descripcion;
  final String leaderId;
  final int color;
  final String emoji;
  final int puntos;
  final List<ClanMiembro> miembros;
  final int maxMiembros;
  final DateTime? createdAt;
  final int victorias;
  final int derrotas;

  const ClanData({
    required this.clanId,
    required this.nombre,
    required this.tag,
    required this.descripcion,
    required this.leaderId,
    required this.color,
    required this.emoji,
    required this.puntos,
    required this.miembros,
    this.maxMiembros = 10,
    this.createdAt,
    this.victorias = 0,
    this.derrotas = 0,
  });

  factory ClanData.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawMiembros = d['miembros'] as List<dynamic>? ?? [];
    return ClanData(
      clanId:      doc.id,
      nombre:      d['nombre'] as String? ?? '',
      tag:         d['tag'] as String? ?? '',
      descripcion: d['descripcion'] as String? ?? '',
      leaderId:    d['leaderId'] as String? ?? '',
      color:       (d['color'] as num? ?? 0xFFCC2222).toInt(),
      emoji:       d['emoji'] as String? ?? '⚔️',
      puntos:      (d['puntos'] as num? ?? 0).toInt(),
      miembros:    rawMiembros.map((m) => ClanMiembro.fromMap(m as Map<String, dynamic>)).toList(),
      maxMiembros: (d['maxMiembros'] as num? ?? 10).toInt(),
      victorias:   (d['victorias'] as num? ?? 0).toInt(),
      derrotas:    (d['derrotas'] as num? ?? 0).toInt(),
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Color get colorObj => Color(color);

  ClanMiembro? miembro(String uid) =>
      miembros.where((m) => m.uid == uid).firstOrNull;

  bool get estaLleno => miembros.length >= maxMiembros;

  double get winRate => (victorias + derrotas) == 0
      ? 0 : victorias / (victorias + derrotas);
}

class ClanWar {
  final String warId;
  final Map<String, dynamic> clanA;
  final Map<String, dynamic> clanB;
  final WarEstado estado;
  final DateTime inicio;
  final DateTime fin;
  final String tipo;
  final Map<String, int> puntuacion;
  final String? ganadorId;
  final Map<String, dynamic>? zonaConflicto;

  const ClanWar({
    required this.warId,
    required this.clanA,
    required this.clanB,
    required this.estado,
    required this.inicio,
    required this.fin,
    required this.tipo,
    required this.puntuacion,
    this.ganadorId,
    this.zonaConflicto,
  });

  factory ClanWar.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawPun = d['puntuacion'] as Map<String, dynamic>? ?? {};
    return ClanWar(
      warId:        doc.id,
      clanA:        (d['clanA'] as Map<String, dynamic>?) ?? {},
      clanB:        (d['clanB'] as Map<String, dynamic>?) ?? {},
      estado:       _parseEstado(d['estado'] as String? ?? 'activa'),
      inicio:       (d['inicio'] as Timestamp).toDate(),
      fin:          (d['fin'] as Timestamp).toDate(),
      tipo:         d['tipo'] as String? ?? 'conquista',
      puntuacion:   rawPun.map((k, v) => MapEntry(k, (v as num).toInt())),
      ganadorId:    d['ganadorId'] as String?,
      zonaConflicto: d['zonaConflicto'] as Map<String, dynamic>?,
    );
  }

  static WarEstado _parseEstado(String s) {
    switch (s) {
      case 'finalizada': return WarEstado.finalizada;
      case 'cancelada':  return WarEstado.cancelada;
      default:           return WarEstado.activa;
    }
  }

  bool get activa => estado == WarEstado.activa;
  Duration get tiempoRestante => fin.difference(DateTime.now());

  String get tiempoRestanteStr {
    final diff = tiempoRestante;
    if (diff.isNegative) return 'FINALIZADA';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h >= 24) return '${diff.inDays}d ${h.remainder(24)}h';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}

class ClanInvite {
  final String inviteId;
  final String clanId;
  final String clanNombre;
  final String clanTag;
  final String fromUid;
  final String fromNickname;
  final String toUid;
  final String estado;
  final DateTime? timestamp;

  const ClanInvite({
    required this.inviteId,
    required this.clanId,
    required this.clanNombre,
    required this.clanTag,
    required this.fromUid,
    required this.fromNickname,
    required this.toUid,
    required this.estado,
    this.timestamp,
  });

  factory ClanInvite.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ClanInvite(
      inviteId:    doc.id,
      clanId:      d['clanId'] as String? ?? '',
      clanNombre:  d['clanNombre'] as String? ?? '',
      clanTag:     d['clanTag'] as String? ?? '',
      fromUid:     d['fromUid'] as String? ?? '',
      fromNickname: d['fromNickname'] as String? ?? '?',
      toUid:       d['toUid'] as String? ?? '',
      estado:      d['estado'] as String? ?? 'pending',
      timestamp:   (d['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SERVICE
// ═══════════════════════════════════════════════════════════

class ClanService {
  static final _db = FirebaseFirestore.instance;

  static String? get myUid => FirebaseAuth.instance.currentUser?.uid;

  // ── Obtener clan del usuario actual ──────────────────────
  static Future<ClanData?> miClan() async {
    if (myUid == null) return null;
    try {
      final playerDoc = await _db.collection('players').doc(myUid).get();
      final clanId = playerDoc.data()?['clanId'] as String?;
      if (clanId == null) return null;
      final clanDoc = await _db.collection('clans').doc(clanId).get();
      if (!clanDoc.exists) return null;
      return ClanData.fromDoc(clanDoc);
    } catch (e) {
      debugPrint('Error miClan: $e');
      return null;
    }
  }

  // ── Stream del clan del usuario ───────────────────────────
  static Stream<ClanData?> miClanStream() {
    if (myUid == null) return Stream.value(null);
    return _db.collection('players').doc(myUid).snapshots().asyncMap((playerDoc) async {
      final clanId = playerDoc.data()?['clanId'] as String?;
      if (clanId == null) return null;
      final clanDoc = await _db.collection('clans').doc(clanId).get();
      if (!clanDoc.exists) return null;
      return ClanData.fromDoc(clanDoc);
    });
  }

  // ── Stream directo del clan por id ────────────────────────
  static Stream<ClanData?> clanStream(String clanId) =>
      _db.collection('clans').doc(clanId).snapshots().map(
        (doc) => doc.exists ? ClanData.fromDoc(doc) : null);

  // ── Crear clan ────────────────────────────────────────────
  static Future<String?> crearClan({
    required String nombre,
    required String tag,
    required String descripcion,
    required int color,
    required String emoji,
    required String myNickname,
    String? myFoto,
  }) async {
    if (myUid == null) return null;

    // Verificar que no esté en otro clan
    final existing = await miClan();
    if (existing != null) throw Exception('Ya perteneces a un clan');

    // Verificar tag único
    final tagSnap = await _db.collection('clans')
        .where('tag', isEqualTo: tag.toUpperCase()).limit(1).get();
    if (tagSnap.docs.isNotEmpty) throw Exception('El tag [$tag] ya está en uso');

    try {
      final ref = _db.collection('clans').doc();
      final miembro = ClanMiembro(
        uid: myUid!, nickname: myNickname,
        rol: ClanRol.lider, puntosAportados: 0, fotoBase64: myFoto,
      );
      await ref.set({
        'clanId':      ref.id,
        'nombre':      nombre,
        'tag':         tag.toUpperCase(),
        'descripcion': descripcion,
        'leaderId':    myUid,
        'color':       color,
        'emoji':       emoji,
        'puntos':      0,
        'victorias':   0,
        'derrotas':    0,
        'maxMiembros': 10,
        'miembros':    [miembro.toMap()],
        'createdAt':   FieldValue.serverTimestamp(),
      });
      // Actualizar jugador
      await _db.collection('players').doc(myUid).update({
        'clanId':     ref.id,
        'clanNombre': nombre,
        'clanTag':    tag.toUpperCase(),
        'clanRol':    'lider',
      });
      return ref.id;
    } catch (e) {
      debugPrint('Error crearClan: $e');
      rethrow;
    }
  }

  // ── Invitar jugador ───────────────────────────────────────
  static Future<void> invitarJugador({
    required ClanData clan,
    required String targetUid,
    required String targetNickname,
    required String myNickname,
  }) async {
    if (myUid == null) return;

    // Verificar que no esté ya en el clan
    if (clan.miembros.any((m) => m.uid == targetUid))
      throw Exception('Este jugador ya está en el clan');

    // Verificar que no haya invitación pendiente
    final existing = await _db.collection('clan_invites')
        .where('clanId', isEqualTo: clan.clanId)
        .where('toUid', isEqualTo: targetUid)
        .where('estado', isEqualTo: 'pending')
        .limit(1).get();
    if (existing.docs.isNotEmpty)
      throw Exception('Ya hay una invitación pendiente');

    await _db.collection('clan_invites').add({
      'clanId':      clan.clanId,
      'clanNombre':  clan.nombre,
      'clanTag':     clan.tag,
      'fromUid':     myUid,
      'fromNickname': myNickname,
      'toUid':       targetUid,
      'estado':      'pending',
      'timestamp':   FieldValue.serverTimestamp(),
    });

    // Notificación
    await _db.collection('notifications').add({
      'toUserId':    targetUid,
      'type':        'clan_invite',
      'fromUserId':  myUid,
      'fromNickname': myNickname,
      'message':     '⚔️ $myNickname te invita al clan [${clan.tag}] ${clan.nombre}',
      'clanId':      clan.clanId,
      'read':        false,
      'timestamp':   FieldValue.serverTimestamp(),
    });
  }

  // ── Aceptar invitación ────────────────────────────────────
  static Future<void> aceptarInvitacion({
    required ClanInvite invite,
    required String myNickname,
    String? myFoto,
  }) async {
    if (myUid == null) return;

    final clanDoc = await _db.collection('clans').doc(invite.clanId).get();
    if (!clanDoc.exists) throw Exception('El clan ya no existe');
    final clan = ClanData.fromDoc(clanDoc);
    if (clan.estaLleno) throw Exception('El clan está lleno');

    final nuevoMiembro = ClanMiembro(
      uid: myUid!, nickname: myNickname,
      rol: ClanRol.miembro, fotoBase64: myFoto,
    );

    final batch = _db.batch();

    // Añadir al clan
    batch.update(_db.collection('clans').doc(invite.clanId), {
      'miembros': FieldValue.arrayUnion([nuevoMiembro.toMap()]),
    });

    // Actualizar jugador
    batch.update(_db.collection('players').doc(myUid), {
      'clanId':     invite.clanId,
      'clanNombre': invite.clanNombre,
      'clanTag':    invite.clanTag,
      'clanRol':    'miembro',
    });

    // Marcar invitación como aceptada
    batch.update(_db.collection('clan_invites').doc(invite.inviteId), {
      'estado': 'accepted',
    });

    await batch.commit();
  }

  // ── Rechazar invitación ───────────────────────────────────
  static Future<void> rechazarInvitacion(String inviteId) async {
    await _db.collection('clan_invites').doc(inviteId).update({'estado': 'rejected'});
  }

  // ── Abandonar clan ────────────────────────────────────────
  static Future<void> abandonarClan(ClanData clan) async {
    if (myUid == null) return;
    if (clan.leaderId == myUid && clan.miembros.length > 1)
      throw Exception('Debes transferir el liderazgo antes de salir');

    final miembro = clan.miembro(myUid!);
    if (miembro == null) return;

    final batch = _db.batch();

    if (clan.miembros.length == 1) {
      // Último miembro — disolver el clan
      batch.delete(_db.collection('clans').doc(clan.clanId));
    } else {
      batch.update(_db.collection('clans').doc(clan.clanId), {
        'miembros': FieldValue.arrayRemove([miembro.toMap()]),
      });
    }

    batch.update(_db.collection('players').doc(myUid), {
      'clanId':     FieldValue.delete(),
      'clanNombre': FieldValue.delete(),
      'clanTag':    FieldValue.delete(),
      'clanRol':    FieldValue.delete(),
    });

    await batch.commit();
  }

  // ── Expulsar miembro (solo lider/capitan) ─────────────────
  static Future<void> expulsarMiembro({
    required ClanData clan,
    required ClanMiembro miembro,
  }) async {
    if (myUid == null) return;
    final yo = clan.miembro(myUid!);
    if (yo == null || yo.rol == ClanRol.miembro)
      throw Exception('Sin permisos para expulsar');
    if (miembro.rol == ClanRol.lider)
      throw Exception('No puedes expulsar al líder');

    final batch = _db.batch();
    batch.update(_db.collection('clans').doc(clan.clanId), {
      'miembros': FieldValue.arrayRemove([miembro.toMap()]),
    });
    batch.update(_db.collection('players').doc(miembro.uid), {
      'clanId':     FieldValue.delete(),
      'clanNombre': FieldValue.delete(),
      'clanTag':    FieldValue.delete(),
      'clanRol':    FieldValue.delete(),
    });
    await batch.commit();
  }

  // ── Promover miembro ──────────────────────────────────────
  static Future<void> promoverMiembro({
    required ClanData clan,
    required ClanMiembro miembro,
    required ClanRol nuevoRol,
  }) async {
    if (myUid == null) return;
    final yo = clan.miembro(myUid!);
    if (yo?.rol != ClanRol.lider) throw Exception('Solo el líder puede promover');

    // Construir lista actualizada
    final nuevaLista = clan.miembros.map((m) {
      if (m.uid == miembro.uid) return m.copyWith(rol: nuevoRol);
      return m;
    }).toList();

    await _db.collection('clans').doc(clan.clanId).update({
      'miembros': nuevaLista.map((m) => m.toMap()).toList(),
    });

    await _db.collection('players').doc(miembro.uid).update({
      'clanRol': nuevoRol.id,
    });
  }

  // ── Sumar puntos al clan (llamado al conquistar territorio) ──
  static Future<void> sumarPuntosAlClan({
    required String clanId,
    required String uid,
    required int puntos,
  }) async {
    try {
      final clanDoc = await _db.collection('clans').doc(clanId).get();
      if (!clanDoc.exists) return;
      final clan = ClanData.fromDoc(clanDoc);
      final nuevaLista = clan.miembros.map((m) {
        if (m.uid == uid) return m.copyWith(puntosAportados: m.puntosAportados + puntos);
        return m;
      }).toList();
      await _db.collection('clans').doc(clanId).update({
        'puntos':   FieldValue.increment(puntos),
        'miembros': nuevaLista.map((m) => m.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('Error sumarPuntosAlClan: $e');
    }
  }

  // ── Declarar guerra ───────────────────────────────────────
  static Future<String?> declararGuerra({
    required ClanData miClan,
    required ClanData rivalClan,
    required String tipo,        // 'conquista' | 'asedio' | 'resistencia'
    required Duration duracion,
  }) async {
    if (myUid == null) return null;
    final yo = miClan.miembro(myUid!);
    if (yo == null || yo.rol == ClanRol.miembro)
      throw Exception('Solo líderes y capitanes pueden declarar guerra');

    // Verificar que no haya guerra activa entre estos clanes
    final existing = await _db.collection('clan_wars')
        .where('estado', isEqualTo: 'activa')
        .get();
    for (final doc in existing.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final a = (d['clanA'] as Map)['id'];
      final b = (d['clanB'] as Map)['id'];
      if ((a == miClan.clanId && b == rivalClan.clanId) ||
          (a == rivalClan.clanId && b == miClan.clanId)) {
        throw Exception('Ya hay una guerra activa entre estos clanes');
      }
    }

    final now   = DateTime.now();
    final fin   = now.add(duracion);
    final ref   = _db.collection('clan_wars').doc();

    await ref.set({
      'warId': ref.id,
      'clanA': {
        'id': miClan.clanId, 'nombre': miClan.nombre,
        'tag': miClan.tag, 'color': miClan.color, 'emoji': miClan.emoji,
      },
      'clanB': {
        'id': rivalClan.clanId, 'nombre': rivalClan.nombre,
        'tag': rivalClan.tag, 'color': rivalClan.color, 'emoji': rivalClan.emoji,
      },
      'estado':     'activa',
      'inicio':     Timestamp.fromDate(now),
      'fin':        Timestamp.fromDate(fin),
      'tipo':       tipo,
      'puntuacion': {'clanA': 0, 'clanB': 0},
      'ganadorId':  null,
      'createdAt':  FieldValue.serverTimestamp(),
    });

    // Notificar a miembros del rival
    for (final m in rivalClan.miembros) {
      await _db.collection('notifications').add({
        'toUserId':   m.uid,
        'type':       'clan_war_declared',
        'fromUserId': myUid,
        'message':    '⚔️ [${miClan.tag}] ${miClan.nombre} os ha declarado la guerra!',
        'warId':      ref.id,
        'read':       false,
        'timestamp':  FieldValue.serverTimestamp(),
      });
    }

    return ref.id;
  }

  // ── Sumar punto en guerra (al conquistar territorio en zona) ──
  static Future<void> puntoClanEnGuerra({
    required String warId,
    required String clanId,
  }) async {
    try {
      final warDoc = await _db.collection('clan_wars').doc(warId).get();
      if (!warDoc.exists) return;
      final war = ClanWar.fromDoc(warDoc);
      if (!war.activa) return;

      final esClanA = (war.clanA['id'] as String) == clanId;
      final key     = esClanA ? 'puntuacion.clanA' : 'puntuacion.clanB';
      await _db.collection('clan_wars').doc(warId).update({
        key: FieldValue.increment(1),
      });

      // Comprobar fin de guerra si es tiempo
      if (DateTime.now().isAfter(war.fin)) {
        await _finalizarGuerra(warId);
      }
    } catch (e) {
      debugPrint('Error puntoClanEnGuerra: $e');
    }
  }

  // ── Finalizar guerra ──────────────────────────────────────
  static Future<void> _finalizarGuerra(String warId) async {
    final warDoc = await _db.collection('clan_wars').doc(warId).get();
    if (!warDoc.exists) return;
    final war = ClanWar.fromDoc(warDoc);
    if (!war.activa) return;

    final pA = war.puntuacion['clanA'] ?? 0;
    final pB = war.puntuacion['clanB'] ?? 0;
    String? ganadorId;
    if (pA > pB) ganadorId = war.clanA['id'] as String;
    else if (pB > pA) ganadorId = war.clanB['id'] as String;

    await _db.collection('clan_wars').doc(warId).update({
      'estado':    'finalizada',
      'ganadorId': ganadorId,
    });

    if (ganadorId != null) {
      // Sumar victorias/derrotas
      final perdedorId = ganadorId == war.clanA['id']
          ? war.clanB['id'] as String
          : war.clanA['id'] as String;
      await _db.collection('clans').doc(ganadorId).update({'victorias': FieldValue.increment(1)});
      await _db.collection('clans').doc(perdedorId).update({'derrotas': FieldValue.increment(1)});
    }
  }

  // ── Streams útiles ────────────────────────────────────────
  static Stream<List<ClanInvite>> misInvitacionesPendientes() {
    if (myUid == null) return Stream.value([]);
    return _db.collection('clan_invites')
        .where('toUid', isEqualTo: myUid)
        .where('estado', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map(ClanInvite.fromDoc).toList());
  }

  static Stream<List<ClanWar>> guerrasActivasDeMiClan(String clanId) =>
      _db.collection('clan_wars')
          .where('estado', isEqualTo: 'activa')
          .snapshots()
          .map((snap) => snap.docs
              .map(ClanWar.fromDoc)
              .where((w) =>
                  w.clanA['id'] == clanId || w.clanB['id'] == clanId)
              .toList());

  static Future<List<ClanWar>> historialGuerras(String clanId) async {
    final snap = await _db.collection('clan_wars')
        .where('estado', isEqualTo: 'finalizada')
        .orderBy('fin', descending: true)
        .limit(20)
        .get();
    return snap.docs
        .map(ClanWar.fromDoc)
        .where((w) => w.clanA['id'] == clanId || w.clanB['id'] == clanId)
        .toList();
  }

  // ── Buscar clanes ─────────────────────────────────────────
  static Future<List<ClanData>> buscarClanes(String query) async {
    if (query.isEmpty) return [];
    final snap = await _db.collection('clans')
        .where('nombre', isGreaterThanOrEqualTo: query)
        .where('nombre', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(15).get();
    return snap.docs.map(ClanData.fromDoc).toList();
  }

  // ── Top clanes por puntos ─────────────────────────────────
  static Stream<List<ClanData>> topClanes({int limit = 20}) =>
      _db.collection('clans')
          .orderBy('puntos', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(ClanData.fromDoc).toList());

  // ── Editar clan (solo líder) ──────────────────────────────
  static Future<void> editarClan({
    required String clanId,
    String? nombre,
    String? descripcion,
    int? color,
    String? emoji,
  }) async {
    final updates = <String, dynamic>{};
    if (nombre      != null) updates['nombre']      = nombre;
    if (descripcion != null) updates['descripcion'] = descripcion;
    if (color       != null) updates['color']       = color;
    if (emoji       != null) updates['emoji']       = emoji;
    if (updates.isEmpty) return;
    await _db.collection('clans').doc(clanId).update(updates);
    // Actualizar clanNombre en players si cambió el nombre
    if (nombre != null) {
      final snap = await _db.collection('players')
          .where('clanId', isEqualTo: clanId).get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'clanNombre': nombre});
      }
      await batch.commit();
    }
  }
}