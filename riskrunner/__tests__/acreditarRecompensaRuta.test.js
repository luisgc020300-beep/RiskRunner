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

const fn = require('../index').acreditarRecompensaRuta;
const { clearEmulatorData, seed, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

beforeEach(() => clearEmulatorData());

describe('acreditarRecompensaRuta – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { routeId: 'r1' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('sin routeId → invalid-argument', async () => {
    await expect(call('u1', {}))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('ruta inexistente → not-found', async () => {
    await expect(call('u1', { routeId: 'noexiste' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  test('ruta de otro usuario → permission-denied', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u2', distanciaKm: 5, ritmoMinKm: 6 });
    await expect(call('u1', { routeId: 'r1' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('ruta ya acreditada → failed-precondition', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', {
      userId: 'u1', distanciaKm: 5, ritmoMinKm: 6, monedas_acreditadas: true,
    });
    await expect(call('u1', { routeId: 'r1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('distancia ausente/0 → failed-precondition', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u1', ritmoMinKm: 6 });
    await expect(call('u1', { routeId: 'r1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('distancia > 100 km → failed-precondition', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u1', distanciaKm: 300, ritmoMinKm: 6 });
    await expect(call('u1', { routeId: 'r1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('acreditarRecompensaRuta – cálculo correcto', () => {
  test('10 km, ritmo normal (>5min/km): 10 × 8 × 1.00 = 80', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u1', distanciaKm: 10, ritmoMinKm: 6 });
    const result = await call('u1', { routeId: 'r1' });
    expect(result).toMatchObject({ ok: true, monedas: 80 });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(80);

    const route = await db().collection('routes').doc('r1').get();
    expect(route.data().monedas_acreditadas).toBe(true);
    expect(route.data().monedasGanadas).toBe(80);
  });

  test('ritmo rápido (<5min/km) aplica el bonus ×1.20: 10 × 8 × 1.20 = 96', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u1', distanciaKm: 10, ritmoMinKm: 4.5 });
    const result = await call('u1', { routeId: 'r1' });
    expect(result.monedas).toBe(96);
  });

  test('sin ritmoMinKm (0) no aplica el bonus', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u1', distanciaKm: 10 });
    const result = await call('u1', { routeId: 'r1' });
    expect(result.monedas).toBe(80);
  });
});

describe('acreditarRecompensaRuta – multiplicadores server-side', () => {
  test('is_premium dobla la recompensa', async () => {
    await seed('players', 'u1', { monedas: 0, is_premium: true });
    await seed('routes', 'r1', { userId: 'u1', distanciaKm: 10, ritmoMinKm: 6 });
    const result = await call('u1', { routeId: 'r1' });
    expect(result.monedas).toBe(160); // 80 × 2
  });
});

describe('acreditarRecompensaRuta – idempotencia', () => {
  test('una segunda llamada sobre la misma ruta falla y no acredita el doble', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('routes', 'r1', { userId: 'u1', distanciaKm: 10, ritmoMinKm: 6 });

    await call('u1', { routeId: 'r1' });
    await expect(call('u1', { routeId: 'r1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(80);
  });
});
