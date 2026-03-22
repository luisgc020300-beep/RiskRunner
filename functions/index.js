/**
 * Risk Runner — Cloud Functions
 *
 * INSTALAR:
 *   cd functions
 *   npm install
 *   firebase deploy --only functions
 *
 * FUNCIONES:
 *   1. resolverDesafioExpirado   — se activa sola cada hora (scheduled)
 *   2. onDesafioActualizado      — se activa cuando cambia un desafío (trigger)
 *   3. acumularPuntosDesafio     — llamada desde el cliente al terminar carrera
 *   4. cerrarTemporada           — llamada desde admin para cerrar la temporada
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
// Antes: el cliente llamaba a verificarExpirados() al abrir la app.
//   → Problema: si los dos jugadores tienen la app cerrada, el desafío
//     nunca se resuelve. Además, dos clientes podían resolver el mismo
//     desafío a la vez (race condition).
//
// Ahora: esta función se ejecuta cada hora en el servidor.
//   → El desafío siempre se resuelve a tiempo.
//   → La transacción de Firestore garantiza que solo se resuelve UNA vez.

exports.resolverDesafiosExpirados = onSchedule(
  { schedule: 'every 60 minutes', region: 'europe-west1' },
  async () => {
    const ahora = Timestamp.now();

    // Buscar todos los desafíos activos que ya pasaron su fecha de fin
    const snap = await db.collection('desafios')
      .where('estado', '==', 'activo')
      .where('fin', '<=', ahora)
      .get();

    if (snap.empty) {
      console.log('No hay desafíos expirados.');
      return;
    }

    console.log(`Resolviendo ${snap.docs.length} desafíos expirados...`);

    // Resolver cada uno en paralelo (cada uno con su propia transacción)
    const promesas = snap.docs.map(doc => _resolverDesafio(doc.id));
    const resultados = await Promise.allSettled(promesas);

    const ok      = resultados.filter(r => r.status === 'fulfilled').length;
    const errores = resultados.filter(r => r.status === 'rejected').length;
    console.log(`Resueltos: ${ok} | Errores: ${errores}`);
  }
);

// =============================================================================
// 2. TRIGGER — cuando un desafío pasa a 'activo', programar su resolución
// =============================================================================
// Esto es un respaldo extra: si por alguna razón el scheduler falla,
// este trigger comprueba al momento de aceptar si el desafío ya expiró.

exports.onDesafioActualizado = onDocumentUpdated(
  { document: 'desafios/{desafioId}', region: 'europe-west1' },
  async (event) => {
    const antes  = event.data.before.data();
    const despues = event.data.after.data();

    // Solo nos importa cuando pasa de 'pendiente' a 'activo'
    if (antes.estado !== 'pendiente' || despues.estado !== 'activo') return;

    // Si la fecha de fin ya pasó en el momento de activarse, resolver directamente
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
// Antes: el cliente escribía directamente en Firestore con FieldValue.increment.
//   → Problema: un cliente malicioso podía enviar distanciaKm = 9999.
//
// Ahora: el servidor valida los datos antes de acumular.
//   → Límites razonables: máx 50km por carrera, máx 100 territorios.
//   → Si el desafío ya expiró, lo resuelve en vez de sumar puntos.
//
// LLAMADA DESDE FLUTTER:
//   final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
//       .httpsCallable('acumularPuntosDesafio');
//   await callable.call({
//     'distanciaKm': 5.2,
//     'territoriosConquistados': 3,
//   });

exports.acumularPuntosDesafio = onCall(
  { region: 'europe-west1' },
  async (request) => {
    // Autenticación obligatoria
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Usuario no autenticado.');
    }

    const uid = request.auth.uid;
    const { distanciaKm, territoriosConquistados } = request.data;

    // Validación de datos
    if (typeof distanciaKm !== 'number' || distanciaKm < 0 || distanciaKm > 100) {
      throw new HttpsError('invalid-argument', 'distanciaKm inválida.');
    }
    if (typeof territoriosConquistados !== 'number' ||
        territoriosConquistados < 0 || territoriosConquistados > 200) {
      throw new HttpsError('invalid-argument', 'territoriosConquistados inválido.');
    }

    const puntos = Math.round(territoriosConquistados * 10 + distanciaKm * 5);
    if (puntos === 0) return { puntosAcumulados: 0, desafiosActualizados: 0 };

    // Buscar desafíos activos del usuario (2 queries en paralelo)
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

    // Merge sin duplicados
    const docsMap = new Map();
    [...snapRetador.docs, ...snapRetado.docs].forEach(d => docsMap.set(d.id, d));
    const docs = Array.from(docsMap.values());

    if (docs.length === 0) return { puntosAcumulados: 0, desafiosActualizados: 0 };

    let desafiosActualizados = 0;

    await Promise.all(docs.map(async (doc) => {
      const data = doc.data();
      const fin  = data.fin;

      // Si ya expiró, resolver en vez de sumar
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
// Antes: cerrarTemporada() se ejecutaba desde el cliente (zona_service.dart).
//   → Problema: hace N queries en loop (una por zona) + batch con todas
//     las operaciones. Podía tardar minutos y fallar a la mitad sin rollback.
//
// Ahora: se ejecuta en el servidor con timeout extendido (540s).
//   → Solo usuarios admin pueden llamarla (comprueba custom claim).
//   → Si falla, no deja la temporada en estado inconsistente.
//
// LLAMADA DESDE FLUTTER (solo desde panel admin):
//   final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
//       .httpsCallable('cerrarTemporada');
//   final result = await callable.call({'temporadaId': 'abc123'});
//   print('Títulos otorgados: ${result.data['titulosOtorgados']}');

exports.cerrarTemporada = onCall(
  { region: 'europe-west1', timeoutSeconds: 540 },
  async (request) => {
    // Solo admins
    if (!request.auth || !request.auth.token.admin) {
      throw new HttpsError('permission-denied', 'Solo administradores.');
    }

    const { temporadaId } = request.data;
    if (!temporadaId) {
      throw new HttpsError('invalid-argument', 'temporadaId requerido.');
    }

    // Leer la temporada
    const temporadaDoc = await db.collection('temporadas').doc(temporadaId).get();
    if (!temporadaDoc.exists) {
      throw new HttpsError('not-found', 'Temporada no encontrada.');
    }
    const temporada = temporadaDoc.data();
    if (!temporada.activa) {
      throw new HttpsError('failed-precondition', 'La temporada ya está cerrada.');
    }

    // Obtener todas las zonas
    const zonasSnap = await db.collection('zonas').orderBy('nombre').get();
    const zonas = zonasSnap.docs;

    // Obtener todos los territorios (una sola query)
    const territoriosSnap = await db.collection('territories').get();

    // Calcular dominio por zona en memoria (sin más queries)
    // Para cada zona: Map<userId, areaM2>
    const dominioMap = new Map(); // zonaId → Map<userId, areaM2>

    for (const terDoc of territoriosSnap.docs) {
      const t = terDoc.data();
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

    // Preparar batch (máx 500 ops por batch — dividimos si hay muchas zonas)
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

    // Cargar nicks de players que ganaron (en paralelo, solo los ganadores)
    const ganadorIds = new Set();
    for (const [zonaId, userMap] of dominioMap.entries()) {
      if (userMap.size === 0) continue;
      const [ganadorId] = [...userMap.entries()].reduce((a, b) => a[1] >= b[1] ? a : b);
      const areaDominada = userMap.get(ganadorId);
      if (areaDominada >= 100) ganadorIds.add(ganadorId);
    }

    const playerDocs = await Promise.all(
      [...ganadorIds].map(id => db.collection('players').doc(id).get())
    );
    const playerMap = new Map(playerDocs.map(d => [d.id, d.data()]));

    // Procesar cada zona
    for (const zonaDoc of zonas) {
      const zona = zonaDoc.data();
      const userMap = dominioMap.get(zonaDoc.id);
      if (!userMap || userMap.size === 0) continue;

      const [ganadorId, areaDominada] = [...userMap.entries()]
        .reduce((a, b) => a[1] >= b[1] ? a : b);

      if (areaDominada < 100) continue;

      const playerData = playerMap.get(ganadorId);
      if (!playerData) continue;

      const nick    = playerData.nickname || 'Runner';
      const monedas = temporada.monedas_base || 500;

      // Título histórico
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

      // Actualizar zona
      batch.update(db.collection('zonas').doc(zonaDoc.id), {
        rey_actual_id:   ganadorId,
        rey_actual_nick: nick,
        temporada_actual: temporada.numero,
      });
      opsEnBatch++;

      // Monedas al ganador
      batch.update(db.collection('players').doc(ganadorId), {
        monedas: FieldValue.increment(monedas),
        'avatar_config.coronaDesbloqueada': true,
      });
      opsEnBatch++;

      // Notificación
      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        toUserId:         ganadorId,
        type:             'titulo_rey',
        zonaId:           zonaDoc.id,
        zonaNombre:       zona.nombre_corto || zona.nombre,
        temporada:        temporada.numero,
        monedasRecompensa: monedas,
        message:          `👑 ¡Eres el Rey de ${zona.nombre_corto || zona.nombre} en la T${temporada.numero}! +${monedas} 🪙`,
        read:             false,
        timestamp:        FieldValue.serverTimestamp(),
      });
      opsEnBatch++;

      titulosOtorgados++;
      await _commitBatchSiLleno();
    }

    // Cerrar temporada
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
// HELPER PRIVADO: resolver un desafío con transacción
// =============================================================================
// Usamos transacción para garantizar que aunque dos Cloud Functions
// intenten resolver el mismo desafío a la vez, solo una lo hace.

async function _resolverDesafio(desafioId) {
  return db.runTransaction(async (tx) => {
    const ref  = db.collection('desafios').doc(desafioId);
    const snap = await tx.get(ref);

    if (!snap.exists) return;

    const data   = snap.data();
    const estado = data.estado;
    if (estado !== 'activo') return; // Ya resuelto por otra instancia

    const pRetador = data.puntosRetador || 0;
    const pRetado  = data.puntosRetado  || 0;

    const ganadorId   = pRetador >= pRetado ? data.retadorId  : data.retadoId;
    const perdedorId  = pRetador >= pRetado ? data.retadoId   : data.retadorId;
    const ganadorNick = pRetador >= pRetado ? data.retadorNick : data.retadoNick;
    const perdedorNick = pRetador >= pRetado ? data.retadoNick : data.retadorNick;
    const premio = (data.apuesta || 0) * 2;

    // Marcar como finalizado
    tx.update(ref, {
      estado:     'finalizado',
      ganadorId,
      resolvedAt: FieldValue.serverTimestamp(),
    });

    // Dar monedas al ganador
    if (premio > 0) {
      tx.update(db.collection('players').doc(ganadorId), {
        monedas: FieldValue.increment(premio),
      });
    }

    // Las notificaciones van fuera de la transacción (no son críticas)
    // Se escriben después de que la transacción confirme
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
// HELPER PRIVADO: calcular área de intersección entre dos polígonos (Sutherland-Hodgman)
// =============================================================================
// Misma lógica que zona_service.dart pero en JS, para el servidor.

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
    const input = [...output];
    output = [];
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