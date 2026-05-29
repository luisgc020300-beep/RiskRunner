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

const fn = require('../index').conquistarTerritorio;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

const TER_LAT = 40.4168;
const TER_LNG = -3.7038;

// Base territory. centroLat/centroLng must match the call coordinates exactly.
const TERRITORY = {
  userId: 'owner',
  nickname: 'Owner',
  centroLat: TER_LAT,
  centroLng: TER_LNG,
  hp: 100,
  hpMax: 100,
  puntos: [
    { lat: 40.4118, lng: -3.7088 },
    { lat: 40.4218, lng: -3.7088 },
    { lat: 40.4218, lng: -3.6988 },
    { lat: 40.4118, lng: -3.6988 },
  ],
};

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data });

beforeEach(() => clearEmulatorData());

describe('conquistarTerritorio – validaciones', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, { docId: 'ter1', latUsuario: TER_LAT, lngUsuario: TER_LNG }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('docId ausente → invalid-argument', async () => {
    await expect(call('u1', { latUsuario: TER_LAT, lngUsuario: TER_LNG }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('coordenadas no numéricas → invalid-argument', async () => {
    await expect(call('u1', { docId: 'ter1', latUsuario: 'abc', lngUsuario: TER_LNG }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('territorio no existe → not-found', async () => {
    await expect(call('u1', { docId: 'noexiste', latUsuario: TER_LAT, lngUsuario: TER_LNG }))
      .rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('conquistarTerritorio – visita propia', () => {
  test('visitar el propio territorio resetea HP y devuelve accion:visita', async () => {
    await seed('territories', 'ter1', { ...TERRITORY, userId: 'u1', hp: 50 });
    await seed('players', 'u1', { nickname: 'Yo' });

    const result = await call('u1', { docId: 'ter1', latUsuario: TER_LAT, lngUsuario: TER_LNG });
    expect(result).toMatchObject({ ok: true, accion: 'visita' });

    const snap = await db().collection('territories').doc('ter1').get();
    expect(snap.data().hp).toBe(100);
  });
});

describe('conquistarTerritorio – restricciones', () => {
  test('territorio visitado hace < 10 días → failed-precondition', async () => {
    await seed('territories', 'ter1', {
      ...TERRITORY,
      ultima_visita: ts(-5 * 86_400_000), // 5 días atrás
    });
    await seed('players', 'u1', { nickname: 'Atacante', clanId: null });

    await expect(call('u1', { docId: 'ter1', latUsuario: TER_LAT, lngUsuario: TER_LNG }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('jugador a > 200 m del centro → failed-precondition', async () => {
    await seed('territories', 'ter1', {
      ...TERRITORY,
      ultima_visita: ts(-15 * 86_400_000), // 15 días atrás
    });
    await seed('players', 'u1', { nickname: 'Atacante', clanId: null });

    // lat 40.5 está ~9 km al norte del centro (40.4168)
    await expect(call('u1', { docId: 'ter1', latUsuario: 40.5, lngUsuario: TER_LNG }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('conquistarTerritorio – conquista exitosa', () => {
  test('conquista cambia el dueño y resetea HP', async () => {
    // Sin ultima_visita → diasSinVisita ≈ epoch days >> 10 → OK
    await seed('territories', 'ter1', { ...TERRITORY });
    await seed('players', 'u1', { nickname: 'Conquistador', clanId: null });

    const result = await call('u1', {
      docId: 'ter1',
      latUsuario: TER_LAT, // mismo punto que centroLat → distancia = 0 m
      lngUsuario: TER_LNG,
    });

    expect(result).toMatchObject({ ok: true, accion: 'conquista' });

    const snap = await db().collection('territories').doc('ter1').get();
    expect(snap.data().userId).toBe('u1');
    expect(snap.data().hp).toBe(100);
    expect(snap.data().nickname).toBe('Conquistador');
  });

  test('conquista con clan suma 25 puntos al clan', async () => {
    await seed('territories', 'ter1', { ...TERRITORY });
    await seed('players', 'u1', { nickname: 'Conquistador', clanId: 'clan1' });
    await seed('clans', 'clan1', { nombre: 'Los Corredores', puntos: 100 });

    await call('u1', { docId: 'ter1', latUsuario: TER_LAT, lngUsuario: TER_LNG });

    const clanSnap = await db().collection('clans').doc('clan1').get();
    expect(clanSnap.data().puntos).toBe(125);
  });
});
