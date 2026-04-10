// functions/index.js
// Cloud Functions para Risk Runner — Guerra Global + Desafíos + Territorios
// Deploy: firebase deploy --only functions

const { onSchedule }         = require('firebase-functions/v2/scheduler');
const { onDocumentCreated,
        onDocumentUpdated }  = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp }      = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

// =============================================================================
// 1. GUERRA GLOBAL — Liquidar cada lunes a las 00:05 UTC
// =============================================================================
exports.liquidarGuerraGlobal = onSchedule(
  {
    schedule : 'every monday 00:05',
    timeZone : 'UTC',
    memory   : '256MiB',
  },
  async (event) => {
    const ahora          = Timestamp.now();
    const semanaId       = _semanaId(new Date());
    const semanaAnterior = _semanaId(_lunes(-7));

    const snap = await db.collection('global_territories').get();
    if (snap.empty) {
      console.log('No hay territorios globales. Saliendo.');
      return;
    }

    const batch         = db.batch();
    const monedasPorUid = {};
    const ligaPorUid    = {};
    const ganadores     = [];

    for (const doc of snap.docs) {
      const data      = doc.data();
      const ownerUid  = data.ownerUid  || null;
      const ownerNick = data.ownerNickname || 'Desconocido';
      const recompensa = (data.baseReward || 0) * Math.max(data.conquestCount || 1, 1);
      const tier       = data.tier      || 'pequeno';

      const ligaPts = tier === 'legendario' ? 100 : tier === 'mediano' ? 50 : 25;

      const histRef = db
        .collection('global_territories')
        .doc(doc.id)
        .collection('historial_semanal')
        .doc(semanaAnterior);

      batch.set(histRef, {
        semana        : semanaAnterior,
        ownerUid      : ownerUid,
        ownerNickname : ownerNick,
        recompensa    : ownerUid ? recompensa : 0,
        ligaPts       : ownerUid ? ligaPts    : 0,
        cerradoEn     : ahora,
      });

      if (ownerUid) {
        batch.update(doc.ref, {
          conquestCount   : FieldValue.increment(1),
          lastRewardAt    : ahora,
          lastRewardSemana: semanaAnterior,
        });

        monedasPorUid[ownerUid] = (monedasPorUid[ownerUid] || 0) + recompensa;
        ligaPorUid[ownerUid]    = (ligaPorUid[ownerUid]    || 0) + ligaPts;

        ganadores.push({
          uid        : ownerUid,
          nickname   : ownerNick,
          territorio : data.epicName || data.name || doc.id,
          recompensa,
          ligaPts,
        });
      }
    }

    await batch.commit();

    const batchPlayers = db.batch();
    for (const [uid, monedas] of Object.entries(monedasPorUid)) {
      const playerRef = db.collection('players').doc(uid);
      batchPlayers.update(playerRef, {
        monedas     : FieldValue.increment(monedas),
        puntos_liga : FieldValue.increment(ligaPorUid[uid] || 0),
      });
    }
    await batchPlayers.commit();

    const batchNotif = db.batch();
    for (const g of ganadores) {
      const notifRef = db.collection('notifications').doc();
      batchNotif.set(notifRef, {
        toUserId  : g.uid,
        type      : 'guerra_global_recompensa',
        message   : `⚔️ Recompensa semanal: +${g.recompensa} 🪙 y +${g.ligaPts} pts de liga por controlar "${g.territorio}"`,
        read      : false,
        timestamp : ahora,
        semana    : semanaAnterior,
      });
    }
    await batchNotif.commit();

    const resumenRef = db
      .collection('guerra_global_semanas')
      .doc(semanaAnterior);

    await resumenRef.set({
      semana          : semanaAnterior,
      cerradaEn       : ahora,
      totalTeritorios : snap.size,
      conquistados    : ganadores.length,
      ganadores       : ganadores.slice(0, 50),
    });

    // ── RESET COMPLETO DEL MAPA CON ROTACIÓN DE POSICIONES ───────────────
    // Baraja posiciones (puntos, centro, nombre, icon) dentro de cada tier
    // para que el mapa se vea diferente cada semana.
    const porTier = { pequeno: [], mediano: [], legendario: [] };
    for (const doc of snap.docs) {
      const d    = doc.data();
      const tier = d.tier || 'pequeno';
      if (porTier[tier]) {
        porTier[tier].push({
          id:          doc.id,
          puntos:      d.puntos      ?? [],
          centro:      d.centro      ?? null,
          centroLat:   d.centroLat   ?? 0,
          centroLng:   d.centroLng   ?? 0,
          nombre:      d.nombre      ?? d.epicName ?? '',
          epicName:    d.epicName    ?? d.nombre   ?? '',
          icon:        d.icon        ?? '🏴',
          inspiration: d.inspiration ?? '',
        });
      }
    }
    for (const tier of Object.keys(porTier)) _shuffle(porTier[tier]);

    const batchReset = db.batch();
    for (const doc of snap.docs) {
      const d      = doc.data();
      const tier   = d.tier || 'pequeno';
      const baseKm = d.baseKm ?? 5;
      const slot   = porTier[tier].shift();
      batchReset.update(doc.ref, {
        ownerUid:          null,
        ownerNickname:     null,
        ownerColor:        null,
        libre:             true,
        clausulaKm:        baseKm,
        conquestCount:     0,
        kmUltimaConquista: null,
        conquistadoEn:     null,
        puntos:            slot?.puntos      ?? d.puntos    ?? [],
        centro:            slot?.centro      ?? d.centro    ?? null,
        centroLat:         slot?.centroLat   ?? d.centroLat ?? 0,
        centroLng:         slot?.centroLng   ?? d.centroLng ?? 0,
        nombre:            slot?.nombre      ?? d.nombre    ?? '',
        epicName:          slot?.epicName    ?? d.epicName  ?? '',
        icon:              slot?.icon        ?? d.icon      ?? '🏴',
        inspiration:       slot?.inspiration ?? d.inspiration ?? '',
      });
    }
    await batchReset.commit();

    console.log(
      `[liquidarGuerraGlobal] Semana ${semanaAnterior} cerrada. ` +
      `${ganadores.length}/${snap.size} territorios tenían dueño. ` +
      `${Object.keys(monedasPorUid).length} jugadores premiados. ` +
      `Mapa reseteado con rotación de posiciones.`
    );
  }
);

// =============================================================================
// 2. TRIGGER — Cuando se crea una conquista global desde el cliente
// =============================================================================
exports.onGlobalTerritoryConquered = onDocumentCreated(
  'global_territories/{territoryId}',
  async (event) => {
    const data = event.data?.data();
    if (!data?.ownerUid) return;

    const ref = db.collection('global_territories').doc(event.params.territoryId);
    await ref.update({
      difficultyLevel: FieldValue.increment(1),
    });
  }
);

