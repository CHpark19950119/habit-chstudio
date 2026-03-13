const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();

const UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2";
const TUYA_BASE = "https://openapi.tuyaus.com";

function getConfig() {
  return {
    accessId: process.env.TUYA_ACCESS_ID || "",
    accessSecret: process.env.TUYA_ACCESS_SECRET || "",
    deviceId: process.env.TUYA_DEVICE_ID || "",
  };
}

// Tuya HMAC-SHA256 signing
function tuyaSign(accessId, accessSecret, t, accessToken, method, path, body) {
  const contentHash = crypto
    .createHash("sha256")
    .update(body || "")
    .digest("hex");
  const stringToSign = [method, contentHash, "", path].join("\n");
  const signStr = accessId + (accessToken || "") + t + stringToSign;
  return crypto
    .createHmac("sha256", accessSecret)
    .update(signStr)
    .digest("hex")
    .toUpperCase();
}

async function getTuyaToken(accessId, accessSecret) {
  const t = Date.now().toString();
  const path = "/v1.0/token?grant_type=1";
  const sign = tuyaSign(accessId, accessSecret, t, "", "GET", path, "");

  const {data} = await axios.get(TUYA_BASE + path, {
    headers: {
      client_id: accessId,
      sign: sign,
      t: t,
      sign_method: "HMAC-SHA256",
    },
  });

  if (!data.success) throw new Error("Token: " + JSON.stringify(data));
  return data.result.access_token;
}

async function getDeviceStatus(accessId, accessSecret, token, deviceId) {
  const t = Date.now().toString();
  const path = "/v1.0/devices/" + deviceId + "/status";
  const sign = tuyaSign(accessId, accessSecret, t, token, "GET", path, "");

  const {data} = await axios.get(TUYA_BASE + path, {
    headers: {
      client_id: accessId,
      access_token: token,
      sign: sign,
      t: t,
      sign_method: "HMAC-SHA256",
    },
  });

  if (!data.success) throw new Error("Status: " + JSON.stringify(data));
  return data.result;
}

async function pollDoorLogic() {
  const {accessId, accessSecret, deviceId} = getConfig();

  // Get Tuya API token
  const token = await getTuyaToken(accessId, accessSecret);

  // Get device status
  const statusArr = await getDeviceStatus(accessId, accessSecret, token, deviceId);

  // Find door contact state
  let doorContactState = null;
  for (const s of statusArr) {
    if (s.code === "doorcontact_state") {
      doorContactState = s.value;
    }
  }

  if (doorContactState === null) {
    return {success: false, msg: "doorcontact_state not found", raw: statusArr};
  }

  // Tuya doorcontact_state: true = closed (magnet contact), false = open
  const isOpen = !doorContactState;

  // Read current state to detect change
  const todayRef = db.doc("users/" + UID + "/data/iot");
  const doc = await todayRef.get();
  const currentDoor = doc.exists ? (doc.data().door || {}) : {};

  const stateChanged =
    currentDoor.isOpen === undefined || currentDoor.isOpen !== isOpen;

  const doorUpdate = {
    isOpen: isOpen,
    state: isOpen ? "open" : "closed",
    lastPolled: admin.firestore.FieldValue.serverTimestamp(),
    sensorId: "front_door",
  };

  // Only update lastChanged when state actually changes
  if (stateChanged) {
    doorUpdate.lastChanged = admin.firestore.FieldValue.serverTimestamp();
  }

  await todayRef.set({door: doorUpdate}, {merge: true});

  return {success: true, isOpen: isOpen, stateChanged: stateChanged, raw: statusArr};
}

// Scheduled: every 1 minute
exports.pollDoorSensor = functions.pubsub
  .schedule("every 1 minutes")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    try {
      const result = await pollDoorLogic();
      console.log("Poll:", JSON.stringify(result));
    } catch (err) {
      console.error("Poll error:", err.message);
    }
    return null;
  });

// Manual test endpoint
exports.checkDoorManual = functions.https.onRequest(async (req, res) => {
  try {
    const result = await pollDoorLogic();
    res.status(200).json(result);
  } catch (err) {
    console.error("Manual check error:", err);
    res.status(500).json({success: false, error: err.message});
  }
});

// ═══════════════════════════════════════════════════════════
//  🦉 헤드위그 — 여자친구 봇 (즉시 응답, 앱 불필요)
// ═══════════════════════════════════════════════════════════

const GF_BOT_TOKEN = "8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc";
const GF_CHAT_ID = "8624466505";
const HEDWIG_KEYWORDS = ["위치", "어디", "어디야", "where", "뭐해"];

// "HH:mm" → KST 기준 몇 분 전인지 계산
function minAgoFromHHMM(hhMm) {
  if (!hhMm || typeof hhMm !== "string") return null;
  const parts = hhMm.split(":");
  if (parts.length !== 2) return null;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (isNaN(h) || isNaN(m)) return null;
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const nowMin = kstNow.getUTCHours() * 60 + kstNow.getUTCMinutes();
  return nowMin - (h * 60 + m);
}

