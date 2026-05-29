jest.mock('firebase-functions/v2/scheduler', () => ({ onSchedule: () => null }));
jest.mock('firebase-functions/v2/firestore', () => ({
  onDocumentCreated: () => null,
  onDocumentUpdated: () => null,
}));
jest.mock('firebase-functions/v2/https', () => ({
  onCall: (optsOrFn, fn) => (typeof optsOrFn === 'function' ? optsOrFn : fn),
  HttpsError: class HttpsError extends Error {
    constructor(code, msg) { super(msg); this.code = code; }
  },
}));

const fn = require('../index').acumularPuntosDesafio;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

beforeEach(() => clearEmulatorData());

describe('acumularPuntosDesafio – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { distanciaKm: 5, territoriosConquistados: 1 }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('distanciaKm negativa → invalid-argument', async () => {
    await expect(call('u1', { distanciaKm: -1, territoriosConquistados: 0 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('distanciaKm > 100 → invalid-argument', async () => {
    await expect(call('u1', { distanciaKm: 101, territoriosConquistados: 0 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('territoriosConquistados > 200 → invalid-argument', async () => {
    await expect(call('u1', { distanciaKm: 5, territoriosConquistados: 201 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('jugador no existe → not-found', async () => {
    await expect(call('nobody', { distanciaKm: 5, territoriosConquistados: 1 }))
      .rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('acumularPuntosDesafio – cooldown global', () => {
  test('llamada < 30s desde la anterior → resource-exhausted', async () => {
    await seed('players', 'u1', { ultimaLlamadaAcumular: ts(-5_000) }); // 5s atrás
    await expect(call('u1', { distanciaKm: 5, territoriosConquistados: 1 }))
      .rejects.toMatchObject({ code: 'resource-exhausted' });
  });

  test('llamada > 30s después → pasa el cooldown', async () => {
    await seed('players', 'u1', { ultimaLlamadaAcumular: ts(-60_000) }); // 60s atrás
    const result = await call('u1', { distanciaKm: 5, territoriosConquistados: 1 });
    // Sin desafíos activos devuelve 0 (pero no lanza error)
    expect(result).toMatchObject({ puntosAcumulados: 0, desafiosActualizados: 0 });
  });
});

describe('acumularPuntosDesafio – acumulación real', () => {
  test('sin desafíos activos devuelve 0', async () => {
    await seed('players', 'u1', { ultimaLlamadaAcumular: ts(-60_000) });
    const result = await call('u1', { distanciaKm: 5, territoriosConquistados: 1 });
    expect(result).toMatchObject({ puntosAcumulados: 0, desafiosActualizados: 0 });
  });

  test('acumula como retador: puntos = territorios×10 + km×5', async () => {
    await seed('players', 'u1', { ultimaLlamadaAcumular: ts(-60_000) });
    await seed('desafios', 'des1', {
      retadorId: 'u1', retadoId: 'u2',
      estado: 'activo',
      fin: ts(3_600_000),
      puntosRetador: 0, puntosRetado: 0,
    });

    // puntos = round(2×10 + 5×5) = 45
    const result = await call('u1', { distanciaKm: 5, territoriosConquistados: 2 });
    expect(result).toMatchObject({ puntosAcumulados: 45, desafiosActualizados: 1 });

    const snap = await db().collection('desafios').doc('des1').get();
    expect(snap.data().puntosRetador).toBe(45);
  });

  test('acumula como retado y suma sobre puntos previos', async () => {
    await seed('players', 'u2', { ultimaLlamadaAcumular: ts(-60_000) });
    await seed('desafios', 'des2', {
      retadorId: 'u1', retadoId: 'u2',
      estado: 'activo',
      fin: ts(3_600_000),
      puntosRetador: 100, puntosRetado: 20,
    });

    // puntos = round(1×10 + 3×5) = 25
    const result = await call('u2', { distanciaKm: 3, territoriosConquistados: 1 });
    expect(result.puntosAcumulados).toBe(25);

    const snap = await db().collection('desafios').doc('des2').get();
    expect(snap.data().puntosRetado).toBe(45); // 20 + 25
  });

  test('cooldown por desafío previene doble acumulación', async () => {
    await seed('players', 'u1', { ultimaLlamadaAcumular: ts(-60_000) });
    await seed('desafios', 'des3', {
      retadorId: 'u1', retadoId: 'u2',
      estado: 'activo',
      fin: ts(3_600_000),
      puntosRetador: 0,
      ultimaAcumRetador: ts(-30_000), // cooldown por desafío activo (< 1 min)
    });

    const result = await call('u1', { distanciaKm: 5, territoriosConquistados: 2 });
    expect(result.desafiosActualizados).toBe(0);
  });
});
