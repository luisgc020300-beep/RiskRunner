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

const fn = require('../index').coronarRey;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });
const DIA_MS = 24 * 60 * 60 * 1000;

beforeEach(() => clearEmulatorData());

describe('coronarRey – validaciones', () => {
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
    await seed('territories', 'ter-ajeno', {
      userId: 'u2', fecha_desde_dueno: ts(-20 * DIA_MS),
    });
    await expect(call('u1', { docId: 'ter-ajeno' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('ya tiene rey → failed-precondition', async () => {
    await seed('territories', 'ter-conrey', {
      userId: 'u1', fecha_desde_dueno: ts(-20 * DIA_MS), rey_id: 'u1',
    });
    await expect(call('u1', { docId: 'ter-conrey' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('sin fecha_desde_dueno registrada → failed-precondition (no se inventa una fecha)', async () => {
    await seed('territories', 'ter-sinfecha', { userId: 'u1' });
    await expect(call('u1', { docId: 'ter-sinfecha' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('coronarRey – el requisito real es server-side, no decorativo', () => {
  test('menos de 14 días de dominio → failed-precondition, aunque el cliente "ya lo comprobó"', async () => {
    // Este es exactamente el caso que antes se saltaba escribiendo
    // Firestore directamente: el territorio se conquistó HOY.
    await seed('territories', 'ter-reciente', {
      userId: 'u1', nickname: 'Runner1', fecha_desde_dueno: ts(-60_000),
    });
    await expect(call('u1', { docId: 'ter-reciente' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });

    const ter = await db().collection('territories').doc('ter-reciente').get();
    expect(ter.data().rey_id).toBeUndefined();
  });

  test('exactamente 13.9 días → todavía failed-precondition', async () => {
    await seed('territories', 'ter-casi', {
      userId: 'u1', nickname: 'Runner1', fecha_desde_dueno: ts(-13.9 * DIA_MS),
    });
    await expect(call('u1', { docId: 'ter-casi' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('14+ días de dominio → corona correctamente', async () => {
    await seed('territories', 'ter-listo', {
      userId: 'u1', nickname: 'Runner1', fecha_desde_dueno: ts(-15 * DIA_MS),
    });
    const result = await call('u1', { docId: 'ter-listo' });
    expect(result).toMatchObject({ ok: true });

    const ter = await db().collection('territories').doc('ter-listo').get();
    expect(ter.data().rey_id).toBe('u1');
    expect(ter.data().rey_nickname).toBe('Runner1');
    expect(ter.data().rey_desde).toBeDefined();
  });

  test('sin nickname en el territorio, usa un valor por defecto en vez de fallar', async () => {
    await seed('territories', 'ter-sinnick', {
      userId: 'u1', fecha_desde_dueno: ts(-15 * DIA_MS),
    });
    const result = await call('u1', { docId: 'ter-sinnick' });
    expect(result.ok).toBe(true);

    const ter = await db().collection('territories').doc('ter-sinnick').get();
    expect(ter.data().rey_nickname).toBe('Runner');
  });
});

describe('coronarRey – idempotencia', () => {
  test('una segunda coronación del mismo territorio falla', async () => {
    await seed('territories', 'ter-doble', {
      userId: 'u1', nickname: 'Runner1', fecha_desde_dueno: ts(-15 * DIA_MS),
    });
    await call('u1', { docId: 'ter-doble' });
    await expect(call('u1', { docId: 'ter-doble' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});
