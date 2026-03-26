/**
 * Risk Runner — Cloud Functions
 *
 * INSTALAR:
 *   cd functions
 *   npm install
 *   firebase deploy --only functions
 *
 * FUNCIONES:
 *   1. resolverDesafioExpirado     — se activa sola cada hora (scheduled)
 *   2. onDesafioActualizado        — se activa cuando cambia un desafío (trigger)
 *   3. acumularPuntosDesafio       — llamada desde el cliente al terminar carrera
 *   4. cerrarTemporada             — llamada desde admin para cerrar la temporada
 *   5. conquistarTerritorio        — llamada desde el cliente para conquistar un territorio
 *   6. renombrarTerritorio         — llamada desde el cliente para poner nombre a un territorio
 */

const { onSchedule }         = require('firebase-functions/v2/scheduler');
const { onDocumentUpdated }  = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp }      = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

// =============================================================================
// 1. RESOLVER DESAFÍOS EXPIRADOS — se ejecuta cada hora automáticamente
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

    const promesas = snap.docs.map(doc => _resolverDesafio(doc.id));
    const resultados = await Promise.allSettled(promesas);

    const ok      = resultados.filter(r => r.status === 'fulfilled').length;
    const errores = resultados.filter(r => r.status === 'rejected').length;
    console.log(`Resueltos: ${ok} | Errores: ${errores}`);
  }
);

// =============================================================================
// 2. TRIGGER — cuando un desafío pasa a 'activo', comprobar si ya expiró
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
// 3. ACUMULAR PUNTOS — llamada desde Flutter al terminar una carrera
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
// 4. CERRAR TEMPORADA — llamada desde panel de admin
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

    const zonasSnap      = await db.collection('zonas').orderBy('nombre').get();
    const zonas          = zonasSnap.docs;
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
        userId:             ganadorId,
        userNick:           nick,
        zonaId:             zonaDoc.id,
        zonaNombre:         zona.nombre,
        zonaNombreCorto:    zona.nombre_corto || null,
        temporada:          temporada.numero,
        areaM2:             areaDominada,
        monedasRecompensa:  monedas,
        coronaDesbloqueada: true,
        fechaOtorgado:      FieldValue.serverTimestamp(),
      });
      opsEnBatch++;

      batch.update(db.collection('zonas').doc(zonaDoc.id), {
        rey_actual_id:    ganadorId,
        rey_actual_nick:  nick,
        temporada_actual: temporada.numero,
      });
      opsEnBatch++;

      batch.update(db.collection('players').doc(ganadorId), {
        monedas: FieldValue.increment(monedas),
        'avatar_config.coronaDesbloqueada': true,
      });
      opsEnBatch++;

      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        toUserId:          ganadorId,
        type:              'titulo_rey',
        zonaId:            zonaDoc.id,
        zonaNombre:        zona.nombre_corto || zona.nombre,
        temporada:         temporada.numero,
        monedasRecompensa: monedas,
        message:           `👑 ¡Eres el Rey de ${zona.nombre_corto || zona.nombre} en la T${temporada.numero}! +${monedas} 🪙`,
        read:              false,
        timestamp:         FieldValue.serverTimestamp(),
      });
      opsEnBatch++;

      titulosOtorgados++;
      await _commitBatchSiLleno();
    }

    batch.update(db.collection('temporadas').doc(temporadaId), {
      activa:       false,
      fecha_cierre: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    console.log(`Temporada ${temporadaId} cerrada. Títulos: ${titulosOtorgados}`);
    return { titulosOtorgados };
  }
);

