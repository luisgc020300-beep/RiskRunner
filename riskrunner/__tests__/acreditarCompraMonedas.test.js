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

const fn = require('../index').acreditarCompraMonedas;
const { clearEmulatorData, seed, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

beforeEach(() => clearEmulatorData());

// transactionId único por test -- el ID del documento es el propio
// transactionId (ver index.js), así que reutilizar el mismo literal entre
// tests de este archivo los deja vulnerables a que clearEmulatorData() no
// haya terminado de propagar su borrado antes de que arranque el siguiente
// (ya visto una vez en acumularPuntosDesafio.test.js).

describe('acreditarCompraMonedas – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { pack: 'coins_patrol', transactionId: 'val-noauth' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('pack inválido (no está en el catálogo) → invalid-argument', async () => {
    await expect(call('u1', { pack: 'coins_gigante_inventado', transactionId: 'val-pack' }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('sin transactionId → invalid-argument', async () => {
    await expect(call('u1', { pack: 'coins_patrol' }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('jugador no existe → not-found', async () => {
    await expect(call('u1', { pack: 'coins_patrol', transactionId: 'val-noplayer' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('acreditarCompraMonedas – catálogo fijo, nunca un valor del cliente', () => {
  test('coins_patrol siempre son 150, aunque no se pida una cantidad', async () => {
    await seed('players', 'u1', { monedas: 0 });
    const result = await call('u1', { pack: 'coins_patrol', transactionId: 'cat-patrol' });
    expect(result).toMatchObject({ ok: true, monedas: 150 });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(150);
  });

  test('coins_commander son 500', async () => {
    await seed('players', 'u1', { monedas: 0 });
    const result = await call('u1', { pack: 'coins_commander', transactionId: 'cat-commander' });
    expect(result.monedas).toBe(500);
  });

  test('coins_legend son 1500', async () => {
    await seed('players', 'u1', { monedas: 0 });
    const result = await call('u1', { pack: 'coins_legend', transactionId: 'cat-legend' });
    expect(result.monedas).toBe(1500);
  });

  test('un intento de pasar una cantidad extra en el payload se ignora', async () => {
    await seed('players', 'u1', { monedas: 0 });
    const result = await call('u1', { pack: 'coins_patrol', transactionId: 'cat-ignorecantidad', cantidad: 999999 });
    expect(result.monedas).toBe(150);
  });
});

describe('acreditarCompraMonedas – anti-repetición por transactionId', () => {
  test('el mismo transactionId no puede acreditarse dos veces', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await call('u1', { pack: 'coins_patrol', transactionId: 'rep-doble' });
    await expect(call('u1', { pack: 'coins_patrol', transactionId: 'rep-doble' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(150); // no 300
  });

  test('el mismo transactionId no puede reclamarse desde otra cuenta', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('players', 'u2', { monedas: 0 });
    await call('u1', { pack: 'coins_patrol', transactionId: 'rep-otracuenta' });
    await expect(call('u2', { pack: 'coins_patrol', transactionId: 'rep-otracuenta' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });

    const u2 = await db().collection('players').doc('u2').get();
    expect(u2.data().monedas).toBe(0);
  });

  test('transactionId distintos sí acreditan por separado', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await call('u1', { pack: 'coins_patrol', transactionId: 'rep-distinto-a' });
    await call('u1', { pack: 'coins_patrol', transactionId: 'rep-distinto-b' });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(300);
  });
});
