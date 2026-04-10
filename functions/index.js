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
    // 1) Libera todos los territorios (owner, clausula, conquestCount).
    // 2) Baraja posiciones (puntos, centro, nombre, icon) dentro de cada tier
    //    para que el mapa se vea renovado cada semana.
    const porTier = { pequeno: [], mediano: [], legendario: [] };
    for (const doc of snap.docs) {
      const d    = doc.data();
      const tier = d.tier || 'pequeno';
      if (porTier[tier]) {
        porTier[tier].push({
          id:       doc.id,
          puntos:   d.puntos   ?? [],
          centro:   d.centro   ?? null,
          centroLat: d.centroLat ?? 0,
          centroLng: d.centroLng ?? 0,
          nombre:   d.nombre   ?? d.epicName ?? '',
          epicName: d.epicName ?? d.nombre   ?? '',
          icon:     d.icon     ?? '🏴',
          inspiration: d.inspiration ?? '',
        });
      }
    }

    // Barajar posiciones dentro de cada tier
    for (const tier of Object.keys(porTier)) {
      _shuffle(porTier[tier]);
    }

    const batchReset = db.batch();
    for (const doc of snap.docs) {
      const d    = doc.data();
      const tier = d.tier || 'pequeno';
      const baseKm = d.baseKm ?? 5;

      // Tomar el siguiente slot barajado del mismo tier
      const slot = porTier[tier].shift();

      batchReset.update(doc.ref, {
        ownerUid:          null,
        ownerNickname:     null,
        ownerColor:        null,
        libre:             true,
        clausulaKm:        baseKm,
        conquestCount:     0,
        kmUltimaConquista: null,
        conquistadoEn:     null,
        // Nueva posición / identidad rotada
        puntos:            slot?.puntos    ?? d.puntos    ?? [],
        centro:            slot?.centro    ?? d.centro    ?? null,
        centroLat:         slot?.centroLat ?? d.centroLat ?? 0,
        centroLng:         slot?.centroLng ?? d.centroLng ?? 0,
        nombre:            slot?.nombre    ?? d.nombre    ?? '',
        epicName:          slot?.epicName  ?? d.epicName  ?? '',
        icon:              slot?.icon      ?? d.icon      ?? '🏴',
        inspiration:       slot?.inspiration ?? d.inspiration ?? '',
      });
    }
    await batchReset.commit();

    console.log(
      `[liquidarGuerraGlobal] Semana ${semanaAnterior} cerrada. ` +
      `${ganadores.length}/${snap.size} territorios tenían dueño. ` +
      `${Object.keys(monedasPorUid).length} jugadores premiados. ` +
      `Mapa reseteado: ${snap.size} territorios libres para el nuevo ciclo.`
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
// =============================================================================
exports.conquistarTerritorioGlobal = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
    }

    const uid = request.auth.uid;
    const { territorioId, activityLogId, ownerColor, kmCorridosEnSesion } = request.data;

    if (!territorioId || typeof territorioId !== 'string') {
      throw new HttpsError('invalid-argument', 'territorioId inválido.');
    }
    if (!activityLogId || typeof activityLogId !== 'string') {
      throw new HttpsError('invalid-argument', 'activityLogId inválido.');
    }
    if (typeof kmCorridosEnSesion !== 'number' || kmCorridosEnSesion <= 0) {
      throw new HttpsError('invalid-argument', 'kmCorridosEnSesion inválido.');
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

    if (log.userId !== uid) {
      throw new HttpsError('permission-denied', 'Este log no te pertenece.');
    }

    const logTimestamp = log.timestamp?.toMillis() ?? 0;
    if (Date.now() - logTimestamp > 2 * 60 * 60 * 1000) {
      throw new HttpsError('failed-precondition', 'El log ha expirado.');
    }

    if (log.usado_conquista_global === true) {
      throw new HttpsError('failed-precondition', 'Este log ya fue usado.');
    }

    const territorio = territorioSnap.data();

    // ── Verificar que no es ya el dueño
    if (territorio.ownerUid === uid) {
      throw new HttpsError('failed-precondition', 'Ya eres el dueño.');
    }

    // ── Verificar cláusula: km corridos >= clausulaKm actual
    // Si nunca ha sido conquistado, clausulaKm = baseKm
    const clausulaActual = territorio.clausulaKm ?? territorio.baseKm ?? 5;
    if (kmCorridosEnSesion < clausulaActual) {
      throw new HttpsError(
        'failed-precondition',
        `Necesitas correr al menos ${clausulaActual.toFixed(2)} km. ` +
        `Has corrido ${kmCorridosEnSesion.toFixed(2)} km.`
      );
    }

    // ── Verificar límite de 5 territorios activos
    const miosSnap = await db.collection('global_territories')
      .where('ownerUid', '==', uid)
      .count()
      .get();

    if (miosSnap.data().count >= 5) {
      throw new HttpsError(
        'failed-precondition',
        'Ya tienes 5 territorios globales activos.'
      );
    }

    const playerSnap = await db.collection('players').doc(uid).get();
    if (!playerSnap.exists) {
      throw new HttpsError('not-found', 'Jugador no encontrado.');
    }

    const player        = playerSnap.data();
    const ownerNickname = player.nickname ?? 'Guerrero';
    const ownerColorFinal = player.territorio_color ?? ownerColor ?? null;
    const anteriorDueno   = territorio.ownerUid ?? null;

    // ── Nueva cláusula = km corridos × 1.15
    // El siguiente tendrá que superar esta marca
    const nuevaClausula  = kmCorridosEnSesion * 1.15;
    const nuevoCount     = (territorio.conquestCount ?? 0) + 1;

    await db.runTransaction(async (tx) => {
      const terRef   = db.collection('global_territories').doc(territorioId);
      const logRef   = db.collection('activity_logs').doc(activityLogId);
      const terSnap2 = await tx.get(terRef);

      if (!terSnap2.exists) {
        throw new HttpsError('not-found', 'Territorio desapareció en la transacción.');
      }
      if (terSnap2.data().ownerUid === uid) {
        throw new HttpsError('failed-precondition', 'Ya eres el dueño.');
      }

      tx.update(terRef, {
        ownerUid:        uid,
        ownerNickname:   ownerNickname,
        ownerColor:      ownerColorFinal,
        libre:           false,
        clausulaKm:      nuevaClausula,   // ← marca del conquistador × 1.15
        conquestCount:   nuevoCount,
        kmUltimaConquista: kmCorridosEnSesion,
        conquistadoEn:   FieldValue.serverTimestamp(),
      });

      tx.update(logRef, {
        usado_conquista_global: true,
        territorio_conquistado: territorioId,
      });
    });

    // ── Notificaciones
    const notifBatch = db.batch();

    notifBatch.set(db.collection('notifications').doc(), {
      toUserId:  uid,
      type:      'global_territory_conquered',
      message:   `⚔️ ¡Conquistaste "${territorio.epicName ?? territorio.nombre}"! ` +
                 `Tu cláusula: ${nuevaClausula.toFixed(1)} km. Defiéndelo hasta el lunes.`,
      read:      false,
      timestamp: FieldValue.serverTimestamp(),
    });

    if (anteriorDueno && anteriorDueno !== uid) {
      notifBatch.set(db.collection('notifications').doc(), {
        toUserId:  anteriorDueno,
        type:      'global_territory_lost',
        message:   `💀 ${ownerNickname} te ha arrebatado ` +
                   `"${territorio.epicName ?? territorio.nombre}" ` +
                   `corriendo ${kmCorridosEnSesion.toFixed(1)} km.`,
        read:      false,
        timestamp: FieldValue.serverTimestamp(),
      });
    }

    await notifBatch.commit();

    // Los puntos de liga NO se otorgan al conquistar — solo el lunes al final
    // del ciclo, en función de los territorios que el jugador controla en ese
    // momento. Conquistas intermedias sin sobrevivir al lunes no puntúan.

    return {
      ok:            true,
      territorioNombre: territorio.epicName ?? territorio.nombre,
      nuevaClausula,
      conquestCount: nuevoCount,
      kmCorridosEnSesion,
    };
  }
);