// =============================================================================
// 5. CONQUISTAR TERRITORIO — llamada desde Flutter cuando el usuario conquista
// =============================================================================
//
// Valida en el servidor:
//   1. El territorio existe
//   2. El atacante no es el dueño actual (si lo es, solo registra visita)
//   3. El territorio lleva >= 10 días sin visita
//   4. El usuario está físicamente a <= 200 m del centro del territorio
//
// Todo dentro de una transacción atómica — imposible doble conquista.
//
// LLAMADA DESDE FLUTTER:
//   final callable = FirebaseFunctions.instance.httpsCallable('conquistarTerritorio');
//   final result   = await callable.call({
//     'docId':      territorio.docId,
//     'latUsuario': posicion.latitude,
//     'lngUsuario': posicion.longitude,
//   });

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

      // Si es nuestro propio territorio → solo visita
      if (duenoId === uid) {
        tx.update(territorioRef, {
          ultima_visita: FieldValue.serverTimestamp(),
        });
        return { accion: 'visita' };
      }

      // Validar deterioro >= 10 días
      const ultimaVisita  = t.ultima_visita ? t.ultima_visita.toMillis() : 0;
      const diasSinVisita = (Date.now() - ultimaVisita) / (1000 * 60 * 60 * 24);

      if (diasSinVisita < 10) {
        throw new HttpsError(
          'failed-precondition',
          `El territorio solo lleva ${Math.floor(diasSinVisita)} días sin visita. Necesita 10.`
        );
      }

      // Validar proximidad <= 200 m
      const latC       = t.centroLat ?? (t.centro?.lat ?? 0);
      const lngC       = t.centroLng ?? (t.centro?.lng ?? 0);
      const distanciaM = _haversineMetros(latUsuario, lngUsuario, latC, lngC);

      if (distanciaM > 200) {
        throw new HttpsError(
          'failed-precondition',
          `Debes estar a menos de 200 m del territorio (estás a ${Math.round(distanciaM)} m).`
        );
      }

      const reyAnteriorId   = t.rey_id       ?? null;
      const reyAnteriorNick = t.rey_nickname  ?? null;

      tx.update(territorioRef, {
        userId:            uid,
        nickname:          nuevoNick,
        ultima_visita:     FieldValue.serverTimestamp(),
        conquistado_por:   uid,
        fecha_conquista:   FieldValue.serverTimestamp(),
        fecha_desde_dueno: FieldValue.serverTimestamp(),
        rey_id:            null,
        rey_nickname:      null,
        rey_desde:         null,
      });

      return {
        accion:          'conquista',
        duenoAnteriorId: duenoId,
        reyAnteriorId,
        reyAnteriorNick,
        nuevoNick,
        clanId: playerSnap.exists ? (playerSnap.data().clanId ?? null) : null,
      };
    });

    // Post-transacción: notificaciones y puntos clan
    if (resultado.accion === 'conquista') {
      const batch = db.batch();

      batch.set(db.collection('notifications').doc(), {
        toUserId:  resultado.duenoAnteriorId,
        type:      'territory_lost',
        message:   `⚔️ ${resultado.nuevoNick} ha conquistado uno de tus territorios.`,
        read:      false,
        timestamp: FieldValue.serverTimestamp(),
      });

      if (resultado.reyAnteriorId && resultado.reyAnteriorId !== '') {
        batch.set(db.collection('notifications').doc(), {
          toUserId:  resultado.reyAnteriorId,
          type:      'territory_king_lost',
          message:   `👑💀 ${resultado.nuevoNick} te ha arrebatado el reinado. Ya no eres Rey de ese territorio.`,
          read:      false,
          timestamp: FieldValue.serverTimestamp(),
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
// 6. RENOMBRAR TERRITORIO — llamada desde Flutter cuando el dueño pone nombre
// =============================================================================
//
// Valida en el servidor:
//   1. El usuario es el dueño actual del territorio
//   2. El nombre no está vacío y tiene <= 30 caracteres
//   3. Solo contiene caracteres permitidos (letras, números, espacios, - ' . ,)
//   4. No contiene palabras de la lista negra
//
// LLAMADA DESDE FLUTTER:
//   final callable = FirebaseFunctions.instance.httpsCallable('renombrarTerritorio');
//   await callable.call({ 'docId': territorio.docId, 'nombre': 'Mi nombre' });

exports.renombrarTerritorio = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Debes estar autenticado.');
  }

  const uid    = request.auth.uid;
  const { docId, nombre } = request.data;

  // 1. Validar parámetros
  if (!docId || typeof docId !== 'string') {
    throw new HttpsError('invalid-argument', 'docId inválido.');
  }
  if (typeof nombre !== 'string') {
    throw new HttpsError('invalid-argument', 'El nombre debe ser texto.');
  }

  const nombreLimpio = nombre.trim();

  // 2. Longitud
  if (nombreLimpio.length === 0) {
    throw new HttpsError('invalid-argument', 'El nombre no puede estar vacío.');
  }
  if (nombreLimpio.length > 30) {
    throw new HttpsError('invalid-argument', 'El nombre no puede superar los 30 caracteres.');
  }

  // 3. Caracteres permitidos: letras (con acentos/ñ), números, espacios, - ' . ,
  const formatoValido = /^[\p{L}\p{N} \-'.,!?áéíóúàèìòùäëïöüñçÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÑÇ]+$/u;
  if (!formatoValido.test(nombreLimpio)) {
    throw new HttpsError('invalid-argument', 'El nombre contiene caracteres no permitidos.');
  }

  // 4. Lista negra — palabras prohibidas (insensible a mayúsculas y acentos)
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

  const nombreNorm = _normalizar(nombreLimpio);
  const palabraProhibida = LISTA_NEGRA.find(p => nombreNorm.includes(_normalizar(p)));
  if (palabraProhibida) {
    throw new HttpsError('invalid-argument', 'El nombre contiene contenido no permitido.');
  }

  // 5. Comprobar que el usuario es el dueño
  const territorioRef = db.collection('territories').doc(docId);
  const territorioSnap = await territorioRef.get();

  if (!territorioSnap.exists) {
    throw new HttpsError('not-found', 'El territorio no existe.');
  }
  if (territorioSnap.data().userId !== uid) {
    throw new HttpsError('permission-denied', 'Solo el dueño puede renombrar su territorio.');
  }

  // 6. Guardar
  await territorioRef.update({ nombre_territorio: nombreLimpio });

  return { ok: true, nombre: nombreLimpio };
});

// =============================================================================
// HELPER PRIVADO: resolver un desafío con transacción
// =============================================================================
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

    const ganadorId    = pRetador >= pRetado ? data.retadorId   : data.retadoId;
    const perdedorId   = pRetador >= pRetado ? data.retadoId    : data.retadorId;
    const ganadorNick  = pRetador >= pRetado ? data.retadorNick : data.retadoNick;
    const perdedorNick = pRetador >= pRetado ? data.retadoNick  : data.retadorNick;
    const premio       = (data.apuesta || 0) * 2;

    tx.update(ref, {
      estado:     'finalizado',
      ganadorId,
      resolvedAt: FieldValue.serverTimestamp(),
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
        toUserId:     ganadorId,
        type:         'desafio_ganado',
        fromNickname: perdedorNick,
        desafioId,
        message:      `🏆 ¡Ganaste el desafío contra ${perdedorNick}! +${premio} 🪙`,
        read:         false,
        timestamp:    FieldValue.serverTimestamp(),
      }),
      db.collection('notifications').add({
        toUserId:     perdedorId,
        type:         'desafio_perdido',
        fromNickname: ganadorNick,
        desafioId,
        message:      `💀 Perdiste el desafío contra ${ganadorNick}. Él se lleva ${premio} 🪙`,
        read:         false,
        timestamp:    FieldValue.serverTimestamp(),
      }),
    ]);
  } catch (e) {
    console.error('Error enviando notificaciones de desafío:', e);
  }
}

// =============================================================================
// HELPER PRIVADO: distancia Haversine en metros
// =============================================================================
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

// =============================================================================
// HELPER PRIVADO: calcular área de intersección entre dos polígonos (Sutherland-Hodgman)
// =============================================================================
function _calcularAreaInterseccion(subject, clip) {
  const interseccion = _sutherlandHodgman(subject, clip);
  if (interseccion.length < 3) return 0;
  return _areaPoligonoMetros(interseccion);
}

function _sutherlandHodgman(subject, clip) {
  let output = [...subject];
  if (output.length === 0) return [];

  for (let i = 0; i < clip.length; i++) {
    if (output.length === 0) return [];
    const input      = [...output];
    output           = [];
    const edgeStart  = clip[i];
    const edgeEnd    = clip[(i + 1) % clip.length];

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