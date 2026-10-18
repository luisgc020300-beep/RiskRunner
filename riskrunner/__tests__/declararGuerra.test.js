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

const fn = require('../index').declararGuerra;
const { clearEmulatorData, seed, db } = require('./helpers');

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data: data ?? {} });

// declararGuerra consulta TODA la colección clan_wars (where estado==activa)
// para comprobar duplicados -- a diferencia de una lectura por ID, esa
// query ve cualquier documento que quede de un test anterior sin importar
// su ID, así que reutilizar el mismo par de IDs de clan entre tests de
// este archivo es exactamente el escenario que puede contaminarse si
// clearEmulatorData() no ha terminado de propagar su borrado. Cada test
// que llega a crear una guerra usa su propio par de clanes único.
function clanA(sufijo, miembros) {
  return { nombre: 'Lobos', tag: 'LOB', color: 0xFFCC2222, emoji: '🐺', miembros };
}
function clanB(sufijo) {
  return {
    nombre: 'Águilas', tag: 'AGL', color: 0xFF2255CC, emoji: '🦅',
    miembros: [{ uid: `u2-${sufijo}`, nickname: 'U2', rol: 'lider' }],
  };
}

beforeEach(() => clearEmulatorData());

describe('declararGuerra – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { miClanId: 'a', rivalClanId: 'b', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('rivalClanId igual a miClanId → invalid-argument', async () => {
    await expect(call('lider1', { miClanId: 'a', rivalClanId: 'a', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('tipo inválido → invalid-argument', async () => {
    await expect(call('lider1', { miClanId: 'a', rivalClanId: 'b', tipo: 'inventado', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('duracionHoras fuera de rango (< 24) → invalid-argument', async () => {
    await expect(call('lider1', { miClanId: 'a', rivalClanId: 'b', tipo: 'conquista', duracionHoras: 10 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('duracionHoras fuera de rango (> 168) → invalid-argument', async () => {
    await expect(call('lider1', { miClanId: 'a', rivalClanId: 'b', tipo: 'conquista', duracionHoras: 200 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('mi clan no existe → not-found', async () => {
    await seed('clans', 'val-b', clanB('val'));
    await expect(call('lider1', { miClanId: 'noexiste', rivalClanId: 'val-b', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  test('clan rival no existe → not-found', async () => {
    await seed('clans', 'val-a', clanA('val', [{ uid: 'lider1', nickname: 'L', rol: 'lider' }]));
    await expect(call('lider1', { miClanId: 'val-a', rivalClanId: 'noexiste', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('declararGuerra – el rol se revalida en servidor, no solo en el cliente', () => {
  test('un miembro normal (no líder/capitán) no puede declarar guerra', async () => {
    await seed('clans', 'rol-a1', clanA('rol1', [
      { uid: 'lider1', nickname: 'L', rol: 'lider' },
      { uid: 'miembro1', nickname: 'M', rol: 'miembro' },
    ]));
    await seed('clans', 'rol-b1', clanB('rol1'));
    // Este es exactamente el caso que antes se saltaba escribiendo
    // Firestore directamente, sin pasar por el chequeo del cliente.
    await expect(call('miembro1', { miClanId: 'rol-a1', rivalClanId: 'rol-b1', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('alguien que ni siquiera es miembro del clan no puede declarar en su nombre', async () => {
    await seed('clans', 'rol-a2', clanA('rol2', [{ uid: 'lider1', nickname: 'L', rol: 'lider' }]));
    await seed('clans', 'rol-b2', clanB('rol2'));
    await expect(call('extraño', { miClanId: 'rol-a2', rivalClanId: 'rol-b2', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('un capitán sí puede declarar guerra', async () => {
    await seed('clans', 'rol-a3', clanA('rol3', [{ uid: 'capitan1', nickname: 'C', rol: 'capitan' }]));
    await seed('clans', 'rol-b3', clanB('rol3'));
    const result = await call('capitan1', { miClanId: 'rol-a3', rivalClanId: 'rol-b3', tipo: 'conquista', duracionHoras: 48 });
    expect(result.ok).toBe(true);
  });

  test('el líder sí puede declarar guerra, y el documento queda con el formato correcto', async () => {
    await seed('clans', 'rol-a4', clanA('rol4', [{ uid: 'lider1', nickname: 'L', rol: 'lider' }]));
    await seed('clans', 'rol-b4', clanB('rol4'));
    const result = await call('lider1', { miClanId: 'rol-a4', rivalClanId: 'rol-b4', tipo: 'asedio', duracionHoras: 72 });
    expect(result.ok).toBe(true);

    const war = await db().collection('clan_wars').doc(result.warId).get();
    const data = war.data();
    expect(data.estado).toBe('activa');
    expect(data.clanA).toMatchObject({ id: 'rol-a4', nombre: 'Lobos', tag: 'LOB' });
    expect(data.clanB).toMatchObject({ id: 'rol-b4', nombre: 'Águilas', tag: 'AGL' });
    expect(data.puntuacion).toEqual({ clanA: 0, clanB: 0 });
    expect(data.ganadorId).toBeNull();
    expect(data.creatorUid).toBe('lider1');
    expect(data.tipo).toBe('asedio');
  });
});

describe('declararGuerra – no se pueden duplicar guerras activas entre el mismo par de clanes', () => {
  test('segunda declaración entre los mismos dos clanes mientras la primera sigue activa → failed-precondition', async () => {
    await seed('clans', 'dup-a1', clanA('dup1', [{ uid: 'lider1', nickname: 'L', rol: 'lider' }]));
    await seed('clans', 'dup-b1', clanB('dup1'));
    await call('lider1', { miClanId: 'dup-a1', rivalClanId: 'dup-b1', tipo: 'conquista', duracionHoras: 48 });
    await expect(call('lider1', { miClanId: 'dup-a1', rivalClanId: 'dup-b1', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('también se bloquea en el sentido inverso (B declara sobre A ya en guerra)', async () => {
    await seed('clans', 'dup-a2', clanA('dup2', [{ uid: 'lider1', nickname: 'L', rol: 'lider' }]));
    await seed('clans', 'dup-b2', clanB('dup2'));
    await call('lider1', { miClanId: 'dup-a2', rivalClanId: 'dup-b2', tipo: 'conquista', duracionHoras: 48 });
    await expect(call('u2-dup2', { miClanId: 'dup-b2', rivalClanId: 'dup-a2', tipo: 'conquista', duracionHoras: 48 }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});
