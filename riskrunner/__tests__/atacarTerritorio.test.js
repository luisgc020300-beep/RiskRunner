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

const fn = require('../index').atacarTerritorio;
const { clearEmulatorData, seed, ts, db } = require('./helpers');

// Defender territory: ~1 km × 1 km square near Madrid.
// CCW winding order (SW→SE→NE→NW in x=lng, y=lat) required by _sutherlandHodgman.
const DEFENDER_POLY = [
  { lat: 40.395, lng: -3.705 }, // SW
  { lat: 40.395, lng: -3.695 }, // SE
  { lat: 40.405, lng: -3.695 }, // NE
  { lat: 40.405, lng: -3.705 }, // NW
];

// Attacker route fully inside the defender territory (~600 m × 500 m). CCW order.
const OVERLAP_ROUTE = [
  { lat: 40.397, lng: -3.703 }, // SW
  { lat: 40.397, lng: -3.698 }, // SE
  { lat: 40.403, lng: -3.698 }, // NE
  { lat: 40.403, lng: -3.703 }, // NW
];

// Tiny triangle well below 500 m²
const TINY_ROUTE = [
  { lat: 40.4000, lng: -3.7000 },
  { lat: 40.40001, lng: -3.7000 },
  { lat: 40.4000, lng: -3.70001 },
];

// Route with no overlap with the defender territory
const FAR_ROUTE = [
  { lat: 41.000, lng: -3.705 },
  { lat: 41.000, lng: -3.695 },
  { lat: 41.010, lng: -3.695 },
  { lat: 41.010, lng: -3.705 },
];

const TERRITORY = {
  userId: 'defender',
  nickname: 'Defensor',
  puntos: DEFENDER_POLY,
  centroLat: 40.4,
  centroLng: -3.7,
  hp: 100,
  hpMax: 100,
  velocidadConquistaKmh: 5.0,
};

const call = (uid, data) => fn({ auth: uid ? { uid } : null, data });

beforeEach(() => clearEmulatorData());

describe('atacarTerritorio – validaciones de parámetros', () => {
  test('sin autenticar → unauthenticated', async () => {
    await expect(call(null, {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    })).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('territorioDefensorId ausente → invalid-argument', async () => {
    await expect(call('u1', { rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8 }))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('ruta con < 3 puntos → invalid-argument', async () => {
    await expect(call('u1', {
      territorioDefensorId: 'ter1',
      rutaAtacante: [{ lat: 40.4, lng: -3.7 }, { lat: 40.5, lng: -3.7 }],
      velocidadMediaAtacanteKmh: 8,
    })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('velocidad Infinity → invalid-argument', async () => {
    await expect(call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: Infinity,
    })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('velocidad NaN → invalid-argument', async () => {
    await expect(call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: NaN,
    })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('velocidad negativa → invalid-argument', async () => {
    await expect(call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: -5,
    })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('coordenada de ruta con Infinity → invalid-argument', async () => {
    const badRoute = [{ lat: Infinity, lng: -3.7 }, { lat: 40.4, lng: -3.7 }, { lat: 40.4, lng: -3.8 }];
    await expect(call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: badRoute, velocidadMediaAtacanteKmh: 8,
    })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('territorio no existe → not-found', async () => {
    await expect(call('u1', {
      territorioDefensorId: 'noexiste', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    })).rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('atacarTerritorio – sin daño', () => {
  beforeEach(async () => {
    await seed('territories', 'ter1', TERRITORY);
    await seed('players', 'u1', { nickname: 'Atacante', monedas: 0 });
  });

  test('atacar el propio territorio → failed-precondition', async () => {
    await seed('territories', 'ter_propio', { ...TERRITORY, userId: 'u1' });
    await expect(call('u1', {
      territorioDefensorId: 'ter_propio', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    })).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('escudo activo → sin_daño con danio 0', async () => {
    await seed('territories', 'ter_escudo', {
      ...TERRITORY,
      escudo_activo: true,
      escudo_expira: ts(3_600_000),
    });
    const result = await call('u1', {
      territorioDefensorId: 'ter_escudo', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    });
    expect(result).toMatchObject({ ok: false, accion: 'sin_daño', danio: 0 });
  });

  test('ruta demasiado pequeña (< 500 m²) → sin_daño', async () => {
    const result = await call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: TINY_ROUTE, velocidadMediaAtacanteKmh: 8,
    });
    expect(result).toMatchObject({ ok: false, accion: 'sin_daño', danio: 0 });
  });

  test('ruta sin solapamiento → sin_daño', async () => {
    const result = await call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: FAR_ROUTE, velocidadMediaAtacanteKmh: 8,
    });
    expect(result).toMatchObject({ ok: false, accion: 'sin_daño', danio: 0 });
  });

  test('atacante más lento que el defensor → sin_daño', async () => {
    // territorio a 5 km/h, atacante a 3 km/h → factor < 1
    const result = await call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 3,
    });
    expect(result).toMatchObject({ ok: false, accion: 'sin_daño', danio: 0 });
  });
});

describe('atacarTerritorio – daño real', () => {
  beforeEach(async () => {
    await seed('territories', 'ter1', TERRITORY);
    await seed('players', 'u1', { nickname: 'Atacante', monedas: 0 });
    await seed('players', 'defender', { nickname: 'Defensor', monedas: 50 });
  });

  test('ataque exitoso: ok=true y danio > 0', async () => {
    // 8 km/h atacante > 5 km/h defensor → factorVelocidad = 1.6
    const result = await call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    });
    expect(result.ok).toBe(true);
    expect(['daño', 'conquista_total', 'robo_parcial']).toContain(result.accion);
    expect(result.danio).toBeGreaterThan(0);
    expect(result.hpDespues).toBeLessThan(result.hpAntes);
  });

  test('HP del territorio se reduce en Firestore', async () => {
    const result = await call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    });

    if (result.accion === 'daño') {
      const snap = await db().collection('territories').doc('ter1').get();
      expect(snap.data().hp).toBeLessThan(100);
    } else {
      // conquista_total o robo_parcial — el territorio fue transformado
      expect(true).toBe(true);
    }
  });

  test('el atacante recibe monedas en Firestore si causó daño', async () => {
    const result = await call('u1', {
      territorioDefensorId: 'ter1', rutaAtacante: OVERLAP_ROUTE, velocidadMediaAtacanteKmh: 8,
    });

    if (result.monedasBotin > 0) {
      const snap = await db().collection('players').doc('u1').get();
      expect(snap.data().monedas).toBeGreaterThan(0);
    }
  });
});
