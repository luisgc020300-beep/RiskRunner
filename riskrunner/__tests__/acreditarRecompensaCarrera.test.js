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

const fn = require('../index').acreditarRecompensaCarrera;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

beforeEach(() => clearEmulatorData());

describe('acreditarRecompensaCarrera – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('sin logId → invalid-argument', async () => {
    await expect(call('u1', {}))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('log inexistente → not-found', async () => {
    await expect(call('u1', { logId: 'noexiste' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  test('log de otro usuario → permission-denied', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u2', distancia: 5, modo: 'competitivo', timestamp: ts(-60_000),
    });
    await expect(call('u1', { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('log expirado (> 2h) → failed-precondition', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 5, modo: 'competitivo', timestamp: ts(-3 * 60 * 60 * 1000),
    });
    await expect(call('u1', { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('log ya acreditado → failed-precondition (no se puede cobrar dos veces)', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 5, modo: 'competitivo', timestamp: ts(-60_000),
      monedas_acreditadas: true,
    });
    await expect(call('u1', { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('distancia del log ausente/0 → failed-precondition', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', modo: 'competitivo', timestamp: ts(-60_000),
    });
    await expect(call('u1', { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('distancia del log > 100 km (imposible) → failed-precondition', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 500, modo: 'competitivo', timestamp: ts(-60_000),
    });
    await expect(call('u1', { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('acreditarRecompensaCarrera – cálculo correcto por modo', () => {
  test('modo competitivo: 10 km × 10 monedas/km × factor 1.00 = 100', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result).toMatchObject({ ok: true, monedas: 100 });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(100);

    const log = await db().collection('activity_logs').doc('log1').get();
    expect(log.data().monedas_acreditadas).toBe(true);
  });

  test('modo solitario: 10 km × 10 × factor 0.65 = 65', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'solitario', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(65);
  });

  test('modo ruta: no otorga monedas (factor 0), pero marca el log como usado', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'ruta', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result).toMatchObject({ ok: true, monedas: 0 });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(0);

    const log = await db().collection('activity_logs').doc('log1').get();
    expect(log.data().monedas_acreditadas).toBe(true);
  });

  test('guerra_global cuenta como competitivo (factor 1.00)', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 4, modo: 'guerra_global', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(40);
  });
});

describe('acreditarRecompensaCarrera – multiplicadores server-side, nunca del cliente', () => {
  test('is_premium=true en el jugador dobla la recompensa', async () => {
    await seed('players', 'u1', { monedas: 0, is_premium: true });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(200); // 100 × 2
  });

  test('boost_xp_activo vigente dobla la recompensa', async () => {
    await seed('players', 'u1', {
      monedas: 0, boost_xp_activo: true, boost_xp_expira: ts(600_000),
    });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(200);
  });

  test('boost_xp_activo ya caducado NO dobla la recompensa', async () => {
    await seed('players', 'u1', {
      monedas: 0, boost_xp_activo: true, boost_xp_expira: ts(-600_000),
    });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(100);
  });

  test('premium + boost a la vez multiplica ×4', async () => {
    await seed('players', 'u1', {
      monedas: 0, is_premium: true, boost_xp_activo: true, boost_xp_expira: ts(600_000),
    });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(400);
  });

  test('un campo is_premium falsificado como string "true" no cuenta como premium', async () => {
    await seed('players', 'u1', { monedas: 0, is_premium: 'true' });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });
    const result = await call('u1', { logId: 'log1' });
    expect(result.monedas).toBe(100); // sin el ×2 -- solo 'true' booleano cuenta
  });
});

describe('acreditarRecompensaCarrera – idempotencia', () => {
  test('una segunda llamada sobre el mismo log falla y no acredita el doble', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('activity_logs', 'log1', {
      userId: 'u1', distancia: 10, modo: 'competitivo', timestamp: ts(-60_000),
    });

    await call('u1', { logId: 'log1' });
    await expect(call('u1', { logId: 'log1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(100); // no 200
  });
});