// =============================================================================
// 3. RESOLVER DESAFÍOS EXPIRADOS — se ejecuta cada hora automáticamente
// =============================================================================
exports.resolverDesafiosExpirados = onSchedule(
  { schedule: 'every 60 minutes', region: 'europe-west1' },
  async () => {
    const ahora = Timestamp.now();

    const snap = await db.collection('desafios')
      .where('estado', '==', 'activo')
      .where('fin', '<=', ahora)
      .get();

    if (snap.empty) {
      console.log('No hay desafíos expirados.');
      return;
    }

    console.log(`Resolviendo ${snap.docs.length} desafíos expirados...`);

    const promesas   = snap.docs.map(doc => _resolverDesafio(doc.id));
    const resultados = await Promise.allSettled(promesas);

    const ok      = resultados.filter(r => r.status === 'fulfilled').length;
    const errores = resultados.filter(r => r.status === 'rejected').length;
    console.log(`Resueltos: ${ok} | Errores: ${errores}`);
  }
);

// =============================================================================
// 4. TRIGGER — cuando un desafío pasa a 'activo', comprobar si ya expiró
// =============================================================================
exports.onDesafioActualizado = onDocumentUpdated(
  { document: 'desafios/{desafioId}', region: 'europe-west1' },
  async (event) => {
    const antes   = event.data.before.data();
    const despues = event.data.after.data();

    if (antes.estado !== 'pendiente' || despues.estado !== 'activo') return;

    const fin = despues.fin;
    if (fin && fin.toDate() <= new Date()) {
      console.log(`Desafío ${event.params.desafioId} expirado al activarse. Resolviendo...`);
      await _resolverDesafio(event.params.desafioId);
    }
  }
);

// =============================================================================
// 5. ACUMULAR PUNTOS — llamada desde Flutter al terminar una carrera
// =============================================================================
exports.acumularPuntosDesafio = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Usuario no autenticado.');
    }

    const uid = request.auth.uid;
    const { distanciaKm, territoriosConquistados } = request.data;

    if (typeof distanciaKm !== 'number' || distanciaKm < 0 || distanciaKm > 100) {
      throw new HttpsError('invalid-argument', 'distanciaKm inválida.');
    }
    if (typeof territoriosConquistados !== 'number' ||
        territoriosConquistados < 0 || territoriosConquistados > 200) {
      throw new HttpsError('invalid-argument', 'territoriosConquistados inválido.');
    }

    const puntos = Math.round(territoriosConquistados * 10 + distanciaKm * 5);
    if (puntos === 0) return { puntosAcumulados: 0, desafiosActualizados: 0 };

    const [snapRetador, snapRetado] = await Promise.all([
      db.collection('desafios')
        .where('retadorId', '==', uid)
        .where('estado', '==', 'activo')
        .get(),
      db.collection('desafios')
        .where('retadoId', '==', uid)
        .where('estado', '==', 'activo')
        .get(),
    ]);

    const docsMap = new Map();
    [...snapRetador.docs, ...snapRetado.docs].forEach(d => docsMap.set(d.id, d));
    const docs = Array.from(docsMap.values());

    if (docs.length === 0) return { puntosAcumulados: 0, desafiosActualizados: 0 };

    let desafiosActualizados = 0;

    await Promise.all(docs.map(async (doc) => {
      const data = doc.data();
      const fin  = data.fin;

      if (fin && fin.toDate() <= new Date()) {
        await _resolverDesafio(doc.id);
        return;
      }

      const campo = data.retadorId === uid ? 'puntosRetador' : 'puntosRetado';
      await db.collection('desafios').doc(doc.id).update({
        [campo]: FieldValue.increment(puntos),
      });
      desafiosActualizados++;
    }));

    return { puntosAcumulados: puntos, desafiosActualizados };
  }
);

// =============================================================================
// 6. CERRAR TEMPORADA — llamada desde panel de admin
// =============================================================================
exports.cerrarTemporada = onCall(
  { region: 'europe-west1', timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth || !request.auth.token.admin) {
      throw new HttpsError('permission-denied', 'Solo administradores.');
    }

    const { temporadaId } = request.data;
    if (!temporadaId) {
      throw new HttpsError('invalid-argument', 'temporadaId requerido.');
    }

    const temporadaDoc = await db.collection('temporadas').doc(temporadaId).get();
    if (!temporadaDoc.exists) {
      throw new HttpsError('not-found', 'Temporada no encontrada.');
    }
    const temporada = temporadaDoc.data();
    if (!temporada.activa) {
      throw new HttpsError('failed-precondition', 'La temporada ya está cerrada.');
    }

    const zonasSnap       = await db.collection('zonas').orderBy('nombre').get();
    const zonas           = zonasSnap.docs;
    const territoriosSnap = await db.collection('territories').get();

    const dominioMap = new Map();

    for (const terDoc of territoriosSnap.docs) {
      const t   = terDoc.data();
      const uid = t.userId;
      if (!uid || !t.puntos || t.puntos.length < 3) continue;

      const puntosLatLng = t.puntos.map(p => ({ lat: p.lat, lng: p.lng }));

      for (const zonaDoc of zonas) {
        const zona = zonaDoc.data();
        if (!zona.poligono || zona.poligono.length < 3) continue;

        const poligonoZona = zona.poligono.map(p => ({ lat: p.lat, lng: p.lng }));
        const area = _calcularAreaInterseccion(puntosLatLng, poligonoZona);
        if (area < 1) continue;

        if (!dominioMap.has(zonaDoc.id)) dominioMap.set(zonaDoc.id, new Map());
        const zonaMap = dominioMap.get(zonaDoc.id);
        zonaMap.set(uid, (zonaMap.get(uid) || 0) + area);
      }
    }

    let titulosOtorgados = 0;
    let batch = db.batch();
    let opsEnBatch = 0;

    const _commitBatchSiLleno = async () => {
      if (opsEnBatch >= 480) {
        await batch.commit();
        batch = db.batch();
        opsEnBatch = 0;
      }
    };

    const ganadorIds = new Set();
    for (const [, userMap] of dominioMap.entries()) {
      if (userMap.size === 0) continue;
      const [ganadorId] = [...userMap.entries()].reduce((a, b) => a[1] >= b[1] ? a : b);
      const areaDominada = userMap.get(ganadorId);
      if (areaDominada >= 100) ganadorIds.add(ganadorId);
    }

    const playerDocs = await Promise.all(
      [...ganadorIds].map(id => db.collection('players').doc(id).get())
    );
    const playerMap = new Map(playerDocs.map(d => [d.id, d.data()]));

    for (const zonaDoc of zonas) {
      const zona    = zonaDoc.data();
      const userMap = dominioMap.get(zonaDoc.id);
      if (!userMap || userMap.size === 0) continue;

      const [ganadorId, areaDominada] = [...userMap.entries()]
        .reduce((a, b) => a[1] >= b[1] ? a : b);

      if (areaDominada < 100) continue;

      const playerData = playerMap.get(ganadorId);
      if (!playerData) continue;

      const nick    = playerData.nickname || 'Runner';
      const monedas = temporada.monedas_base || 500;

      const tituloRef = db.collection('titulos_rey').doc();
      batch.set(tituloRef, {
        userId             : ganadorId,
        userNick           : nick,
        zonaId             : zonaDoc.id,
        zonaNombre         : zona.nombre,
        zonaNombreCorto    : zona.nombre_corto || null,
        temporada          : temporada.numero,
        areaM2             : areaDominada,
        monedasRecompensa  : monedas,
        coronaDesbloqueada : true,
        fechaOtorgado      : FieldValue.serverTimestamp(),
      });
      opsEnBatch++;

      batch.update(db.collection('zonas').doc(zonaDoc.id), {
        rey_actual_id    : ganadorId,
        rey_actual_nick  : nick,
        temporada_actual : temporada.numero,
      });
      opsEnBatch++;

      batch.update(db.collection('players').doc(ganadorId), {
        monedas                       : FieldValue.increment(monedas),
        'avatar_config.coronaDesbloqueada': true,
      });
      opsEnBatch++;

      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        toUserId          : ganadorId,
        type              : 'titulo_rey',
        zonaId            : zonaDoc.id,
        zonaNombre        : zona.nombre_corto || zona.nombre,
        temporada         : temporada.numero,
        monedasRecompensa : monedas,
        message           : `👑 ¡Eres el Rey de ${zona.nombre_corto || zona.nombre} en la T${temporada.numero}! +${monedas} 🪙`,
        read              : false,
        timestamp         : FieldValue.serverTimestamp(),
      });
      opsEnBatch++;

      titulosOtorgados++;
      await _commitBatchSiLleno();
    }

    batch.update(db.collection('temporadas').doc(temporadaId), {
      activa       : false,
      fecha_cierre : FieldValue.serverTimestamp(),
    });

    await batch.commit();

    console.log(`Temporada ${temporadaId} cerrada. Títulos: ${titulosOtorgados}`);
    return { titulosOtorgados };
  }
);

