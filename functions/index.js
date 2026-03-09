const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// =============================================================================
// FUNCIÓN 1: Notificación cuando se conquista un territorio
// =============================================================================
exports.notificarConquista = onDocumentUpdated(
  "territories/{territoryId}",
  async (event) => {
    const antes = event.data.before.data();
    const despues = event.data.after.data();

    if (antes.userId === despues.userId) return null;

    const duenoAnteriorId = antes.userId;
    const nuevoDuenoId = despues.userId;

    if (!duenoAnteriorId || !nuevoDuenoId) return null;

    try {
      const invasorDoc = await db.collection("players").doc(nuevoDuenoId).get();
      const invasorNickname = invasorDoc.data()?.nickname || "Un rival";

      const duenoDoc = await db.collection("players").doc(duenoAnteriorId).get();
      const fcmToken = duenoDoc.data()?.fcm_token;

      if (!fcmToken) {
        console.log(`Sin FCM token para usuario ${duenoAnteriorId}`);
        return null;
      }

      const nombreZona = despues.nombre || `zona ${event.params.territoryId.substring(0, 6)}`;

      await db.collection("notifications").add({
        userId: duenoAnteriorId,
        titulo: "⚔️ ¡Tu territorio ha sido invadido!",
        cuerpo: `${invasorNickname} ha conquistado tu zona en ${nombreZona}`,
        tipo: "invasion",
        leida: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        data: {
          tipo: "invasion",
          invasorNombre: invasorNickname,
          zona: nombreZona,
          territoryId: event.params.territoryId,
        },
      });

      await messaging.send({
        token: fcmToken,
        notification: {
          title: "⚔️ ¡Tu territorio ha sido invadido!",
          body: `${invasorNickname} ha conquistado tu zona en ${nombreZona}`,
        },
        data: {
          tipo: "invasion",
          invasorNombre: invasorNickname,
          zona: nombreZona,
          territoryId: event.params.territoryId,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "runner_risk_invasions",
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: { sound: "default", badge: 1 },
          },
        },
      });

      console.log(`✅ Notificación de invasión enviada a ${duenoAnteriorId}`);
      return null;
    } catch (error) {
      console.error("❌ Error en notificarConquista:", error);
      return null;
    }
  }
);

// =============================================================================
// FUNCIÓN 2: Notificación de deterioro — todos los días a las 9:00 AM
// =============================================================================
exports.notificarDeterioros = onSchedule(
  { schedule: "0 9 * * *", timeZone: "Europe/Madrid" },
  async () => {
    try {
      const ahora = new Date();
      const hace5dias = new Date(ahora.getTime() - 5 * 24 * 60 * 60 * 1000);
      const hace6dias = new Date(ahora.getTime() - 6 * 24 * 60 * 60 * 1000);

      const snap = await db.collection("territories")
        .where("ultima_visita", "<=", admin.firestore.Timestamp.fromDate(hace5dias))
        .where("ultima_visita", ">=", admin.firestore.Timestamp.fromDate(hace6dias))
        .get();

      console.log(`🔍 Territorios deteriorados: ${snap.docs.length}`);

      for (const doc of snap.docs) {
        const data = doc.data();
        const userId = data.userId;
        if (!userId) continue;

        const playerDoc = await db.collection("players").doc(userId).get();
        const fcmToken = playerDoc.data()?.fcm_token;
        const nombreZona = data.nombre || `zona ${doc.id.substring(0, 6)}`;

        if (!fcmToken) continue;

        await db.collection("notifications").add({
          userId,
          titulo: "⚠️ Tu territorio se está debilitando",
          cuerpo: `Tu zona en ${nombreZona} lleva 5 días sin reforzar. ¡Sal a correr!`,
          tipo: "deterioro",
          leida: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        await messaging.send({
          token: fcmToken,
          notification: {
            title: "⚠️ Tu territorio se está debilitando",
            body: `Tu zona en ${nombreZona} lleva 5 días sin reforzar. ¡Sal a correr!`,
          },
          data: { tipo: "deterioro", zona: nombreZona, territoryId: doc.id },
          android: {
            priority: "high",
            notification: { channelId: "runner_risk_invasions", defaultSound: true },
          },
          apns: { payload: { aps: { sound: "default" } } },
        });

        console.log(`✅ Deterioro enviado a ${userId}`);
      }

      return null;
    } catch (error) {
      console.error("❌ Error en notificarDeterioros:", error);
      return null;
    }
  }
);

// =============================================================================
// FUNCIÓN 3: Notificación de subida de liga
// =============================================================================
exports.notificarSubidaLiga = onDocumentUpdated(
  "players/{userId}",
  async (event) => {
    const antes = event.data.before.data();
    const despues = event.data.after.data();

    if (antes.liga === despues.liga) return null;

    const userId = event.params.userId;
    const fcmToken = despues.fcm_token;

    if (!fcmToken) return null;

    const ligaEmojis = {
      bronce: "🥉",
      plata: "🥈",
      oro: "🥇",
      diamante: "💎",
      elite: "👑",
    };

    const nombreLiga = despues.liga || "nueva liga";
    const emoji = ligaEmojis[nombreLiga.toLowerCase()] || "🏆";

    try {
      await db.collection("notifications").add({
        userId,
        titulo: `${emoji} ¡Subiste a ${nombreLiga}!`,
        cuerpo: "Sigue conquistando territorios para mantenerte en lo alto",
        tipo: "liga",
        leida: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      await messaging.send({
        token: fcmToken,
        notification: {
          title: `${emoji} ¡Subiste a ${nombreLiga}!`,
          body: "Sigue conquistando territorios para mantenerte en lo alto",
        },
        data: { tipo: "liga", nombreLiga },
        android: {
          priority: "high",
          notification: { channelId: "runner_risk_invasions", defaultSound: true },
        },
        apns: { payload: { aps: { sound: "default" } } },
      });

      console.log(`✅ Notificación de liga enviada a ${userId}`);
      return null;
    } catch (error) {
      console.error("❌ Error en notificarSubidaLiga:", error);
      return null;
    }
  }
);