function formatMinAgo(min) {
  if (min === null) return "";
  if (min < 1) return "방금";
  if (min < 60) return `${min}분 전`;
  return `${Math.floor(min / 60)}시간째`;
}

function buildHedwigMessage(timeRecord, lastLocation) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const kstHour = kstNow.getUTCHours();

  const wake = timeRecord && timeRecord.wake;       // "HH:mm"
  const outing = timeRecord && timeRecord.outing;   // "HH:mm"
  const returnHome = timeRecord && timeRecord.returnHome; // "HH:mm"
  const wokeToday = !!wake;

  // 1. 수면 (11PM~7AM + 오늘 Wake 미발생)
  if ((kstHour >= 23 || kstHour < 7) && !wokeToday) {
    return "💤 자고 있어요... 쉿!\n🦉 헤드위그 🪶";
  }

  // 2. 기상 직후 (Wake 후 30분 이내)
  const wakeMinAgo = minAgoFromHHMM(wake);
  if (wokeToday && wakeMinAgo !== null && wakeMinAgo >= 0 && wakeMinAgo <= 30) {
    return `☀️ 방금 일어났어요! (${wakeMinAgo}분 전)\n🦉 헤드위그 🪶`;
  }

  // 3. 외출 중 (outing 있고 returnHome 없음)
  if (outing && !returnHome) {
    const outMin = minAgoFromHHMM(outing);
    const justLeft = outMin !== null && outMin <= 5;
    let msg = justLeft
      ? `🧹💨 방금 나갔어요! (${formatMinAgo(outMin)})`
      : `🧹 외출 중` + (outMin !== null ? ` (${formatMinAgo(outMin)} 출발)` : "");
    if (lastLocation && lastLocation.latitude && lastLocation.longitude) {
      msg += `\n📍 https://www.google.com/maps?q=${lastLocation.latitude},${lastLocation.longitude}`;
    }
    msg += "\n🦉 헤드위그 🪶";
    return msg;
  }

  // 4. 집
  if (returnHome) {
    const homeMin = minAgoFromHHMM(returnHome);
    const homeStr = homeMin !== null ? formatMinAgo(homeMin) : "";
    return `🏰 집에 있어요` + (homeStr ? ` (귀가 ${homeStr})` : "") + "\n🦉 헤드위그 🪶";
  }

  return "🏰 집에 있어요\n🦉 헤드위그 🪶";
}

// Girlfriend bot webhook — Hedwig instant response
exports.girlfriendBotWebhook = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(200).send("OK");
      return;
    }

    const message = req.body && req.body.message;
    if (!message || !message.text) {
      res.status(200).send("OK");
      return;
    }

    const text = message.text.trim().toLowerCase();
    const chatId = String(message.chat.id);

    if (chatId !== GF_CHAT_ID) {
      res.status(200).send("OK");
      return;
    }

    const isQuery = HEDWIG_KEYWORDS.some((kw) => text.includes(kw));

    if (!isQuery) {
      // 키워드 아닌 메시지 → 안내
      await axios.post(
        `https://api.telegram.org/bot${GF_BOT_TOKEN}/sendMessage`,
        {chat_id: chatId, text: "🦉 부엉? \"어디야\" 로 물어봐주세요!"},
      );
      res.status(200).send("OK");
      return;
    }

    // Read Firestore: today doc (timeRecords) + iot doc (lastLocation)
    const kstDate = new Date(Date.now() + 9 * 60 * 60 * 1000);
    const todayStr = kstDate.toISOString().slice(0, 10);

    const [todayDoc, iotDoc] = await Promise.all([
      db.doc("users/" + UID + "/data/today").get(),
      db.doc("users/" + UID + "/data/iot").get(),
    ]);

    const todayData = todayDoc.exists ? todayDoc.data() : {};
    const timeRecords = todayData.timeRecords || {};
    const timeRecord = timeRecords[todayStr] || null;

    const iotData = iotDoc.exists ? iotDoc.data() : {};
    const lastLocation = iotData.lastLocation || null;

    const hedwigMsg = buildHedwigMessage(timeRecord, lastLocation);

    await axios.post(
      `https://api.telegram.org/bot${GF_BOT_TOKEN}/sendMessage`,
      {chat_id: chatId, text: hedwigMsg},
    );

    // 외출 중이면 위치 핀도 전송
    const isOuting = timeRecord && timeRecord.outing && !timeRecord.returnHome;
    if (isOuting && lastLocation && lastLocation.latitude && lastLocation.longitude) {
      await axios.post(
        `https://api.telegram.org/bot${GF_BOT_TOKEN}/sendLocation`,
        {
          chat_id: chatId,
          latitude: lastLocation.latitude,
          longitude: lastLocation.longitude,
        },
      );
    }

    console.log("Hedwig responded:", hedwigMsg.split("\n")[0]);
    res.status(200).send("OK");
  } catch (err) {
    console.error("girlfriendBotWebhook error:", err.message);
    res.status(200).send("OK");
  }
});