// =============================================================================
// 7. CONQUISTAR TERRITORIO — llamada desde Flutter
// =============================================================================
exports.conquistarTerritorio = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
  }

  const uid = request.auth.uid;
  const { docId, latUsuario, lngUsuario } = request.data;

  if (!docId || typeof docId !== 'string') {
    throw new HttpsError('invalid-argument', 'docId inválido.');
  }
  if (typeof latUsuario !== 'number' || typeof lngUsuario !== 'number') {
    throw new HttpsError('invalid-argument', 'Coordenadas inválidas.');
  }

  const territorioRef = db.collection('territories').doc(docId);
  const playerRef     = db.collection('players').doc(uid);

  try {
    const resultado = await db.runTransaction(async (tx) => {
      const [territorioSnap, playerSnap] = await Promise.all([
        tx.get(territorioRef),
        tx.get(playerRef),
      ]);

      if (!territorioSnap.exists) {
        throw new HttpsError('not-found', 'El territorio no existe.');
      }

      const t         = territorioSnap.data();
      const duenoId   = t.userId;
      const nuevoNick = playerSnap.exists ? (playerSnap.data().nickname ?? 'Alguien') : 'Alguien';

      if (duenoId === uid) {
        tx.update(territorioRef, {
          ultima_visita:         FieldValue.serverTimestamp(),
          hp:                    100,
          ultimaActualizacionHp: FieldValue.serverTimestamp(),
        });
        return { accion: 'visita' };
      }

      const ultimaVisita  = t.ultima_visita ? t.ultima_visita.toMillis() : 0;
      const diasSinVisita = (Date.now() - ultimaVisita) / (1000 * 60 * 60 * 24);

      if (diasSinVisita < 10) {
        throw new HttpsError(
          'failed-precondition',
          `El territorio solo lleva ${Math.floor(diasSinVisita)} días sin visita. Necesita 10.`
        );
      }

      const latC       = t.centroLat ?? (t.centro?.lat ?? 0);
      const lngC       = t.centroLng ?? (t.centro?.lng ?? 0);
      const distanciaM = _haversineMetros(latUsuario, lngUsuario, latC, lngC);

      if (distanciaM > 200) {
        throw new HttpsError(
          'failed-precondition',
          `Debes estar a menos de 200 m del territorio (estás a ${Math.round(distanciaM)} m).`
        );
      }

      const reyAnteriorId   = t.rey_id      ?? null;
      const reyAnteriorNick = t.rey_nickname ?? null;

      tx.update(territorioRef, {
        userId            : uid,
        nickname          : nuevoNick,
        ultima_visita     : FieldValue.serverTimestamp(),
        conquistado_por   : uid,
        fecha_conquista   : FieldValue.serverTimestamp(),
        fecha_desde_dueno : FieldValue.serverTimestamp(),
        rey_id            : null,
        rey_nickname      : null,
        rey_desde         : null,
        hp                : 100,
        hpMax             : 100,
        ultimaActualizacionHp: FieldValue.serverTimestamp(),
      });

      return {
        accion          : 'conquista',
        duenoAnteriorId : duenoId,
        reyAnteriorId,
        reyAnteriorNick,
        nuevoNick,
        clanId: playerSnap.exists ? (playerSnap.data().clanId ?? null) : null,
      };
    });

    if (resultado.accion === 'conquista') {
      const batch = db.batch();

      batch.set(db.collection('notifications').doc(), {
        toUserId  : resultado.duenoAnteriorId,
        type      : 'territory_lost',
        message   : `⚔️ ${resultado.nuevoNick} ha conquistado uno de tus territorios.`,
        read      : false,
        timestamp : FieldValue.serverTimestamp(),
      });

      if (resultado.reyAnteriorId && resultado.reyAnteriorId !== '') {
        batch.set(db.collection('notifications').doc(), {
          toUserId  : resultado.reyAnteriorId,
          type      : 'territory_king_lost',
          message   : `👑💀 ${resultado.nuevoNick} te ha arrebatado el reinado. Ya no eres Rey de ese territorio.`,
          read      : false,
          timestamp : FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (resultado.clanId) {
        try {
          await db.collection('clans').doc(resultado.clanId).update({
            puntos: FieldValue.increment(25),
          });
        } catch (e) {
          console.error('Error sumando puntos al clan:', e);
        }
      }
    }

    return { ok: true, accion: resultado.accion };

  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error('conquistarTerritorio error:', e);
    throw new HttpsError('internal', 'Error interno al conquistar territorio.');
  }
});

// =============================================================================
// 8. RENOMBRAR TERRITORIO — llamada desde Flutter
// =============================================================================
exports.renombrarTerritorio = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
  }

  const uid = request.auth.uid;
  const { docId, nombre } = request.data;

  if (!docId || typeof docId !== 'string') {
    throw new HttpsError('invalid-argument', 'docId inválido.');
  }
  if (typeof nombre !== 'string') {
    throw new HttpsError('invalid-argument', 'El nombre debe ser texto.');
  }

  const nombreLimpio = nombre.trim();

  if (nombreLimpio.length === 0) {
    throw new HttpsError('invalid-argument', 'El nombre no puede estar vacío.');
  }
  if (nombreLimpio.length > 30) {
    throw new HttpsError('invalid-argument', 'El nombre no puede superar los 30 caracteres.');
  }

  const formatoValido = /^[\p{L}\p{N} \-'.,!?áéíóúàèìòùäëïöüñçÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÑÇ]+$/u;
  if (!formatoValido.test(nombreLimpio)) {
    throw new HttpsError('invalid-argument', 'El nombre contiene caracteres no permitidos.');
  }

  const _normalizar = (s) => s.toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '');

  const LISTA_NEGRA = [
    'puta','puto','polla','coño','joder','hostia','mierda','gilipollas',
    'capullo','imbecil','idiota','subnormal','maricón','maricon','zorra',
    'pendejo','culero','cabron','cabrón','hijo de puta','hdp',
    'fuck','shit','bitch','asshole','cunt','dick','cock','pussy',
    'nazi','hitler','kkk','isis','terrorista','violacion','violación',
    'pedo','pedofil','pedofilo',
  ];

  const nombreNorm      = _normalizar(nombreLimpio);
  const palabraProhibida = LISTA_NEGRA.find(p => nombreNorm.includes(_normalizar(p)));
  if (palabraProhibida) {
    throw new HttpsError('invalid-argument', 'El nombre contiene contenido no permitido.');
  }

  const territorioRef  = db.collection('territories').doc(docId);
  const territorioSnap = await territorioRef.get();

  if (!territorioSnap.exists) {
    throw new HttpsError('not-found', 'El territorio no existe.');
  }
  if (territorioSnap.data().userId !== uid) {
    throw new HttpsError('permission-denied', 'Solo el dueño puede renombrar su territorio.');
  }

  await territorioRef.update({ nombre_territorio: nombreLimpio });

  return { ok: true, nombre: nombreLimpio };
});