// =============================================================================
// 10. AJUSTAR TERRITORIOS ACTIVOS — se ejecuta cada día a las 00:00 UTC
// =============================================================================
exports.ajustarTerritoriosActivos = onSchedule(
  {
    schedule: 'every day 00:00',
    timeZone: 'UTC',
    memory:   '256MiB',
    region:   'europe-west1',
  },
  async () => {
    const hace7d = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

    // Contar jugadores únicos activos en los últimos 7 días
    const logsSnap = await db.collection('activity_logs')
      .where('timestamp', '>=', hace7d)
      .get();

    const jugadoresUnicos = new Set(
      logsSnap.docs
        .map(d => d.data().userId)
        .filter(Boolean)
    );
    const numJugadores   = Math.max(10, jugadoresUnicos.size);
    // Proporción: 1 territorio por cada 1.4 jugadores
    const objetivoTotal  = Math.round(numJugadores / 1.4);

    const col  = db.collection('global_territories');
    const snap = await col.get();

    const conquistados    = snap.docs.filter(d => d.data().ownerUid != null);
    const libresActivos   = snap.docs.filter(d => d.data().ownerUid == null && d.data().activo !== false);
    const libresInactivos = snap.docs.filter(d => d.data().ownerUid == null && d.data().activo === false);

    const totalActual    = conquistados.length + libresActivos.length;
    const diferencia     = objetivoTotal - totalActual;

    console.log(
      `[ajustarTerritoriosActivos] Jugadores: ${numJugadores} → ` +
      `Objetivo: ${objetivoTotal} | Actual: ${totalActual} ` +
      `(${conquistados.length} conquistados + ${libresActivos.length} libres)`
    );

    const batch  = db.batch();
    let cambios  = 0;

    if (diferencia > 0) {
      // Faltan territorios — activar inactivos libres
      const aActivar = _shuffle([...libresInactivos]).slice(0, diferencia);
      for (const d of aActivar) {
        // Resetear cláusula al baseKm original al activarse de nuevo
        const data = d.data();
        batch.update(col.doc(d.id), {
          activo:       true,
          clausulaKm:   data.baseKm ?? 5,
          conquestCount: 0,
          ownerUid:     null,
          ownerNickname: null,
          ownerColor:   null,
          libre:        true,
        });
        cambios++;
      }
      if (aActivar.length < diferencia) {
        // No hay suficientes inactivos — crear nuevos territorios libres
        const porCrear = diferencia - aActivar.length;
        for (let i = 0; i < porCrear; i++) {
          const ref  = col.doc();
          const tier = i < porCrear * 0.6 ? 'pequeno'
                     : i < porCrear * 0.9 ? 'mediano'
                     : 'legendario';
          batch.set(ref, _nuevoTerritorioLibre(tier));
          cambios++;
        }
      }

    } else if (diferencia < 0) {
      // Sobran — desactivar solo los libres (nunca los conquistados)
      const aDesactivar = _shuffle([...libresActivos]).slice(0, Math.abs(diferencia));
      for (const d of aDesactivar) {
        batch.update(col.doc(d.id), { activo: false });
        cambios++;
      }
    }

    if (cambios > 0) await batch.commit();

    await db.collection('guerra_global_logs').add({
      tipo:          'recalculo_diario',
      fecha:         new Date(),
      jugadores:     numJugadores,
      objetivoTotal,
      totalAntes:    totalActual,
      conquistados:  conquistados.length,
      libresAntes:   libresActivos.length,
      cambios,
    });

    console.log(`[ajustarTerritoriosActivos] ${cambios} cambios aplicados.`);
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
// 11b. ACTIVAR ESCUDO — paga monedas, protege el territorio X horas
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

    const terRef     = db.collection('territories').doc(territorioId);
    const playerRef  = db.collection('players').doc(uid);

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
        escudo_activo:  true,
        escudo_expira:  Timestamp.fromDate(expira),
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
// 12. ATACAR TERRITORIO — sistema de HP v7
// =============================================================================
// =============================================================================
// 12. ATACAR TERRITORIO — sistema de Estados v8
// =============================================================================
async function _obtenerBarrio(lat, lng) {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&zoom=15`;
    const res  = await fetch(url);
    const data = await res.json();
    return data.address?.suburb
        || data.address?.neighbourhood
        || data.address?.quarter
        || data.address?.city_district
        || null;
  } catch (e) {
    console.error('Error geocodificando barrio:', e);
    return null;
  }
}

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
      // Es propio — reforzar
      const hpActualPropio = _hpActual(terData);
      let nuevoHpPropio;
      if (hpActualPropio >= 70) {
        nuevoHpPropio = 100; // Fuerte → 100
      } else if (hpActualPropio >= 30) {
        nuevoHpPropio = 100; // Medio → 100 si pasas corriendo
      } else {
        nuevoHpPropio = 30;  // Leve → sube a Medio (HP 30)
      }
      await terRef.update({
        hp:                    nuevoHpPropio,
        ultimaActualizacionHp: FieldValue.serverTimestamp(),
        ultima_visita:         FieldValue.serverTimestamp(),
      });
      return {
        ok: true, accion: 'refuerzo',
        hpAntes: hpActualPropio, hpDespues: nuevoHpPropio,
        danio: 0, monedasBotin: 0,
        mensaje: nuevoHpPropio === 100
          ? '¡Territorio reforzado a máximo!'
          : '¡Territorio reforzado a estado Medio!',
      };
    }

    // ── Escudo activo ──────────────────────────────────────────────────────
    if (terData.escudo_activo === true && terData.escudo_expira) {
      const expira = terData.escudo_expira.toDate();
      if (expira > new Date()) {
        const hpEscudo = _hpActual(terData);
        return {
          ok: false, accion: 'sin_daño',
          mensaje: 'Este territorio está blindado.',
          hpAntes: hpEscudo, hpDespues: hpEscudo,
          danio: 0, monedasBotin: 0,
        };
      }
    }

    const hpActual = _hpActual(terData);

    // ── Determinar estado ──────────────────────────────────────────────────
    // Fuerte: 70-100 | Medio: 30-69 | Leve: 1-29
    const esFuerte = hpActual >= 70;
    const esMedio  = hpActual >= 30 && hpActual < 70;
    const esLeve   = hpActual < 30 && hpActual > 0;

    // ── Verificar intersección de ruta con territorio ──────────────────────
    const poliAtacante  = rutaAtacante.map(p => ({ x: p.lng, y: p.lat }));
    const poliDefensor  = (terData.puntos || []).map(p => ({ x: p.lng, y: p.lat }));
    const areaDefensorM2 = _calcularAreaM2(poliDefensor);
    const interseccion   = _sutherlandHodgman(poliAtacante, poliDefensor);
    const areaInterseccionM2 = interseccion.length >= 3
      ? _calcularAreaM2(interseccion) : 0;

    if (areaInterseccionM2 < 1) {
      return {
        ok: false, accion: 'sin_daño',
        mensaje: 'Tu ruta no pasa por este territorio.',
        hpAntes: hpActual, hpDespues: hpActual,
        danio: 0, monedasBotin: 0,
      };
    }

    // ── Comprobar condición según estado ───────────────────────────────────
    const VEL_FUERTE = 7.0; // km/h mínimo para atacar Fuerte
    const VEL_MEDIO  = 5.0; // km/h mínimo para atacar Medio

    if (esFuerte && velocidadMediaAtacanteKmh < VEL_FUERTE) {
      return {
        ok: false, accion: 'sin_daño',
        mensaje: `Este territorio está Fuerte. Necesitas ir a más de ${VEL_FUERTE} km/h.`,
        hpAntes: hpActual, hpDespues: hpActual,
        danio: 0, monedasBotin: 0,
      };
    }

    if (esMedio && velocidadMediaAtacanteKmh < VEL_MEDIO) {
  // Verificar si el atacante registró actividad cerca del territorio
  // en las últimas 48h — usando centroLat/centroLng del territorio
  const hace48h = new Date(Date.now() - 48 * 60 * 60 * 1000);

  const centroLat = terData.centroLat ?? (terData.centro?.lat ?? 0);
  const centroLng = terData.centroLng ?? (terData.centro?.lng ?? 0);
  const RADIO_METROS = 300;

  const sesionesRecientes = await db.collection('activity_logs')
    .where('userId', '==', atacanteId)
    .where('timestamp', '>=', hace48h)
    .get();

  // Comprobamos si alguna sesión reciente terminó cerca del centro
  // del territorio usando las coordenadas finales guardadas en el log
  const yaEstuvoCerca = sesionesRecientes.docs.some(doc => {
    const log = doc.data();

    // Intentamos con coordenadas finales del log si las tiene
    const latFinal = log.latFinal ?? log.lat ?? null;
    const lngFinal = log.lngFinal ?? log.lng ?? null;

    if (latFinal !== null && lngFinal !== null) {
      const distancia = _haversineMetros(latFinal, lngFinal, centroLat, centroLng);
      return distancia <= RADIO_METROS;
    }

    // Fallback: si no tiene coordenadas finales, miramos
    // si el log tiene centroLat/centroLng de la zona donde corrió
    const logLat = log.centroLat ?? null;
    const logLng = log.centroLng ?? null;
    if (logLat !== null && logLng !== null) {
      const distancia = _haversineMetros(logLat, logLng, centroLat, centroLng);
      return distancia <= RADIO_METROS * 2; // radio más amplio para centros
    }

    return false;
  });

  if (!yaEstuvoCerca) {
    return {
      ok: false, accion: 'sin_daño',
      mensaje: `Territorio en estado Medio. Necesitas ${VEL_MEDIO} km/h o haber corrido cerca en las últimas 48h.`,
      hpAntes: hpActual, hpDespues: hpActual,
      danio: 0, monedasBotin: 0,
    };
  }
}

    // ── Calcular daño ──────────────────────────────────────────────────────
    // En estado Leve cualquier paso conquista directamente
    let danio;
    let hpNuevo;

    if (esLeve) {
      // Conquista directa
      danio   = hpActual;
      hpNuevo = 0;
    } else {
      // Daño proporcional al área solapada y velocidad
      const porcentajeArea = Math.min(areaInterseccionM2 / areaDefensorM2, 1.0);
      const factorVelocidad = esFuerte
        ? (velocidadMediaAtacanteKmh / VEL_FUERTE)
        : (velocidadMediaAtacanteKmh / VEL_MEDIO);
      const factorFinal = Math.min(factorVelocidad * porcentajeArea, 1.0);

      // En Medio el daño es mayor porque el territorio ya está debilitado
      const multiplicadorEstado = esMedio ? 1.4 : 1.0;
      danio   = Math.min(
        Math.round(hpActual * factorFinal * multiplicadorEstado),
        hpActual
      );
      // HP nunca baja de 1 por decay — solo conquista lo lleva a 0
      hpNuevo = Math.max(hpActual - danio, 1);

      // Si el daño es suficiente para dejar en 1, es conquista
      if (hpNuevo === 1 && danio >= hpActual - 1) {
        hpNuevo = 0;
        danio   = hpActual;
      }
    }

    const monedasBotin = Math.round(danio * 0.5 + areaInterseccionM2 * 0.1);

    const atacanteSnap  = await db.collection('players').doc(atacanteId).get();
    const atacanteData  = atacanteSnap.exists ? atacanteSnap.data() : {};
    const atacanteNick  = atacanteData.nickname  || 'Alguien';
    const atacanteColor = atacanteData.territorio_color || null;

    // ── CASO A: CONQUISTA TOTAL — requiere pisado del 95%+ del territorio ──
    if (hpNuevo === 0 && (areaInterseccionM2 / areaDefensorM2) >= 0.95) {
      const defensorId   = terData.userId;
      const defensorNick = terData.nickname || 'Alguien';
      const batch        = db.batch();
      
    // ── CASO A: CONQUISTA TOTAL ──
      const barrio = await _obtenerBarrio(
          terData.centroLat ?? terData.centro?.lat,
          terData.centroLng ?? terData.centro?.lng
        );

      batch.update(terRef, {
        barrio: barrio,
        userId:                atacanteId,
        nickname:              atacanteNick,
        color:                 atacanteColor,
        hp:                    100,
        hpMax:                 100,
        velocidadConquistaKmh: velocidadMediaAtacanteKmh,
        ultimaActualizacionHp: FieldValue.serverTimestamp(),
        ultima_visita:         FieldValue.serverTimestamp(),
        fecha_desde_dueno:     FieldValue.serverTimestamp(),
        rey_id:                null,
        rey_nickname:          null,
        rey_desde:             null,
        // Guardamos el estado anterior para historial
        conquistado_de_estado: esFuerte ? 'fuerte' : esMedio ? 'medio' : 'leve',
      });

      batch.update(db.collection('players').doc(atacanteId), {
        monedas: FieldValue.increment(monedasBotin),
      });

      batch.set(db.collection('notifications').doc(), {
        toUserId:     defensorId,
        type:         'territory_lost',
        message:      `😤 ¡${atacanteNick} ha conquistado uno de tus territorios!`,
        fromNickname: atacanteNick,
        territoryId:  terRef.id,
        read:         false,
        timestamp:    FieldValue.serverTimestamp(),
      });

      await batch.commit();

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
        estadoAntes: esFuerte ? 'fuerte' : esMedio ? 'medio' : 'leve',
        mensaje: `¡Has conquistado el territorio de ${defensorNick}!`,
        territorioRobadoId: terRef.id,
      };
    }

    // ── CASO B: ROBO PARCIAL — el atacante pisó menos del 95% ────────────
    if (hpNuevo === 0 && (areaInterseccionM2 / areaDefensorM2) < 0.95) {
      const defensorId   = terData.userId;
      const defensorNick = terData.nickname || 'Alguien';
      const batch        = db.batch();

      const puntosRestantes = poliDefensor.filter(
        p => !_puntoEnPoligono(p, poliAtacante)
      );

      if (puntosRestantes.length >= 3) {
        const centroRestante = _centroide(puntosRestantes);
        
        // ── CASO B: ROBO PARCIAL ──
      const barrioRestante = puntosRestantes.length >= 3
        ? await _obtenerBarrio(centroRestante.y, centroRestante.x)
        : null;

const barrioNuevo = await _obtenerBarrio(
  centroInterseccion.y,
  centroInterseccion.x
);

        // El trozo restante conserva su HP intacto — solo la zona pisada
        // por el atacante se vio afectada. El resto del polígono no cambia de HP.
        batch.update(terRef, {
          puntos:                puntosRestantes.map(p => ({ lat: p.y, lng: p.x })),
          centro:                { lat: centroRestante.y, lng: centroRestante.x },
          centroLat:             centroRestante.y,
          centroLng:             centroRestante.x,
          hp:                    hpActual, // HP original conservado en la zona no pisada
          hpMax:                 100,
          ultimaActualizacionHp: FieldValue.serverTimestamp(),
        });
      } else {
        batch.delete(terRef);
      }

      const centroInterseccion = _centroide(interseccion);
      const nuevoTerRef        = db.collection('territories').doc();

      batch.set(nuevoTerRef, {
        userId:                atacanteId,
        nickname:              atacanteNick,
        color:                 atacanteColor,
        puntos:                interseccion.map(p => ({ lat: p.y, lng: p.x })),
        centro:                { lat: centroInterseccion.y, lng: centroInterseccion.x },
        centroLat:             centroInterseccion.y,
        centroLng:             centroInterseccion.x,
        hp:                    100,
        hpMax:                 100,
        velocidadConquistaKmh: velocidadMediaAtacanteKmh,
        ultimaActualizacionHp: FieldValue.serverTimestamp(),
        ultima_visita:         FieldValue.serverTimestamp(),
        fecha_desde_dueno:     FieldValue.serverTimestamp(),
        modo:                  'competitivo',
        area_m2:               areaInterseccionM2,
        rey_id:                null,
        rey_nickname:          null,
        rey_desde:             null,
        nombre_territorio:     null,
      });

      batch.update(db.collection('players').doc(atacanteId), {
        monedas: FieldValue.increment(monedasBotin),
      });

      batch.set(db.collection('notifications').doc(), {
        toUserId:     defensorId,
        type:         'territory_bitten',
        message:      `⚔️ ¡${atacanteNick} te ha robado un trozo de territorio!`,
        fromNickname: atacanteNick,
        territoryId:  terRef.id,
        read:         false,
        timestamp:    FieldValue.serverTimestamp(),
      });

      await batch.commit();

      return {
        ok: true, accion: 'robo_parcial',
        hpAntes: hpActual, hpDespues: 0,
        danio, monedasBotin,
        estadoAntes: esFuerte ? 'fuerte' : esMedio ? 'medio' : 'leve',
        mensaje: `¡Has robado un trozo del territorio de ${defensorNick}!`,
        territorioRobadoId: nuevoTerRef.id,
      };
    }

    // ── CASO C: DAÑO PARCIAL ───────────────────────────────────────────────
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

    // Notificar al defensor si baja de estado
    const estadoAntes  = esFuerte ? 'fuerte' : 'medio';
    const estadoDespues = hpNuevo >= 70 ? 'fuerte' : hpNuevo >= 30 ? 'medio' : 'leve';
    const bajóDeEstado  = estadoAntes !== estadoDespues;

    if (bajóDeEstado) {
      batch.set(db.collection('notifications').doc(), {
        toUserId:     defensorId,
        type:         'territory_weakened',
        message:      `⚠️ ¡${atacanteNick} ha debilitado tu territorio! Ahora está en estado ${estadoDespues.toUpperCase()}.`,
        fromNickname: atacanteNick,
        territoryId:  terRef.id,
        read:         false,
        timestamp:    FieldValue.serverTimestamp(),
      });
    } else if (hpNuevo <= 29 && hpActual > 29) {
      batch.set(db.collection('notifications').doc(), {
        toUserId:     defensorId,
        type:         'territory_under_attack',
        message:      `🔥 ¡${atacanteNick} está asediando tu territorio! Estado crítico: ${hpNuevo}% HP`,
        fromNickname: atacanteNick,
        territoryId:  terRef.id,
        read:         false,
        timestamp:    FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return {
      ok: true, accion: 'daño',
      hpAntes: hpActual, hpDespues: hpNuevo,
      danio, monedasBotin,
      estadoAntes,
      estadoDespues,
      bajóDeEstado,
      mensaje: bajóDeEstado
        ? `¡Has debilitado el territorio a estado ${estadoDespues}! HP: ${hpNuevo}%`
        : `Daño causado: ${danio} HP. El territorio tiene ${hpNuevo}% de salud.`,
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
      const nuevoHp = Math.max(
  Math.round(hpActual - decayPorHora * horasTranscurridas), 1
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
// HELPERS PRIVADOS
// =============================================================================

function _hpActual(terData) {
  const HP_MAX         = 100;
  const HP_DECAY_DIA   = 100 / 7;

  if (terData.hp === undefined || terData.hp === null) {
    const ultimaVisita = terData.ultima_visita
      ? terData.ultima_visita.toDate() : new Date();
    const dias = (new Date() - ultimaVisita) / (1000 * 60 * 60 * 24);
    return Math.max(Math.round(HP_MAX - dias * HP_DECAY_DIA), 1);
  }

  const ultimaActualizacion = terData.ultimaActualizacionHp
    ? terData.ultimaActualizacionHp.toDate() : new Date();
  const horasTranscurridas  = (new Date() - ultimaActualizacion) / (1000 * 60 * 60);
  const decayPorHora        = HP_DECAY_DIA / 24;
  return Math.max(Math.round(terData.hp - decayPorHora * horasTranscurridas), 1);
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
    // En empate gana el retado (defensor) — igual que en Risk clásico
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

function _nuevoTerritorioLibre(tier) {
  const config = {
    pequeno:    { baseKm: 2,  baseReward: 50,  nombres: ['El Pueblo del Río','La Aldea del Norte','El Cruce del Viento'] },
    mediano:    { baseKm: 8,  baseReward: 150, nombres: ['La Fortaleza del Centro','El Bastión del Este','La Torre del Horizonte'] },
    legendario: { baseKm: 20, baseReward: 400, nombres: ['El Corazón del Mapa','La Ciudadela Eterna','El Trono del Mundo'] },
  };
  const cfg    = config[tier];
  const nombre = cfg.nombres[Math.floor(Math.random() * cfg.nombres.length)];
  return {
    nombre,
    epicName:      nombre,
    tier,
    baseKm:        cfg.baseKm,
    baseReward:    cfg.baseReward,
    clausulaKm:    cfg.baseKm,   // empieza igual al baseKm
    conquestCount: 0,
    ownerUid:      null,
    ownerNickname: null,
    ownerColor:    null,
    libre:         true,
    activo:        true,
    puntos:        [],
  };
}
// v7 — atacarTerritorio integrado