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

const fn = require('../index').conquistarTerritorioGlobal;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

const GLOBAL_TERRITORY = {
  nombre: 'Monte Perdido',
  epicName: 'El Pico de la Muerte',
  ownerUid: null,
  clausulaKm: 5,
  baseKm: 5,
  conquestCount: 0,
  tier: 'mediano',
  baseReward: 50,
};

const VALID_LOG = {
  userId: 'u1',
  distancia: 10, // 10 km > clausulaKm (5)
  usado_conquista_global: false,
  // timestamp reciente (hace 10 minutos)
};

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data });

beforeEach(() => clearEmulatorData());

describe('conquistarTerritorioGlobal – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { territorioId: 'gt1', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('territorioId ausente → invalid-argument', async () => {
    await expect(call('u1', { activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('activityLogId ausente → invalid-argument', async () => {
    await expect(call('u1', { territorioId: 'gt1' }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('territorio global no existe → not-found', async () => {
    await seed('activity_logs', 'log1', { ...VALID_LOG, timestamp: ts(-600_000) });
    await expect(call('u1', { territorioId: 'noexiste', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  test('activity log no existe → not-found', async () => {
    await seed('global_territories', 'gt1', GLOBAL_TERRITORY);
    await expect(call('u1', { territorioId: 'gt1', activityLogId: 'noexiste' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('conquistarTerritorioGlobal – anti-cheat del log', () => {
  beforeEach(async () => {
    await seed('global_territories', 'gt1', GLOBAL_TERRITORY);
    await seed('players', 'u1', { nickname: 'Corredor', global_territories_count: 0 });
  });

  test('log de otro usuario → permission-denied', async () => {
    await seed('activity_logs', 'log1', {
      ...VALID_LOG,
      userId: 'u_otro', // no es u1
      timestamp: ts(-600_000),
    });
    await expect(call('u1', { territorioId: 'gt1', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('log expirado (> 2h) → failed-precondition', async () => {
    await seed('activity_logs', 'log1', {
      ...VALID_LOG,
      timestamp: ts(-3 * 3_600_000), // hace 3 horas
    });
    await expect(call('u1', { territorioId: 'gt1', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('log ya usado → failed-precondition', async () => {
    await seed('activity_logs', 'log1', {
      ...VALID_LOG,
      timestamp: ts(-600_000),
      usado_conquista_global: true,
    });
    await expect(call('u1', { territorioId: 'gt1', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('km insuficientes (< clausulaKm) → failed-precondition', async () => {
    await seed('activity_logs', 'log1', {
      ...VALID_LOG,
      distancia: 3, // 3 km < clausulaKm (5)
      timestamp: ts(-600_000),
    });
    await expect(call('u1', { territorioId: 'gt1', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('ya eres el dueño → failed-precondition', async () => {
    await seed('global_territories', 'gt_owned', { ...GLOBAL_TERRITORY, ownerUid: 'u1' });
    await seed('activity_logs', 'log1', { ...VALID_LOG, timestamp: ts(-600_000) });
    await expect(call('u1', { territorioId: 'gt_owned', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('límite de 5 territorios globales → failed-precondition', async () => {
    await seed('players', 'u1', { nickname: 'Corredor', global_territories_count: 5 });
    await seed('activity_logs', 'log1', { ...VALID_LOG, timestamp: ts(-600_000) });
    await expect(call('u1', { territorioId: 'gt1', activityLogId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('conquistarTerritorioGlobal – conquista exitosa', () => {
  beforeEach(async () => {
    await seed('global_territories', 'gt1', GLOBAL_TERRITORY);
    await seed('players', 'u1', { nickname: 'Corredor', global_territories_count: 0 });
    await seed('activity_logs', 'log1', { ...VALID_LOG, timestamp: ts(-600_000) });
  });

  test('conquista exitosa devuelve ok:true con la nueva cláusula', async () => {
    const result = await call('u1', { territorioId: 'gt1', activityLogId: 'log1' });
    expect(result.ok).toBe(true);
    // nuevaClausula = 10 km * 1.15 = 11.5 km
    expect(result.nuevaClausula).toBeCloseTo(11.5, 1);
    expect(result.territorioNombre).toBe('El Pico de la Muerte');
  });

  test('el territorio queda con el nuevo dueño en Firestore', async () => {
    await call('u1', { territorioId: 'gt1', activityLogId: 'log1' });
    const snap = await db().collection('global_territories').doc('gt1').get();
    expect(snap.data().ownerUid).toBe('u1');
    expect(snap.data().clausulaKm).toBeCloseTo(11.5, 1);
  });

  test('el log queda marcado como usado', async () => {
    await call('u1', { territorioId: 'gt1', activityLogId: 'log1' });
    const snap = await db().collection('activity_logs').doc('log1').get();
    expect(snap.data().usado_conquista_global).toBe(true);
  });

  test('global_territories_count del jugador aumenta en 1', async () => {
    await call('u1', { territorioId: 'gt1', activityLogId: 'log1' });
    const snap = await db().collection('players').doc('u1').get();
    expect(snap.data().global_territories_count).toBe(1);
  });

  test('el contador del dueño anterior disminuye', async () => {
    await seed('global_territories', 'gt2', { ...GLOBAL_TERRITORY, ownerUid: 'u_anterior' });
    await seed('players', 'u_anterior', { nickname: 'Ex-dueño', global_territories_count: 2 });
    await seed('activity_logs', 'log2', { ...VALID_LOG, timestamp: ts(-600_000) });

    await call('u1', { territorioId: 'gt2', activityLogId: 'log2' });

    const snap = await db().collection('players').doc('u_anterior').get();
    expect(snap.data().global_territories_count).toBe(1); // 2 - 1
  });

  test('el contador del dueño anterior NO baja de 0 (anti-underflow)', async () => {
    await seed('global_territories', 'gt3', { ...GLOBAL_TERRITORY, ownerUid: 'u_sin_count' });
    // Jugador antiguo sin el campo → count efectivo = 0
    await seed('players', 'u_sin_count', { nickname: 'Antiguo' });
    await seed('activity_logs', 'log3', { ...VALID_LOG, timestamp: ts(-600_000) });

    await call('u1', { territorioId: 'gt3', activityLogId: 'log3' });

    const snap = await db().collection('players').doc('u_sin_count').get();
    // No debe haberse decrementado (ya era 0 o no existía)
    const count = snap.data()?.global_territories_count ?? 0;
    expect(count).toBeGreaterThanOrEqual(0);
  });
});