// =============================================================================
// 9. CONQUISTAR TERRITORIO GLOBAL — llamada desde Flutter
// Sistema: cláusula escalante (km corridos × 1.15)
// =============================================================================
exports.conquistarTerritorioGlobal = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
    }

    const uid = request.auth.uid;
    const { territorioId, activityLogId, ownerColor: ownerColorReq, kmCorridosEnSesion } = request.data;

    if (!territorioId || typeof territorioId !== 'string') {
      throw new HttpsError('invalid-argument', 'territorioId inválido.');
    }
    if (!activityLogId || typeof activityLogId !== 'string') {
      throw new HttpsError('invalid-argument', 'activityLogId inválido.');
    }

    const [territorioSnap, logSnap] = await Promise.all([
      db.collection('global_territories').doc(territorioId).get(),
      db.collection('activity_logs').doc(activityLogId).get(),
    ]);

    if (!territorioSnap.exists) {
      throw new HttpsError('not-found', 'El territorio global no existe.');
    }
    if (!logSnap.exists) {
      throw new HttpsError('not-found', 'Log de actividad no encontrado.');
    }

    const log = logSnap.data();

    // ── Anti-cheat: validaciones del log ──────────────────────────────────
    if (log.userId !== uid) {
      throw new HttpsError('permission-denied', 'Este log no te pertenece.');
    }
    const logTimestamp = log.timestamp?.toMillis() ?? 0;
    if (Date.now() - logTimestamp > 2 * 60 * 60 * 1000) {
      throw new HttpsError('failed-precondition', 'El log ha expirado (>2h).');
    }
    if (log.usado_conquista_global === true) {
      throw new HttpsError('failed-precondition', 'Este log ya fue usado para una conquista.');
    }

    // ── Km: fuente autoritativa = log del servidor ────────────────────────
    const kmRecorridos = log.distancia ?? 0;

    const territorio   = territorioSnap.data();
    // clausulaKm es el mínimo a superar; si nunca fue conquistado, usa baseKm
    const clausulaActual = territorio.clausulaKm ?? territorio.baseKm ?? 5;

    if (kmRecorridos < clausulaActual) {
      throw new HttpsError(
        'failed-precondition',
        `Necesitas al menos ${clausulaActual.toFixed(2)} km. Has corrido ${kmRecorridos.toFixed(2)} km.`
      );
    }

    if (territorio.ownerUid === uid) {
      throw new HttpsError('failed-precondition', 'Ya eres el dueño de este territorio.');
    }

    const miosSnap = await db.collection('global_territories')
      .where('ownerUid', '==', uid).count().get();
    if ((miosSnap.data().count ?? 0) >= 5) {
      throw new HttpsError('failed-precondition', 'Ya controlas 5 territorios globales (máximo).');
    }

    const playerSnap = await db.collection('players').doc(uid).get();
    if (!playerSnap.exists) throw new HttpsError('not-found', 'Jugador no encontrado.');

    const player        = playerSnap.data();
    const ownerNickname = player.nickname ?? 'Guerrero';
    const ownerColor    = player.territorio_color ?? ownerColorReq ?? null;
    const anteriorDueno = territorio.ownerUid ?? null;

    // Nueva cláusula = km corridos × 1.15 (el conquistador decide lo difícil que lo pone)
    const nuevaClausula = kmRecorridos * 1.15;
    const nuevoCount    = (territorio.conquestCount ?? 0) + 1;

    await db.runTransaction(async (tx) => {
      const terRef   = db.collection('global_territories').doc(territorioId);
      const logRef   = db.collection('activity_logs').doc(activityLogId);
      const terSnap2 = await tx.get(terRef);

      if (!terSnap2.exists) throw new HttpsError('not-found', 'Territorio desapareció.');
      if (terSnap2.data().ownerUid === uid) throw new HttpsError('failed-precondition', 'Ya eres el dueño.');

      tx.update(terRef, {
        ownerUid:          uid,
        ownerNickname:     ownerNickname,
        ownerColor:        ownerColor,
        libre:             false,
        clausulaKm:        nuevaClausula,
        conquestCount:     nuevoCount,
        kmUltimaConquista: kmRecorridos,
        conquistadoEn:     FieldValue.serverTimestamp(),
      });
      tx.update(logRef, {
        usado_conquista_global: true,
        territorio_conquistado: territorioId,
      });
    });

    // ── Notificaciones ────────────────────────────────────────────────────
    const notifBatch = db.batch();
    notifBatch.set(db.collection('notifications').doc(), {
      toUserId  : uid,
      type      : 'global_territory_conquered',
      message   : `⚔️ ¡Conquistaste "${territorio.epicName ?? territorio.nombre}"! ` +
                  `Tu cláusula: ${nuevaClausula.toFixed(1)} km. Defiéndelo hasta el lunes.`,
      read      : false,
      timestamp : FieldValue.serverTimestamp(),
    });
    if (anteriorDueno && anteriorDueno !== uid) {
      notifBatch.set(db.collection('notifications').doc(), {
        toUserId  : anteriorDueno,
        type      : 'global_territory_lost',
        message   : `💀 ${ownerNickname} te ha arrebatado ` +
                    `"${territorio.epicName ?? territorio.nombre}" corriendo ${kmRecorridos.toFixed(1)} km.`,
        read      : false,
        timestamp : FieldValue.serverTimestamp(),
      });
    }
    await notifBatch.commit();

    // Los puntos de liga NO se otorgan al conquistar — solo el lunes (liquidarGuerraGlobal)
    console.log(
      `[conquistarTerritorioGlobal] ${ownerNickname} (${uid}) conquistó ` +
      `"${territorioId}" con ${kmRecorridos.toFixed(1)} km. Nueva cláusula: ${nuevaClausula.toFixed(1)} km.`
    );

    return {
      ok:               true,
      territorioNombre: territorio.epicName ?? territorio.nombre,
      nuevaClausula,
      conquestCount:    nuevoCount,
      kmCorridosEnSesion: kmRecorridos,
    };
  }
);

