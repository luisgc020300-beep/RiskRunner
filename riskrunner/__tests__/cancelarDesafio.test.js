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

const fn = require('../index').cancelarDesafio;
const { clearEmulatorData, seed, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

beforeEach(() => clearEmulatorData());

describe('cancelarDesafio – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { desafioId: 'x' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('sin desafioId → invalid-argument', async () => {
    await expect(call('u1', {}))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('desafío inexistente → not-found', async () => {
    await expect(call('u1', { desafioId: 'no-existe' }))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  test('usuario ajeno al desafío → permission-denied', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'pendiente', apuesta: 50,
    });
    await expect(call('u3', { desafioId: 'd1' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('desafío ya activo → failed-precondition (no se puede cancelar lo ya aceptado)', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'activo', apuesta: 50,
    });
    await expect(call('u1', { desafioId: 'd1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('cancelarDesafio – caso legítimo: el propio retador cancela', () => {
  test('reembolsa la apuesta al retador y marca estado=cancelado', async () => {
    await seed('players', 'u1', { monedas: 100 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'pendiente', apuesta: 50,
    });

    const result = await call('u1', { desafioId: 'd1' });
    expect(result).toMatchObject({ ok: true, estado: 'cancelado' });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(150); // 100 + 50 reembolsados

    const desafio = await db().collection('desafios').doc('d1').get();
    expect(desafio.data().estado).toBe('cancelado');
  });
});

describe('cancelarDesafio – caso legítimo: el retado rechaza', () => {
  test('reembolsa al retador (no a quien rechaza) y marca estado=rechazado', async () => {
    // Este es el caso que antes fallaba con permission-denied en el cliente:
    // quien rechaza (u2) no es dueño del documento players/u1 que hay que
    // acreditar -- solo una Cloud Function con el Admin SDK puede hacerlo.
    await seed('players', 'u1', { monedas: 0 });
    await seed('players', 'u2', { monedas: 0 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'pendiente', apuesta: 50,
    });

    const result = await call('u2', { desafioId: 'd1' });
    expect(result).toMatchObject({ ok: true, estado: 'rechazado' });

    const retador = await db().collection('players').doc('u1').get();
    expect(retador.data().monedas).toBe(50); // recupera su apuesta

    const retado = await db().collection('players').doc('u2').get();
    expect(retado.data().monedas).toBe(0); // quien rechaza no recibe nada

    const desafio = await db().collection('desafios').doc('d1').get();
    expect(desafio.data().estado).toBe('rechazado');
  });
});

describe('cancelarDesafio – contrapropuesta en curso', () => {
  test('cortar una contrapropuesta reembolsa el importe propuesto, no el original', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'contrapropuesta',
      apuesta: 50, propuestaApuesta: 80, contrapropuestaDeId: 'u2',
    });

    const result = await call('u1', { desafioId: 'd1' });
    expect(result).toMatchObject({ ok: true, estado: 'cancelado' });

    const retador = await db().collection('players').doc('u1').get();
    expect(retador.data().monedas).toBe(80); // el importe propuesto, no los 50 originales
  });

  test('cualquiera de los dos participantes puede cortar la contrapropuesta', async () => {
    await seed('players', 'u1', { monedas: 0 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'contrapropuesta',
      apuesta: 50, propuestaApuesta: 80, contrapropuestaDeId: 'u1',
    });

    const result = await call('u2', { desafioId: 'd1' });
    expect(result).toMatchObject({ ok: true, estado: 'cancelado' });
  });
});

describe('cancelarDesafio – idempotencia / doble llamada', () => {
  test('una segunda cancelación del mismo desafío ya resuelto falla, no reembolsa dos veces', async () => {
    await seed('players', 'u1', { monedas: 100 });
    await seed('desafios', 'd1', {
      retadorId: 'u1', retadoId: 'u2', estado: 'pendiente', apuesta: 50,
    });

    await call('u1', { desafioId: 'd1' });
    await expect(call('u1', { desafioId: 'd1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });

    const player = await db().collection('players').doc('u1').get();
    expect(player.data().monedas).toBe(150); // no 200 -- el segundo intento no debe sumar nada
  });
});
