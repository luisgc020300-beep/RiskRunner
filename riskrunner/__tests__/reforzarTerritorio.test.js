jest.mock('firebase-functions/v2/scheduler', () => ({ onSchedule: () => null }));
jest.mock('firebase-functions/v2/firestore', () => ({
  onDocumentCreated: () => null,
  onDocumentUpdated: () => null,
}));
jest.mock('firebase-functions/v2/https', () => ({
  onCall: (optsOrFn, fn) => (typeof optsOrFn === 'function' ? optsOrFn : fn),
  onRequest: () => null,
  HttpsError: class HttpsError extends Error {
    constructor(code, msg) { super(msg); this.code = code; }
  },
}));

const fn = require('../index').reforzarTerritorio;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

beforeEach(() => clearEmulatorData());

describe('reforzarTerritorio – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { docId: 'ter-noauth' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('sin docId → invalid-argument', async () => {
    await expect(call('u1', {}))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('territorio no existe → not-found', async () => {
    await expect(call('u1', { docId: 'noexiste' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  test('territorio de otro usuario → permission-denied', async () => {
    await seed('territories', 'ter-ajeno', { userId: 'u2', hp: 20 });
    await expect(call('u1', { docId: 'ter-ajeno' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });
});

describe('reforzarTerritorio – escalado de HP (no un valor arbitrario)', () => {
  test('HP leve (< 30) sube a 30, no a 100', async () => {
    await seed('territories', 'ter-leve', {
      userId: 'u1', hp: 10, ultimaActualizacionHp: ts(-3_600_000),
    });
    const result = await call('u1', { docId: 'ter-leve' });
    expect(result).toMatchObject({ ok: true, hp: 30 });

    const ter = await db().collection('territories').doc('ter-leve').get();
    expect(ter.data().hp).toBe(30);
  });

  test('HP medio (30-69) sube a 100', async () => {
    await seed('territories', 'ter-medio', {
      userId: 'u1', hp: 50, ultimaActualizacionHp: ts(-3_600_000),
    });
    const result = await call('u1', { docId: 'ter-medio' });
    expect(result.hp).toBe(100);
  });

  test('HP ya fuerte (70-100) se queda en 100', async () => {
    await seed('territories', 'ter-fuerte', {
      userId: 'u1', hp: 90, ultimaActualizacionHp: ts(-3_600_000),
    });
    const result = await call('u1', { docId: 'ter-fuerte' });
    expect(result.hp).toBe(100);
  });

  test('sin campo hp (territorio legacy) se trata como HP_MAX antes de decaer', async () => {
    await seed('territories', 'ter-legacy', {
      userId: 'u1', ultima_visita: ts(-60_000),
    });
    const result = await call('u1', { docId: 'ter-legacy' });
    expect(result.hp).toBe(100);
  });

  test('un territorio decaído durante semanas nunca llega a 0 -- se trata como 1 (leve) y sube a 30', async () => {
    // P0.7: "los territorios nunca mueren" -- el decaimiento por tiempo
    // nunca debe dejar el HP en 0, solo un ataque real puede hacer eso.
    await seed('territories', 'ter-abandonado', {
      userId: 'u1', hp: 100, ultimaActualizacionHp: ts(-30 * 24 * 60 * 60 * 1000), // 30 días
    });
    const result = await call('u1', { docId: 'ter-abandonado' });
    expect(result.hp).toBe(30); // hpAntes se trató como 1 (leve), no 0
  });
});

describe('reforzarTerritorio – cooldown anti-spam', () => {
  test('una segunda llamada inmediata se bloquea con resource-exhausted', async () => {
    await seed('territories', 'ter-cooldown', {
      userId: 'u1', hp: 10, ultimaActualizacionHp: ts(-3_600_000),
    });
    await call('u1', { docId: 'ter-cooldown' });
    await expect(call('u1', { docId: 'ter-cooldown' }))
      .rejects.toMatchObject({ code: 'resource-exhausted' });

    const ter = await db().collection('territories').doc('ter-cooldown').get();
    expect(ter.data().hp).toBe(30); // no subió una segunda vez
  });

  test('pasado el cooldown, una nueva llamada sí funciona', async () => {
    await seed('territories', 'ter-pasado', {
      userId: 'u1', hp: 10, ultimaActualizacionHp: ts(-120_000), // hace 2 min, cooldown es 1 min
    });
    const result = await call('u1', { docId: 'ter-pasado' });
    expect(result.ok).toBe(true);
  });
});