// =============================================================================
// 10. AJUSTAR TERRITORIOS ACTIVOS — se ejecuta cada día a las 00:00 UTC
// =============================================================================
exports.ajustarTerritoriosActivos = onSchedule(
  {
    schedule : 'every day 00:00',
    timeZone : 'UTC',
    memory   : '256MiB',
    region   : 'europe-west1',
  },
  async () => {
    console.log('[ajustarTerritoriosActivos] Iniciando recalculo diario...');

    const col  = db.collection('global_territories');
    const snap = await col.get();

    if (snap.empty) {
      console.log('Pool vacío. Ejecuta el script seed primero.');
      return;
    }

    const todos           = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    const conquistados    = todos.filter(t => t.ownerUid != null);
    const activosLibres   = todos.filter(t => t.activo && t.ownerUid == null);
    const inactivosLibres = todos.filter(t => !t.activo && t.ownerUid == null);

    const numConquistados  = conquistados.length;
    const objetivo         = Math.max(10, numConquistados * 2);
    const numActivosLibres = activosLibres.length;
    const diferencia       = objetivo - numActivosLibres;

    console.log(`  Conquistados:    ${numConquistados}`);
    console.log(`  Libres activos:  ${numActivosLibres}`);
    console.log(`  Objetivo libres: ${objetivo}`);
    console.log(`  Diferencia:      ${diferencia}`);

    const batch = db.batch();
    let cambios = 0;

    if (diferencia > 0) {
      const disponibles = _shuffle([...inactivosLibres]);
      const aActivar    = disponibles.slice(0, diferencia);

      for (const t of aActivar) {
        batch.update(col.doc(t.id), { activo: true });
        console.log(`  ACTIVAR  ${t.id} — ${t.epicName}`);
        cambios++;
      }

      if (aActivar.length < diferencia) {
        console.warn(
          `  ⚠ Pool insuficiente: necesitábamos ${diferencia} pero solo había ${aActivar.length} inactivos libres.`
        );
      }

    } else if (diferencia < 0) {
      const aDesactivar = _shuffle([...activosLibres]).slice(0, Math.abs(diferencia));

      for (const t of aDesactivar) {
        batch.update(col.doc(t.id), { activo: false });
        console.log(`  DESACTIVAR  ${t.id} — ${t.epicName}`);
        cambios++;
      }
    } else {
      console.log('  Número de territorios ya correcto. Sin cambios.');
    }

    if (cambios > 0) {
      await batch.commit();
      console.log(`[ajustarTerritoriosActivos] ${cambios} cambios aplicados.`);
    }

    await db.collection('guerra_global_logs').add({
      tipo:           'recalculo_diario',
      fecha:          Timestamp.now(),
      conquistados:   numConquistados,
      libresAntes:    numActivosLibres,
      objetivoLibres: objetivo,
      cambios,
    });

    console.log('[ajustarTerritoriosActivos] Finalizado.');
  }
);

// =============================================================================
// 11. ACTIVAR PRIMERA VEZ — callable para lanzar el primer lote manualmente
// =============================================================================
exports.activarTerritoriosIniciales = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth?.token?.admin) {
      throw new HttpsError('permission-denied', 'Solo administradores.');
    }

    const col  = db.collection('global_territories');
    const snap = await col.get();

    const activos = snap.docs.filter(d => d.data().activo);
    if (activos.length > 0) {
      return { ok: false, mensaje: `Ya hay ${activos.length} territorios activos.` };
    }

    const todos    = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    const libres   = _shuffle(todos.filter(t => !t.ownerUid));
    const aActivar = libres.slice(0, 10);

    const batch = db.batch();
    for (const t of aActivar) {
      batch.update(col.doc(t.id), { activo: true });
    }
    await batch.commit();

    return { ok: true, activados: aActivar.length };
  }
);

// =============================================================================
// 12. ATACAR TERRITORIO — sistema de HP v7
// =============================================================================
exports.atacarTerritorio = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
    }

    const atacanteId = request.auth.uid;
    const { territorioDefensorId, rutaAtacante, velocidadMediaAtacanteKmh } = request.data;

    if (!territorioDefensorId || !rutaAtacante || rutaAtacante.length < 3) {
      throw new HttpsError('invalid-argument', 'Parámetros insuficientes.');
    }
    if (typeof velocidadMediaAtacanteKmh !== 'number' || velocidadMediaAtacanteKmh <= 0) {
      throw new HttpsError('invalid-argument', 'Velocidad inválida.');
    }

    const terRef  = db.collection('territories').doc(territorioDefensorId);
    const terSnap = await terRef.get();

    if (!terSnap.exists) {
      throw new HttpsError('not-found', 'Territorio no encontrado.');
    }

    const terData = terSnap.data();

    if (terData.userId === atacanteId) {
      throw new HttpsError('failed-precondition', 'No puedes atacar tu propio territorio.');
    }

    // Escudo activo
    if (terData.escudo_activo === true && terData.escudo_expira) {
      const expira = terData.escudo_expira.toDate();
      if (expira > new Date()) {
        const hpActualEscudo = _hpActual(terData);
        return {
          ok: false, accion: 'sin_daño',
          mensaje: 'Este territorio está blindado. No puedes atacarlo.',
          hpAntes: hpActualEscudo, hpDespues: hpActualEscudo,
          danio: 0, monedasBotin: 0,
        };
      }
    }

    const hpActual       = _hpActual(terData);
    const poliAtacante   = rutaAtacante.map(p => ({ x: p.lng, y: p.lat }));
    const poliDefensor   = (terData.puntos || []).map(p => ({ x: p.lng, y: p.lat }));
    const areaAtacanteM2 = _calcularAreaM2(poliAtacante);

    if (areaAtacanteM2 < 500) {
      return {
        ok: false, accion: 'sin_daño',
        mensaje: 'Tu zona es demasiado pequeña.',
        hpAntes: hpActual, hpDespues: hpActual,
        danio: 0, monedasBotin: 0,
      };
    }

    const interseccion       = _sutherlandHodgman(poliAtacante, poliDefensor);
    const areaInterseccionM2 = interseccion.length >= 3
      ? _calcularAreaM2(interseccion) : 0;

    if (areaInterseccionM2 < 1) {
      return {
        ok: false, accion: 'sin_daño',
        mensaje: 'Tu ruta no solapa con este territorio.',
        hpAntes: hpActual, hpDespues: hpActual,
        danio: 0, monedasBotin: 0,
      };
    }

    const velocidadDefensorKmh = terData.velocidadConquistaKmh || 5.0;
    const factorVelocidad      = velocidadMediaAtacanteKmh / velocidadDefensorKmh;

    if (factorVelocidad < 1.0) {
      return {
        ok: false, accion: 'sin_daño',
        mensaje: `Necesitas correr más rápido. El defensor fue a ${velocidadDefensorKmh.toFixed(1)} km/h.`,
        hpAntes: hpActual, hpDespues: hpActual,
        danio: 0, monedasBotin: 0,
      };
    }

    const areaDefensorM2 = _calcularAreaM2(poliDefensor);
    const porcentajeArea = Math.min(areaInterseccionM2 / areaDefensorM2, 1.0);
    const danioBase      = factorVelocidad * porcentajeArea * hpActual * 0.8;
    const danio          = Math.min(Math.round(danioBase), hpActual);
    const hpNuevo        = Math.max(hpActual - danio, 0);
    const monedasBotin   = Math.round(danio * 0.5 + areaInterseccionM2 * 0.1);

    const atacanteSnap  = await db.collection('players').doc(atacanteId).get();
    const atacanteData  = atacanteSnap.exists ? atacanteSnap.data() : {};
    const atacanteNick  = atacanteData.nickname || 'Alguien';
    const atacanteColor = atacanteData.territorio_color || null;

    // ── CASO A: CONQUISTA TOTAL ───────────────────────────────────────────
    if (hpNuevo === 0 && porcentajeArea >= 0.95) {
      const defensorId   = terData.userId;
      const defensorNick = terData.nickname || 'Alguien';
      const batch        = db.batch();

      batch.update(terRef, {
        userId:                  atacanteId,
        nickname:                atacanteNick,
        color:                   atacanteColor,
        hp:                      100,
        hpMax:                   100,
        velocidadConquistaKmh:   velocidadMediaAtacanteKmh,
        ultimaActualizacionHp:   FieldValue.serverTimestamp(),
        ultima_visita:           FieldValue.serverTimestamp(),
        fecha_desde_dueno:       FieldValue.serverTimestamp(),
        rey_id:                  null,
        rey_nickname:            null,
        rey_desde:               null,
      });

      batch.update(db.collection('players').doc(atacanteId), {
        monedas: FieldValue.increment(monedasBotin),
      });

      batch.set(db.collection('notifications').doc(), {
        toUserId:    defensorId,
        type:        'territory_lost',
        message:     `😤 ¡${atacanteNick} ha conquistado uno de tus territorios!`,
        fromNickname: atacanteNick,
        territoryId: terRef.id,
        read:        false,
        timestamp:   FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Puntos de liga
      await Promise.all([
        db.collection('players').doc(atacanteId).update({
          puntos_liga: FieldValue.increment(25),
        }),
        db.collection('players').doc(defensorId).update({
          puntos_liga: FieldValue.increment(-10),
        }),
      ]);

      return {
        ok: true, accion: 'conquista_total',
        hpAntes: hpActual, hpDespues: 100,
        danio, monedasBotin,
        mensaje: `¡Has conquistado el territorio de ${defensorNick}!`,
        territorioRobadoId: terRef.id,
      };
    }

    // ── CASO B: ROBO PARCIAL ─────────────────────────────────────────────
    if (hpNuevo === 0 && porcentajeArea < 0.95) {
      const defensorId   = terData.userId;
      const defensorNick = terData.nickname || 'Alguien';
      const batch        = db.batch();

      const puntosRestantes = poliDefensor.filter(
        p => !_puntoEnPoligono(p, poliAtacante)
      );

      if (puntosRestantes.length >= 3) {
        const centroRestante = _centroide(puntosRestantes);
        batch.update(terRef, {
          puntos:                puntosRestantes.map(p => ({ lat: p.y, lng: p.x })),
          centro:                { lat: centroRestante.y, lng: centroRestante.x },
          centroLat:             centroRestante.y,
          centroLng:             centroRestante.x,
          hp:                    hpActual,
          hpMax:                 100,
          ultimaActualizacionHp: FieldValue.serverTimestamp(),
        });
      } else {
        batch.delete(terRef);
      }

      const centroInterseccion = _centroide(interseccion);
      const nuevoTerRef        = db.collection('territories').doc();

      batch.set(nuevoTerRef, {
        userId:                  atacanteId,
        nickname:                atacanteNick,
        color:                   atacanteColor,
        puntos:                  interseccion.map(p => ({ lat: p.y, lng: p.x })),
        centro:                  { lat: centroInterseccion.y, lng: centroInterseccion.x },
        centroLat:               centroInterseccion.y,
        centroLng:               centroInterseccion.x,
        hp:                      100,
        hpMax:                   100,
        velocidadConquistaKmh:   velocidadMediaAtacanteKmh,
        ultimaActualizacionHp:   FieldValue.serverTimestamp(),
        ultima_visita:           FieldValue.serverTimestamp(),
        fecha_desde_dueno:       FieldValue.serverTimestamp(),
        modo:                    'competitivo',
        area_m2:                 areaInterseccionM2,
        rey_id:                  null,
        rey_nickname:            null,
        rey_desde:               null,
        nombre_territorio:       null,
      });

      batch.update(db.collection('players').doc(atacanteId), {
        monedas: FieldValue.increment(monedasBotin),
      });

      batch.set(db.collection('notifications').doc(), {
        toUserId:    defensorId,
        type:        'territory_bitten',
        message:     `⚔️ ¡${atacanteNick} te ha robado un trozo de territorio!`,
        fromNickname: atacanteNick,
        territoryId: terRef.id,
        read:        false,
        timestamp:   FieldValue.serverTimestamp(),
      });

      await batch.commit();

      return {
        ok: true, accion: 'robo_parcial',
        hpAntes: hpActual, hpDespues: 0,
        danio, monedasBotin,
        mensaje: `¡Has robado un trozo del territorio de ${defensorNick}!`,
        territorioRobadoId: nuevoTerRef.id,
      };
    }

    // ── CASO C: DAÑO PARCIAL ─────────────────────────────────────────────
    const defensorId = terData.userId;
    const batch      = db.batch();

    batch.update(terRef, {
      hp:                    hpNuevo,
      ultimaActualizacionHp: FieldValue.serverTimestamp(),
    });

    if (monedasBotin > 0) {
      batch.update(db.collection('players').doc(atacanteId), {
        monedas: FieldValue.increment(monedasBotin),
      });
    }

    if (hpNuevo <= 30 && hpActual > 30) {
      batch.set(db.collection('notifications').doc(), {
        toUserId:    defensorId,
        type:        'territory_under_attack',
        message:     `🔥 ¡${atacanteNick} está asediando tu territorio! HP crítico: ${hpNuevo}%`,
        fromNickname: atacanteNick,
        territoryId: terRef.id,
        read:        false,
        timestamp:   FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return {
      ok: true, accion: 'daño',
      hpAntes: hpActual, hpDespues: hpNuevo,
      danio, monedasBotin,
      mensaje: `Daño causado: ${danio} HP. El territorio tiene ${hpNuevo}% de salud.`,
    };
  }
);

// =============================================================================
// 13. ACTUALIZAR HP DE TODOS LOS TERRITORIOS — cada 6 horas
// =============================================================================
exports.actualizarHpTodosLosTerritorios = onSchedule(
  {
    schedule : 'every 6 hours',
    timeZone : 'UTC',
    memory   : '256MiB',
    region   : 'europe-west1',
  },
  async () => {
    const ahora    = new Date();
    const snap     = await db.collection('territories').get();
    const batch    = db.batch();
    let   contador = 0;

    for (const doc of snap.docs) {
      const data     = doc.data();
      const hpActual = _hpActual(data);
      if (hpActual <= 0) continue;

      const ultimaActualizacion = data.ultimaActualizacionHp
        ? data.ultimaActualizacionHp.toDate()
        : (data.ultima_visita ? data.ultima_visita.toDate() : ahora);

      const horasTranscurridas = (ahora - ultimaActualizacion) / (1000 * 60 * 60);
      const decayPorHora       = (100 / 7) / 24;
      const nuevoHp            = Math.max(
        Math.round(hpActual - decayPorHora * horasTranscurridas), 0
      );

      if (nuevoHp !== hpActual) {
        batch.update(doc.ref, {
          hp:                    nuevoHp,
          ultimaActualizacionHp: FieldValue.serverTimestamp(),
        });
        contador++;
      }
    }

    await batch.commit();
    console.log(`[actualizarHpTodosLosTerritorios] HP actualizado en ${contador} territorios.`);
  }
);

// =============================================================================
// 12. ACTIVAR ESCUDO — paga monedas, protege el territorio X horas
// =============================================================================
exports.activarEscudo = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
    }
    const uid = request.auth.uid;
    const { territorioId, horas } = request.data;

    if (!territorioId || typeof territorioId !== 'string') {
      throw new HttpsError('invalid-argument', 'territorioId inválido.');
    }
    const PRECIOS = { 24: 50, 48: 90, 72: 120 };
    if (!PRECIOS[horas]) {
      throw new HttpsError('invalid-argument', 'horas debe ser 24, 48 o 72.');
    }
    const precio = PRECIOS[horas];

    const terRef    = db.collection('territories').doc(territorioId);
    const playerRef = db.collection('players').doc(uid);

    await db.runTransaction(async (tx) => {
      const [terSnap, playerSnap] = await Promise.all([
        tx.get(terRef), tx.get(playerRef),
      ]);

      if (!terSnap.exists) {
        throw new HttpsError('not-found', 'Territorio no encontrado.');
      }
      if (terSnap.data().userId !== uid) {
        throw new HttpsError('permission-denied', 'Este territorio no es tuyo.');
      }
      const monedas = playerSnap.data()?.monedas ?? 0;
      if (monedas < precio) {
        throw new HttpsError(
          'failed-precondition',
          `Necesitas ${precio} monedas. Tienes ${monedas}.`
        );
      }

      const expira = new Date(Date.now() + horas * 3600 * 1000);
      tx.update(terRef, {
        escudo_activo: true,
        escudo_expira: Timestamp.fromDate(expira),
      });
      tx.update(playerRef, {
        monedas: FieldValue.increment(-precio),
      });
    });

    const expiraFinal = new Date(Date.now() + horas * 3600 * 1000);
    return {
      ok:           true,
      escudoExpira: expiraFinal.getTime(),
      horas,
      precio,
    };
  }
);

// =============================================================================
// HELPERS PRIVADOS
// =============================================================================

function _hpActual(terData) {
  const HP_MAX         = 100;
  const HP_DECAY_DIA   = 100 / 7;

  if (terData.hp === undefined || terData.hp === null) {
    const ultimaVisita = terData.ultima_visita
      ? terData.ultima_visita.toDate() : new Date();
    const dias = (new Date() - ultimaVisita) / (1000 * 60 * 60 * 24);
    return Math.max(Math.round(HP_MAX - dias * HP_DECAY_DIA), 0);
  }

  const ultimaActualizacion = terData.ultimaActualizacionHp
    ? terData.ultimaActualizacionHp.toDate() : new Date();
  const horasTranscurridas  = (new Date() - ultimaActualizacion) / (1000 * 60 * 60);
  const decayPorHora        = HP_DECAY_DIA / 24;
  return Math.max(Math.round(terData.hp - decayPorHora * horasTranscurridas), 0);
}

function _sutherlandHodgman(subjectPoly, clipPoly) {
  if (!subjectPoly.length || !clipPoly.length) return [];
  let output = [...subjectPoly];
  for (let i = 0; i < clipPoly.length; i++) {
    if (!output.length) return [];
    const input  = [...output];
    output       = [];
    const edgeA  = clipPoly[i];
    const edgeB  = clipPoly[(i + 1) % clipPoly.length];
    for (let j = 0; j < input.length; j++) {
      const current  = input[j];
      const previous = input[(j + input.length - 1) % input.length];
      const currentInside  = _ladoIzquierdo(edgeA, edgeB, current);
      const previousInside = _ladoIzquierdo(edgeA, edgeB, previous);
      if (currentInside) {
        if (!previousInside) output.push(_interseccionLineas(previous, current, edgeA, edgeB));
        output.push(current);
      } else if (previousInside) {
        output.push(_interseccionLineas(previous, current, edgeA, edgeB));
      }
    }
  }
  return output;
}

function _ladoIzquierdo(a, b, p) {
  return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0;
}

function _interseccionLineas(p1, p2, p3, p4) {
  const denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x);
  if (Math.abs(denom) < 1e-10) return p1;
  const t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom;
  return { x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y) };
}

function _calcularAreaM2(poligono) {
  if (poligono.length < 3) return 0;
  const latRef = poligono.reduce((s, p) => s + p.y, 0) / poligono.length;
  const cosLat = Math.cos(latRef * Math.PI / 180);
  let area = 0;
  const n  = poligono.length;
  for (let i = 0; i < n; i++) {
    const j  = (i + 1) % n;
    const xi = poligono[i].x * 111320 * cosLat;
    const yi = poligono[i].y * 111320;
    const xj = poligono[j].x * 111320 * cosLat;
    const yj = poligono[j].y * 111320;
    area += xi * yj - xj * yi;
  }
  return Math.abs(area / 2);
}

function _centroide(poligono) {
  const n = poligono.length;
  return {
    x: poligono.reduce((s, p) => s + p.x, 0) / n,
    y: poligono.reduce((s, p) => s + p.y, 0) / n,
  };
}

function _puntoEnPoligono(punto, poligono) {
  let intersecciones = 0;
  const n = poligono.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = poligono[i].x, yi = poligono[i].y;
    const xj = poligono[j].x, yj = poligono[j].y;
    const cruza =
      ((yi > punto.y) !== (yj > punto.y)) &&
      (punto.x < (xj - xi) * (punto.y - yi) / (yj - yi) + xi);
    if (cruza) intersecciones++;
  }
  return intersecciones % 2 === 1;
}

async function _resolverDesafio(desafioId) {
  return db.runTransaction(async (tx) => {
    const ref  = db.collection('desafios').doc(desafioId);
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const data   = snap.data();
    const estado = data.estado;
    if (estado !== 'activo') return;
    const pRetador = data.puntosRetador || 0;
    const pRetado  = data.puntosRetado  || 0;
    const ganadorId    = pRetador > pRetado ? data.retadorId   : data.retadoId;
    const perdedorId   = pRetador > pRetado ? data.retadoId    : data.retadorId;
    const ganadorNick  = pRetador > pRetado ? data.retadorNick : data.retadoNick;
    const perdedorNick = pRetador > pRetado ? data.retadoNick  : data.retadorNick;
    const premio       = (data.apuesta || 0) * 2;
    tx.update(ref, {
      estado     : 'finalizado',
      ganadorId,
      resolvedAt : FieldValue.serverTimestamp(),
    });
    if (premio > 0) {
      tx.update(db.collection('players').doc(ganadorId), {
        monedas: FieldValue.increment(premio),
      });
    }
    setImmediate(() => _enviarNotificacionesDesafio({
      desafioId, ganadorId, perdedorId,
      ganadorNick, perdedorNick, premio,
    }));
  });
}

async function _enviarNotificacionesDesafio({
  desafioId, ganadorId, perdedorId,
  ganadorNick, perdedorNick, premio,
}) {
  try {
    await Promise.all([
      db.collection('notifications').add({
        toUserId     : ganadorId,
        type         : 'desafio_ganado',
        fromNickname : perdedorNick,
        desafioId,
        message      : `🏆 ¡Ganaste el desafío contra ${perdedorNick}! +${premio} 🪙`,
        read         : false,
        timestamp    : FieldValue.serverTimestamp(),
      }),
      db.collection('notifications').add({
        toUserId     : perdedorId,
        type         : 'desafio_perdido',
        fromNickname : ganadorNick,
        desafioId,
        message      : `💀 Perdiste el desafío contra ${ganadorNick}. Él se lleva ${premio} 🪙`,
        read         : false,
        timestamp    : FieldValue.serverTimestamp(),
      }),
    ]);
  } catch (e) {
    console.error('Error enviando notificaciones de desafío:', e);
  }
}

function _haversineMetros(lat1, lng1, lat2, lng2) {
  const R    = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a    =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function _calcularAreaInterseccion(subject, clip) {
  const interseccion = _sutherlandHodgmanLatLng(subject, clip);
  if (interseccion.length < 3) return 0;
  return _areaPoligonoMetros(interseccion);
}

function _sutherlandHodgmanLatLng(subject, clip) {
  let output = [...subject];
  if (output.length === 0) return [];
  for (let i = 0; i < clip.length; i++) {
    if (output.length === 0) return [];
    const input     = [...output];
    output          = [];
    const edgeStart = clip[i];
    const edgeEnd   = clip[(i + 1) % clip.length];
    for (let j = 0; j < input.length; j++) {
      const current  = input[j];
      const previous = input[(j + input.length - 1) % input.length];
      const currentInside  = _isInside(current,  edgeStart, edgeEnd);
      const previousInside = _isInside(previous, edgeStart, edgeEnd);
      if (currentInside) {
        if (!previousInside) {
          const inter = _intersection(previous, current, edgeStart, edgeEnd);
          if (inter) output.push(inter);
        }
        output.push(current);
      } else if (previousInside) {
        const inter = _intersection(previous, current, edgeStart, edgeEnd);
        if (inter) output.push(inter);
      }
    }
  }
  return output;
}

function _isInside(p, a, b) {
  return (b.lng - a.lng) * (p.lat - a.lat) - (b.lat - a.lat) * (p.lng - a.lng) >= 0;
}

function _intersection(p1, p2, p3, p4) {
  const d1lat = p2.lat - p1.lat, d1lng = p2.lng - p1.lng;
  const d2lat = p4.lat - p3.lat, d2lng = p4.lng - p3.lng;
  const denom = d1lat * d2lng - d1lng * d2lat;
  if (Math.abs(denom) < 1e-10) return null;
  const t = ((p3.lat - p1.lat) * d2lng - (p3.lng - p1.lng) * d2lat) / denom;
  return { lat: p1.lat + t * d1lat, lng: p1.lng + t * d1lng };
}

function _areaPoligonoMetros(pts) {
  if (pts.length < 3) return 0;
  const R = 6371000;
  let area = 0;
  for (let i = 0; i < pts.length; i++) {
    const j    = (i + 1) % pts.length;
    const lat1 = pts[i].lat * Math.PI / 180;
    const lat2 = pts[j].lat * Math.PI / 180;
    const dLng = (pts[j].lng - pts[i].lng) * Math.PI / 180;
    area += dLng * (2 + Math.sin(lat1) + Math.sin(lat2));
  }
  return Math.abs(area * R * R / 2);
}

function _semanaId(date) {
  const d    = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day  = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const year = d.getUTCFullYear();
  const week = Math.ceil((((d - new Date(Date.UTC(year, 0, 1))) / 86400000) + 1) / 7);
  return `${year}-W${String(week).padStart(2, '0')}`;
}

function _lunes(offsetDias = 0) {
  const d   = new Date();
  const day = d.getDay() || 7;
  d.setDate(d.getDate() - day + 1 + offsetDias);
  return d;
}

function _calcularKmRequeridos(baseKm, difficultyLevel) {
  if (difficultyLevel <= 1) return baseKm;
  if (difficultyLevel <= 4) return baseKm * 1.5;
  if (difficultyLevel <= 7) return baseKm * 2.5;
  if (difficultyLevel <= 9) return baseKm * 4.0;
  return baseKm * 6.0;
}

function _shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}
// v7 — atacarTerritorio integrado