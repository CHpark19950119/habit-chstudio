const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();

const UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2";
const TUYA_BASE = "https://openapi.tuyaus.com";
const MY_BOT_TOKEN = "8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo";
const MY_CHAT_ID = "8724548311";
const GF_BOT_TOKEN = "8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc";
const GF_CHAT_ID = "8624466505";
const KAKAO_REST_KEY = "8987f9dd586416344444c7a59b5f0e73";

// ═══ 4AM 경계 날짜 (앱 StudyDateUtils.todayKey와 동일) ═══
function kstStudyDate(kstNow) {
  if (!kstNow) kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const kstHour = kstNow.getUTCHours();
  // 새벽 0~3시는 전날로 처리
  const effective = kstHour < 4
    ? new Date(kstNow.getTime() - 24 * 60 * 60 * 1000)
    : kstNow;
  return effective.toISOString().slice(0, 10);
}

// ═══ Haversine 거리 계산 (미터) ═══
function haversineM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function getConfig() {
  return {
    accessId: process.env.TUYA_ACCESS_ID || "",
    accessSecret: process.env.TUYA_ACCESS_SECRET || "",
    deviceId: process.env.TUYA_DEVICE_ID || "",
    mmwaveId: process.env.TUYA_MMWAVE_DEVICE_ID || "",
    plug16aId: process.env.TUYA_PLUG_16A_DEVICE_ID || "",
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

// ═══ Tuya POST 명령 전송 (소켓 ON/OFF 등) ═══
async function sendTuyaCommand(accessId, accessSecret, token, deviceId, commands) {
  const t = Date.now().toString();
  const path = "/v1.0/devices/" + deviceId + "/commands";
  const body = JSON.stringify({commands});
  const sign = tuyaSign(accessId, accessSecret, t, token, "POST", path, body);
  const {data} = await axios.post(TUYA_BASE + path, body, {
    headers: {
      client_id: accessId,
      access_token: token,
      sign,
      t,
      sign_method: "HMAC-SHA256",
      "Content-Type": "application/json",
    },
  });
  if (!data.success) console.error("Tuya command fail:", JSON.stringify(data));
  return data.success;
}

// ═══ 전등 제어 헬퍼 ═══
async function setLight(on) {
  try {
    const {accessId, accessSecret, plug16aId} = getConfig();
    if (!plug16aId) return;
    const token = await getTuyaToken(accessId, accessSecret);
    const ok = await sendTuyaCommand(accessId, accessSecret, token, plug16aId,
      [{code: "switch_1", value: on}]);
    console.log("Light " + (on ? "ON" : "OFF") + ":", ok);
  } catch (e) {
    console.error("setLight error:", e.message);
  }
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

  // Tuya doorcontact_state: true = open (magnet away), false = closed
  const isOpen = doorContactState;

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

  // ═══ 문 열림 일별 추적 (openedToday) ═══
  const todayDateStr = kstStudyDate();
  const prevOpenedDate = currentDoor.openedDate || "";

  // 날짜 넘어가면 리셋
  if (prevOpenedDate !== todayDateStr) {
    doorUpdate.openedToday = false;
    doorUpdate.openedDate = todayDateStr;
    doorUpdate.firstOpenTime = null;
  }

  // 문이 열려있으면 openedToday 설정 (stateChanged 무관 — 이미 열려있는 경우도 포함)
  if (isOpen) {
    doorUpdate.openedToday = true;
    doorUpdate.openedDate = todayDateStr;
    // 오늘 첫 열림 시간만 기록
    if (!currentDoor.firstOpenTime || prevOpenedDate !== todayDateStr) {
      const kstT = new Date(Date.now() + 9 * 60 * 60 * 1000);
      doorUpdate.firstOpenTime = String(kstT.getUTCHours()).padStart(2, "0") + ":" +
        String(kstT.getUTCMinutes()).padStart(2, "0");
    }
  }

  await todayRef.set({door: doorUpdate}, {merge: true});

  // ═══ 기상 감지: 오늘 문 열린 적 있으면 매 폴링마다 체크 ═══
  let wakeTime = null;
  const doorMerged = {...currentDoor, ...doorUpdate};
  if (doorMerged.openedToday) {
    wakeTime = await checkWakeAndNotify(doc, doorMerged.firstOpenTime);
  }

  // ═══ 외출 20분 확정 체크 ═══
  let outingTime = null;
  outingTime = await checkMovementPending(doc);

  // ═══ mmWave presence 폴링 (토큰 재활용) ═══
  let sleepTime = null;
  const {mmwaveId} = getConfig();
  if (mmwaveId) {
    try {
      const mmStatus = await getDeviceStatus(accessId, accessSecret, token, mmwaveId);
      let presenceState = null;
      let targetDist = null;
      for (const s of mmStatus) {
        if (s.code === "presence_state") presenceState = s.value;
        if (s.code === "target_dis_closest") targetDist = s.value;
      }

      // Firestore에 presence 상태 기록
      const iotData = doc.exists ? doc.data() : {};
      const prevPresence = iotData.presence || {};
      const presenceUpdate = {
        state: presenceState,
        distance: targetDist,
        lastPolled: admin.firestore.FieldValue.serverTimestamp(),
        sensorId: "mmwave_room",
      };

      // stationarySince 추적 — peaceful + 침대 근처(≤200cm) 연속 시작 시점
      const inBed = presenceState === "peaceful" && targetDist !== null && targetDist <= 200;
      if (inBed) {
        // 이전에도 침대 조건이었으면 유지, 아니면 새로 시작
        const prevInBed = prevPresence.state === "peaceful"
          && prevPresence.distance !== undefined && prevPresence.distance <= 200;
        if (!prevPresence.stationarySince || !prevInBed) {
          presenceUpdate.stationarySince = admin.firestore.FieldValue.serverTimestamp();
        }
      } else {
        presenceUpdate.stationarySince = null;
      }

      await todayRef.set({presence: presenceUpdate}, {merge: true});

      // ═══ 취침 자동 감지 ═══
      sleepTime = await checkSleepByPresence(doc, presenceState, prevPresence, targetDist);
    } catch (e) {
      console.error("mmWave poll error:", e.message);
    }
  }

  return {success: true, isOpen, stateChanged, wakeTime, outingTime, sleepTime, raw: statusArr};
}

// ═══════════════════════════════════════════════════════════
//  기상 감지 — CF에서 자동 처리 (앱 불필요)
// ═══════════════════════════════════════════════════════════

async function checkWakeAndNotify(iotDoc, firstOpenTime) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const kstHour = kstNow.getUTCHours();
  const kstMin = kstNow.getUTCMinutes();

  // 7시 이전 무시 (wake는 항상 7시 이후이므로 4AM 경계 무관)
  if (kstHour < 7) return null;

  const dateStr = kstStudyDate(kstNow);

  // ★ 기상 시각: 첫 문 열림 시간 사용 (7시 이전이면 현재 시간)
  let timeStr;
  if (firstOpenTime) {
    const fp = firstOpenTime.split(":").map(Number);
    timeStr = (fp[0] >= 7) ? firstOpenTime
      : String(kstHour).padStart(2, "0") + ":" + String(kstMin).padStart(2, "0");
  } else {
    timeStr = String(kstHour).padStart(2, "0") + ":" + String(kstMin).padStart(2, "0");
  }

  // 오늘 wake 이미 기록되었는지 확인
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  // ★ FIX: today doc은 flat 구조 — timeRecords.wake 직접 확인
  const todayTr = todayData.timeRecords || {};
  if (todayTr.wake || todayTr[dateStr]?.wake) return null; // 이미 기상 기록됨

  // ★ FIX: today=flat, study=nested 분리 쓰기
  const studyUpdate = {timeRecords: {}};
  studyUpdate.timeRecords[dateStr] = {wake: timeStr};

  const todayRef = db.doc("users/" + UID + "/data/today");
  await Promise.all([
    // today doc: flat 구조 (update 실패 시 set fallback)
    todayRef.update({"timeRecords.wake": timeStr, "date": dateStr})
      .catch(() => todayRef.set({timeRecords: {wake: timeStr}, date: dateStr}, {merge: true})),
    // study doc: nested 구조
    db.doc("users/" + UID + "/data/study").set(studyUpdate, {merge: true}),
  ]);

  // 텔레그램 (양쪽 발송)
  const msg = "⏰ 자동 기상 " + timeStr;
  await Promise.all([
    axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
      {chat_id: MY_CHAT_ID, text: msg}).catch(() => {}),
    axios.post("https://api.telegram.org/bot" + GF_BOT_TOKEN + "/sendMessage",
      {chat_id: GF_CHAT_ID, text: msg}).catch(() => {}),
  ]);

  // FCM data message → 앱 깨우기
  const iotData = iotDoc.exists ? iotDoc.data() : {};
  if (iotData.fcmToken) {
    try {
      await admin.messaging().send({
        token: iotData.fcmToken,
        data: {type: "wake", time: timeStr},
        notification: {title: "☀️ 기상", body: "자동 기상 " + timeStr},
        android: {priority: "high", notification: {channelId: "cheonhong_wake"}},
      });
      console.log("FCM wake sent:", timeStr);
    } catch (e) {
      console.error("FCM error:", e.message);
    }
  }

  console.log("Wake recorded:", timeStr);
  return timeStr;
}

// ═══════════════════════════════════════════════════════════
//  외출 20분 확정 — 빅스비 OUT 후 20분 경과 시 확정 처리
// ═══════════════════════════════════════════════════════════

async function checkMovementPending(iotDoc) {
  const iotData = iotDoc.exists ? iotDoc.data() : {};
  const movement = iotData.movement || {};

  if (!movement.pending) return null;

  const leftAt = movement.leftAt; // Firestore Timestamp
  if (!leftAt || !leftAt.toDate) return null;

  const leftTime = leftAt.toDate();
  const now = new Date();
  const diffMin = (now - leftTime) / (1000 * 60);

  if (diffMin < 20) return null; // 20분 미경과

  // KST 날짜/시간 (4AM 경계 적용)
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const dateStr = kstStudyDate(kstNow);
  const outTimeStr = movement.leftAtLocal || "??:??";

  // ★ FIX: today doc flat 구조로 중복 확인
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  const todayTr = todayData.timeRecords || {};
  if ((todayTr.outing || todayTr[dateStr]?.outing) === outTimeStr) {
    await db.doc("users/" + UID + "/data/iot").update({"movement.pending": false});
    return null;
  }

  // ★ FIX: today=flat, study=nested 분리 쓰기
  const studyOutUpdate = {timeRecords: {}};
  studyOutUpdate.timeRecords[dateStr] = {outing: outTimeStr};
  const todayRef2 = db.doc("users/" + UID + "/data/today");
  await Promise.all([
    db.doc("users/" + UID + "/data/study").set(studyOutUpdate, {merge: true}),
    todayRef2.update({"timeRecords.outing": outTimeStr, "date": dateStr})
      .catch(() => todayRef2.set({timeRecords: {outing: outTimeStr}, date: dateStr}, {merge: true})),
  ]);

  // 텔레그램
  // ═══ 공부 장소 매칭 ═══
  const studyLocations = iotData.studyLocations || [];
  const lastLoc = iotData.lastLocation || {};
  let locationType = "out";
  let locationName = null;

  if (lastLoc.latitude && lastLoc.longitude && studyLocations.length > 0) {
    for (const loc of studyLocations) {
      const dist = haversineM(lastLoc.latitude, lastLoc.longitude, loc.lat, loc.lng);
      const radius = loc.radius || 200;
      if (dist <= radius) {
        locationType = "studying";
        locationName = loc.name;
        break;
      }
    }
  }

  // ═══ 전등 OFF (외출 확정 시) ═══
  setLight(false);

  // movement 타입 업데이트
  const movementUpdate = {
    "movement.pending": false,
    "movement.type": locationType,
    "movement.confirmedAt": admin.firestore.FieldValue.serverTimestamp(),
  };
  if (locationName) movementUpdate["movement.locationName"] = locationName;
  await db.doc("users/" + UID + "/data/iot").update(movementUpdate);

  const locLabel = locationName ? " @ " + locationName : "";
  const emoji = locationType === "studying" ? "📚" : "🚶";
  const msg = emoji + " 외출 확정 " + outTimeStr + " (20분 경과)" + locLabel;
  await Promise.all([
    axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
      {chat_id: MY_CHAT_ID, text: msg}).catch(() => {}),
    axios.post("https://api.telegram.org/bot" + GF_BOT_TOKEN + "/sendMessage",
      {chat_id: GF_CHAT_ID, text: msg}).catch(() => {}),
  ]);

  // FCM → 앱 상태 업데이트
  if (iotData.fcmToken) {
    try {
      await admin.messaging().send({
        token: iotData.fcmToken,
        data: {type: locationType === "studying" ? "studying" : "outing", time: outTimeStr, location: locationName || ""},
        android: {priority: "high"},
      });
      console.log("FCM outing sent:", outTimeStr);
    } catch (e) {
      console.error("FCM outing error:", e.message);
    }
  }

  console.log("Outing confirmed:", outTimeStr);
  return outTimeStr;
}

// ═══════════════════════════════════════════════════════════
//  취침 자동 감지 — mmWave presence 기반
//  peaceful + ≤200cm + 23~07시 + 30분 연속 → 취침 확정
// ═══════════════════════════════════════════════════════════

async function checkSleepByPresence(iotDoc, presenceState, prevPresence, targetDist) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const kstHour = kstNow.getUTCHours();
  const kstMin = kstNow.getUTCMinutes();

  // 시간 조건: 23~07시
  if (kstHour >= 7 && kstHour < 23) return null;

  // presence 조건
  if (presenceState !== "peaceful" || targetDist === null || targetDist > 200) return null;

  // bedTime 이미 기록 확인
  const dateStr = kstStudyDate(kstNow);
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  const todayTr = todayData.timeRecords || {};
  if (todayTr.bedTime || todayTr[dateStr]?.bedTime) return null;

  // stationarySince 30분 경과 확인
  const since = prevPresence.stationarySince;
  if (!since || !since.toDate) return null;
  const sinceTime = since.toDate();
  const elapsedMin = (Date.now() - sinceTime.getTime()) / (1000 * 60);
  if (elapsedMin < 30) return null;

  // ═══ 취침 확정 ═══
  const timeStr = String(kstHour).padStart(2, "0") + ":" + String(kstMin).padStart(2, "0");

  // 1. 전등 OFF
  setLight(false);

  // 2. bedTime 듀얼라이트
  const studySleepUpdate = {timeRecords: {}};
  studySleepUpdate.timeRecords[dateStr] = {bedTime: timeStr};
  const todayRef = db.doc("users/" + UID + "/data/today");
  await Promise.all([
    todayRef.update({"timeRecords.bedTime": timeStr, "date": dateStr})
      .catch(() => todayRef.set({timeRecords: {bedTime: timeStr}, date: dateStr}, {merge: true})),
    db.doc("users/" + UID + "/data/study").set(studySleepUpdate, {merge: true}),
  ]);

  // 3. stationarySince 리셋 (재감지 방지)
  await db.doc("users/" + UID + "/data/iot").update({"presence.stationarySince": null});

  // 4. 텔레그램
  const msg = "🛏️ 자동 취침 " + timeStr;
  await Promise.all([
    axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
      {chat_id: MY_CHAT_ID, text: msg}).catch(() => {}),
    axios.post("https://api.telegram.org/bot" + GF_BOT_TOKEN + "/sendMessage",
      {chat_id: GF_CHAT_ID, text: msg}).catch(() => {}),
  ]);

  // 5. FCM → 앱 sleeping 전환
  const iotData = iotDoc.exists ? iotDoc.data() : {};
  if (iotData.fcmToken) {
    try {
      await admin.messaging().send({
        token: iotData.fcmToken,
        data: {type: "sleep", time: timeStr},
        notification: {title: "🛏️ 취침", body: "자동 취침 " + timeStr},
        android: {priority: "high", notification: {channelId: "cheonhong_sleep"}},
      });
    } catch (e) { console.error("FCM sleep error:", e.message); }
  }

  console.log("Sleep recorded:", timeStr);
  return timeStr;
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
//  onIotWrite — Single Writer for external timeRecords
//  data/iot 변경 감지 → today+study 듀얼라이트 (유일한 외부 writer)
// ═══════════════════════════════════════════════════════════

exports.onIotWrite = functions.firestore
  .document("users/{uid}/data/iot")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    if (uid !== UID) return;

    const before = change.before.exists ? change.before.data() : {};
    const after = change.after.exists ? change.after.data() : {};

    const mvBefore = before.movement || {};
    const mvAfter = after.movement || {};

    // ── 귀가 감지: movement.type → "home" ──
    if (mvAfter.type === "home" && mvBefore.type !== "home") {
      await handleReturnHome(mvAfter, after);
    }

    // ── Geofence 직접 외출: source=geofence*, type → "out" ──
    if (mvAfter.type === "out" && mvBefore.type !== "out"
        && !mvAfter.pending
        && (mvAfter.source || "").startsWith("geofence")) {
      await handleGeofenceOuting(mvAfter, after);
    }
  });

async function handleReturnHome(movement, iotData) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const dateStr = kstStudyDate(kstNow);
  const returnTime = movement.returnedAtLocal || "??:??";

  // ★ FIX: today doc flat 구조로 중복 확인
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  const todayTr = todayData.timeRecords || {};
  if (todayTr.returnHome || todayTr[dateStr]?.returnHome) return;

  // ═══ 전등 ON (귀가 시) — bedTime 기록 시 스킵(화장실), 낮 스킵 ═══
  const bedTimeRecorded = todayTr.bedTime || todayTr[dateStr]?.bedTime;
  if (!bedTimeRecorded && kstNow.getUTCHours() >= 18) {
    setLight(true);
  }

  // ★ FIX: today=flat, study=nested 분리 쓰기
  const studyReturnUpdate = {timeRecords: {}};
  studyReturnUpdate.timeRecords[dateStr] = {returnHome: returnTime};
  const todayRef3 = db.doc("users/" + UID + "/data/today");
  await Promise.all([
    todayRef3.update({"timeRecords.returnHome": returnTime, "date": dateStr})
      .catch(() => todayRef3.set({timeRecords: {returnHome: returnTime}, date: dateStr}, {merge: true})),
    db.doc("users/" + UID + "/data/study").set(studyReturnUpdate, {merge: true}),
  ]);

  // 경과시간
  const outTime = todayTr.outing || todayTr[dateStr]?.outing;
  let dur = "";
  if (outTime) {
    try {
      const op = outTime.split(":").map(Number);
      const rp = returnTime.split(":").map(Number);
      const m = (rp[0] * 60 + rp[1]) - (op[0] * 60 + op[1]);
      if (m > 0) dur = " (" + Math.floor(m / 60) + "h" + String(m % 60).padStart(2, "0") + "m)";
    } catch (_) {}
  }

  // 텔레그램
  const msg = "🏠 귀가 " + returnTime + dur;
  await Promise.all([
    axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
      {chat_id: MY_CHAT_ID, text: msg}).catch(() => {}),
    axios.post("https://api.telegram.org/bot" + GF_BOT_TOKEN + "/sendMessage",
      {chat_id: GF_CHAT_ID, text: msg}).catch(() => {}),
  ]);

  // FCM
  if (iotData.fcmToken) {
    try {
      await admin.messaging().send({
        token: iotData.fcmToken,
        data: {type: "returnHome", time: returnTime},
        android: {priority: "high"},
      });
    } catch (e) { console.error("FCM return error:", e.message); }
  }
  console.log("Return recorded:", returnTime + dur);
}

async function handleGeofenceOuting(movement, iotData) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const dateStr = kstStudyDate(kstNow);
  const outTime = movement.leftAtLocal || "??:??";

  // ★ FIX: today doc flat 구조로 중복 확인
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  const todayTr = todayData.timeRecords || {};
  if (todayTr.outing || todayTr[dateStr]?.outing) return;

  // ═══ 전등 OFF (외출 시) ═══
  setLight(false);

  // ★ FIX: today=flat, study=nested 분리 쓰기
  const studyGeoUpdate = {timeRecords: {}};
  studyGeoUpdate.timeRecords[dateStr] = {outing: outTime};
  const todayRef4 = db.doc("users/" + UID + "/data/today");
  await Promise.all([
    todayRef4.update({"timeRecords.outing": outTime, "date": dateStr})
      .catch(() => todayRef4.set({timeRecords: {outing: outTime}, date: dateStr}, {merge: true})),
    db.doc("users/" + UID + "/data/study").set(studyGeoUpdate, {merge: true}),
  ]);

  const lastLoc = iotData.lastLocation || {};
  let locStr = "";
  if (lastLoc.latitude && lastLoc.longitude) {
    locStr = " (" + lastLoc.latitude.toFixed(4) + "," + lastLoc.longitude.toFixed(4) + ")";
  }
  const msg = "🚶 외출 " + outTime + locStr;
  await Promise.all([
    axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
      {chat_id: MY_CHAT_ID, text: msg}).catch(() => {}),
    axios.post("https://api.telegram.org/bot" + GF_BOT_TOKEN + "/sendMessage",
      {chat_id: GF_CHAT_ID, text: msg}).catch(() => {}),
  ]);

  if (iotData.fcmToken) {
    try {
      await admin.messaging().send({
        token: iotData.fcmToken,
        data: {type: "outing", time: outTime},
        android: {priority: "high"},
      });
    } catch (e) { console.error("FCM geofence outing error:", e.message); }
  }
  console.log("Geofence outing recorded:", outTime);
}

// ═══════════════════════════════════════════════════════════
//  🦉 헤드위그 — 여자친구 봇 (즉시 응답, 앱 불필요)
// ═══════════════════════════════════════════════════════════

const HEDWIG_KEYWORDS = ["위치", "어디", "어디야", "where", "뭐해", "/where", "/status"];

// 카카오 역지오코딩 — GPS → 보편적 장소명
// "금정역 근처", "이마트 광정점 근처" 같이 알아듣기 쉽게
async function reverseGeocode(lat, lng) {
  try {
    const headers = {Authorization: "KakaoAK " + KAKAO_REST_KEY};
    const params = {x: lng, y: lat, radius: 500, sort: "distance"};

    // 1) 랜드마크 카테고리 검색 (지하철 > 대형마트 > 학교 > 병원 순)
    const categories = [
      {code: "SW8", label: "역"},      // 지하철
      {code: "MT1", label: ""},         // 대형마트
      {code: "SC4", label: ""},         // 학교
      {code: "CT1", label: ""},         // 문화시설
      {code: "HP8", label: ""},         // 병원
    ];

    for (const cat of categories) {
      try {
        const {data} = await axios.get("https://dapi.kakao.com/v2/local/search/category.json", {
          params: {...params, category_group_code: cat.code},
          headers,
        });
        const places = data.documents || [];
        if (places.length > 0) {
          const p = places[0];
          const dist = parseInt(p.distance);
          const name = p.place_name;
          if (dist <= 100) return name;
          return name + " 근처 (" + dist + "m)";
        }
      } catch (_) {}
    }

    // 2) fallback: 행정동
    const {data} = await axios.get("https://dapi.kakao.com/v2/local/geo/coord2regioncode.json", {
      params: {x: lng, y: lat}, headers,
    });
    const regions = data.documents || [];
    const hDoc = regions.find((d) => d.region_type === "H") || regions[0];
    if (hDoc) return hDoc.region_1depth_name + " " + hDoc.region_2depth_name;
  } catch (e) {
    console.error("Kakao geocode error:", e.message);
  }
  return null;
}

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

async function buildHedwigMessage(timeRecord, lastLocation, movement) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const kstHour = kstNow.getUTCHours();

  const wake = timeRecord && timeRecord.wake;       // "HH:mm"
  const wokeToday = !!wake;

  // 0. bedTime 기록 있으면 확실히 자고 있는 상태
  if (timeRecord && timeRecord.bedTime) {
    return "💤 자고 있어요... 쉿!\n🦉 헤드위그 🪶";
  }

  // 1. 수면 (11PM~7AM + 오늘 Wake 미발생)
  if ((kstHour >= 23 || kstHour < 7) && !wokeToday) {
    return "💤 자고 있어요... 쉿!\n🦉 헤드위그 🪶";
  }

  // 2. 기상 직후 (Wake 후 30분 이내)
  const wakeMinAgo = minAgoFromHHMM(wake);
  if (wokeToday && wakeMinAgo !== null && wakeMinAgo >= 0 && wakeMinAgo <= 30) {
    return `☀️ 방금 일어났어요! (${wakeMinAgo}분 전)\n🦉 헤드위그 🪶`;
  }

  // 3. 빅스비 movement 기반 외출/귀가 (우선)
  if (movement) {
    const mType = movement.type || "";
    const mPending = movement.pending || false;
    const leftLocal = movement.leftAtLocal || "";
    const returnedLocal = movement.returnedAtLocal || "";

    // 3a. 확인 중 (pending)
    if (mPending && mType === "pending") {
      const outMin = minAgoFromHHMM(leftLocal);
      let msg = `🚶 잠깐 나간 것 같아요... (확인 중)`;
      if (outMin !== null && outMin >= 0) msg += `\n⏱ ${formatMinAgo(outMin)} 출발`;
      msg += "\n🦉 헤드위그 🪶";
      return msg;
    }

    // 3b. 외출 확정
    if (mType === "out") {
      const outMin = minAgoFromHHMM(leftLocal);
      const justLeft = outMin !== null && outMin <= 5;
      let msg = justLeft
        ? `🧹💨 방금 나갔어요! (${formatMinAgo(outMin)})`
        : `🧹 외출 중` + (outMin !== null ? ` (${formatMinAgo(outMin)} 출발)` : "");
      if (lastLocation && lastLocation.latitude && lastLocation.longitude) {
        const place = await reverseGeocode(lastLocation.latitude, lastLocation.longitude);
        if (place) msg += `\n📍 ${place}`;
        msg += `\n🗺 https://www.google.com/maps?q=${lastLocation.latitude},${lastLocation.longitude}`;
      }
      msg += "\n🦉 헤드위그 🪶";
      return msg;
    }

    // 3c. 귀가 완료
    if (mType === "home") {
      const homeMin = minAgoFromHHMM(returnedLocal);
      const homeStr = homeMin !== null ? formatMinAgo(homeMin) : "";
      return `🏰 집에 있어요` + (homeStr ? ` (귀가 ${homeStr})` : "") + "\n🦉 헤드위그 🪶";
    }
  }

  // 4. fallback: timeRecords 기반 (레거시)
  const outing = timeRecord && timeRecord.outing;
  const returnHome = timeRecord && timeRecord.returnHome;

  if (outing && !returnHome) {
    const outMin = minAgoFromHHMM(outing);
    let msg = `🧹 외출 중` + (outMin !== null ? ` (${formatMinAgo(outMin)} 출발)` : "");
    if (lastLocation && lastLocation.latitude && lastLocation.longitude) {
      const place = await reverseGeocode(lastLocation.latitude, lastLocation.longitude);
      if (place) msg += `\n📍 ${place}`;
      msg += `\n🗺 https://www.google.com/maps?q=${lastLocation.latitude},${lastLocation.longitude}`;
    }
    msg += "\n🦉 헤드위그 🪶";
    return msg;
  }

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
    // ★ FIX: 4AM 경계 + today doc flat 구조 대응
    const [todayDoc, iotDoc] = await Promise.all([
      db.doc("users/" + UID + "/data/today").get(),
      db.doc("users/" + UID + "/data/iot").get(),
    ]);

    const todayData = todayDoc.exists ? todayDoc.data() : {};
    // today doc flat 구조: timeRecords.wake 직접, nested fallback도 확인
    const rawTr = todayData.timeRecords || {};
    const timeRecord = rawTr.wake !== undefined ? rawTr : null;

    const iotData = iotDoc.exists ? iotDoc.data() : {};
    const lastLocation = iotData.lastLocation || null;
    const movement = iotData.movement || null;

    const hedwigMsg = await buildHedwigMessage(timeRecord, lastLocation, movement);

    await axios.post(
      `https://api.telegram.org/bot${GF_BOT_TOKEN}/sendMessage`,
      {chat_id: chatId, text: hedwigMsg},
    );

    // 외출 중이면 위치 핀도 전송
    const isOuting = (movement && (movement.type === "out" || (movement.pending && movement.type === "pending")))
      || (timeRecord && timeRecord.outing && !timeRecord.returnHome);
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

// ═══════════════════════════════════════════════════════════
//  📋 고시 공고 크롤러 — 사이버국가고시센터 공지사항
//  하루 1회 (08:00 KST) 새 공고 확인 → 텔레그램 알림
// ═══════════════════════════════════════════════════════════

const GOSI_BBS_URL = "https://www.gosi.kr/cop/bbs/selectBoardList.do?bbsId=BBSMSTR_000000000131";
const GOSI_DETAIL_URL = "https://www.gosi.kr/cop/bbs/selectBoardArticle.do?bbsId=BBSMSTR_000000000131&nttId=";

async function pollGosiLogic() {
  // 1. Firestore에서 마지막 확인한 nttId 읽기
  const metaRef = db.doc("users/" + UID + "/data/meta");
  const metaDoc = await metaRef.get();
  const meta = metaDoc.exists ? metaDoc.data() : {};
  const lastNttId = meta.gosiLastNttId || 0;

  // 2. 공지사항 페이지 크롤링
  const {data: html} = await axios.get(GOSI_BBS_URL, {
    timeout: 15000,
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8",
      "Accept-Encoding": "gzip, deflate, br",
      "Connection": "keep-alive",
      "Referer": "https://www.gosi.kr/",
    },
    maxRedirects: 5,
  });

  // 3. 게시글 파싱 — fn_egov_inqire_notice('nttId','bbsId') 패턴
  const regex = /fn_egov_inqire_notice\('(\d+)'/g;
  const titleRegex = /<td[^>]*class="tit"[^>]*>([\s\S]*?)<\/td>/gi;
  const dateRegex = /(\d{4}\.\d{2}\.\d{2})/g;

  // 행 단위 파싱
  const rows = html.split(/<tr[^>]*>/i).slice(1);
  const notices = [];

  for (const row of rows) {
    const nttMatch = /fn_egov_inqire_notice\('(\d+)'/.exec(row);
    if (!nttMatch) continue;
    const nttId = parseInt(nttMatch[1]);

    // 제목 추출
    const titMatch = /<td[^>]*class="tit"[^>]*>([\s\S]*?)<\/td>/i.exec(row);
    let title = "제목 없음";
    if (titMatch) {
      title = titMatch[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
    }

    // 날짜 추출
    const dates = row.match(/\d{4}\.\d{2}\.\d{2}/g);
    const date = dates ? dates[dates.length - 1] : "";

    // 시험종류 추출
    const typeMatch = /<td[^>]*>([\s\S]*?)<\/td>/gi;
    let examType = "";
    let tdIdx = 0;
    let m;
    while ((m = /<td[^>]*>([\s\S]*?)<\/td>/gi.exec(row)) !== null) {
      tdIdx++;
      if (tdIdx === 2) {
        examType = m[1].replace(/<[^>]+>/g, "").trim();
        break;
      }
    }

    notices.push({nttId, title, date, examType});
  }

  if (notices.length === 0) {
    return {success: true, newCount: 0, msg: "파싱 실패 또는 공지 없음"};
  }

  // 4. 새 공고 필터
  const newNotices = notices.filter((n) => n.nttId > lastNttId);

  if (newNotices.length === 0) {
    return {success: true, newCount: 0, latest: notices[0]?.nttId};
  }

  // 5. 텔레그램 알림
  let msg = "📋 고시 공고 " + newNotices.length + "건\n";
  for (const n of newNotices.slice(0, 5)) {
    msg += "\n" + (n.examType ? "[" + n.examType + "] " : "");
    msg += n.title;
    if (n.date) msg += " (" + n.date + ")";
    msg += "\n" + GOSI_DETAIL_URL + n.nttId;
  }
  if (newNotices.length > 5) {
    msg += "\n\n... 외 " + (newNotices.length - 5) + "건";
  }

  await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
    {chat_id: MY_CHAT_ID, text: msg, disable_web_page_preview: true}).catch(() => {});

  // 6. 마지막 nttId 업데이트
  const maxNttId = Math.max(...notices.map((n) => n.nttId));
  await metaRef.set({gosiLastNttId: maxNttId}, {merge: true});

  console.log("Gosi:", newNotices.length, "new, max:", maxNttId);
  return {success: true, newCount: newNotices.length, maxNttId};
}

// 매일 08:00 KST
exports.pollGosiNotice = functions.pubsub
  .schedule("0 8 * * *")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    try {
      const result = await pollGosiLogic();
      console.log("Gosi poll:", JSON.stringify(result));
    } catch (err) {
      console.error("Gosi poll error:", err.message);
      // 에러 시 텔레그램 알림
      await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
        {chat_id: MY_CHAT_ID, text: "⚠️ 고시 공고 크롤링 실패\n에러: " + err.message}).catch(() => {});
    }
    return null;
  });

// 수동 테스트
exports.checkGosiManual = functions.https.onRequest(async (req, res) => {
  try {
    const result = await pollGosiLogic();
    res.status(200).json(result);
  } catch (err) {
    res.status(500).json({success: false, error: err.message});
  }
});

// ═══════════════════════════════════════════════════════════
//  🤖 AI 비서 — 텔레그램 → Claude API (tool use) → Firestore
// ═══════════════════════════════════════════════════════════

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY || "";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

const AI_TOOLS = [
  {
    name: "add_todo",
    description: "오늘 투두(할 일) 추가. 예: '헌법 모의고사 풀기', '행정법 30강 듣기'",
    input_schema: {
      type: "object",
      properties: {
        title: {type: "string", description: "할 일 제목"},
        subject: {type: "string", enum: ["언어", "자료", "상황", "경제", "7급전공"], description: "과목 (선택)"},
        estimatedMinutes: {type: "integer", description: "예상 소요 시간 (분, 선택)"},
        priority: {type: "string", enum: ["high", "medium", "low"], description: "우선순위 (선택)"},
        type: {type: "string", enum: ["study", "review", "mock", "task", "errand"], description: "유형 (선택)"},
      },
      required: ["title"],
    },
  },
  {
    name: "add_habit",
    description: "습관 추가. 예: '매일 아침 커피사기', '취침 전 스트레칭'",
    input_schema: {
      type: "object",
      properties: {
        title: {type: "string", description: "습관 제목"},
        emoji: {type: "string", description: "이모지 (기본: ✅)"},
        autoTrigger: {type: "string", enum: ["wake", "sleep", "study", "outing", "meal"], description: "자동 트리거 (선택). wake=기상, sleep=취침, study=공부시작, outing=외출, meal=식사"},
        triggerTime: {type: "string", description: "트리거 시간 HH:mm (선택, autoTrigger와 함께)"},
      },
      required: ["title"],
    },
  },
  {
    name: "add_goal",
    description: "진행도 목표 추가. 예: '행정법 기본서 1회독 500페이지', '경제학 인강 60강'",
    input_schema: {
      type: "object",
      properties: {
        title: {type: "string", description: "목표 제목"},
        subject: {type: "string", enum: ["언어", "자료", "상황", "경제", "7급전공"], description: "과목"},
        totalUnits: {type: "integer", description: "총 단위 수 (강, 페이지 등)"},
        unitName: {type: "string", description: "단위명 (강, 페이지, 회 등). 기본: 강"},
        goalType: {type: "string", enum: ["lecture", "textbook"], description: "유형. lecture=인강, textbook=교재"},
        endDate: {type: "string", description: "마감일 yyyy-MM-dd (선택)"},
      },
      required: ["title", "subject", "totalUnits"],
    },
  },
  {
    name: "today_summary",
    description: "오늘 하루 요약 조회. 기상, 공부, 외출, 식사, 투두 현황 등",
    input_schema: {type: "object", properties: {}, required: []},
  },
  {
    name: "set_light",
    description: "방 전등 켜기/끄기",
    input_schema: {
      type: "object",
      properties: {
        on: {type: "boolean", description: "true=켜기, false=끄기"},
      },
      required: ["on"],
    },
  },
  {
    name: "list_todos",
    description: "오늘 투두 목록 조회",
    input_schema: {type: "object", properties: {}, required: []},
  },
  {
    name: "complete_todo",
    description: "투두 완료 처리 (제목으로 검색)",
    input_schema: {
      type: "object",
      properties: {
        keyword: {type: "string", description: "투두 제목 키워드 (부분 일치)"},
      },
      required: ["keyword"],
    },
  },
  {
    name: "iot_status",
    description: "IoT 센서 전체 상태 조회 — 도어센서, mmWave, 전등, 위치",
    input_schema: {type: "object", properties: {}, required: []},
  },
  {
    name: "query_sensor",
    description: "특정 Tuya 센서/기기 실시간 상태 직접 조회 (API 호출)",
    input_schema: {
      type: "object",
      properties: {
        device: {type: "string", enum: ["door", "mmwave", "plug_16a", "plug_20a"], description: "조회할 기기"},
      },
      required: ["device"],
    },
  },
];

const AI_SYSTEM = `너는 CHEONHONG STUDIO 앱의 AI 비서야. 사용자(천홍)의 공부/루틴/IoT를 관리해.
오늘 날짜: ${kstStudyDate()}
간결하게 답하되 친근한 반말 사용. 이모지 적절히.
tool 호출이 필요하면 반드시 tool을 사용해. 일반 대화도 가능.

IoT 기기:
- 도어센서(door): 방문 열림/닫힘
- mmWave(mmwave): 존재감지 (none=비어있음, presence=움직임, peaceful=정지), distance=거리cm
- 16A 소켓(plug_16a): 방 전등 ON/OFF
- 20A 소켓(plug_20a): 예비 (미연결)

"센서 상태" → iot_status, "전등 상태" → query_sensor(plug_16a)`;

// ── tool 실행 ──

async function executeTool(name, input) {
  const dateStr = kstStudyDate();

  if (name === "add_todo") {
    const studyData = await db.doc("users/" + UID + "/data/study").get();
    const data = studyData.exists ? studyData.data() : {};
    const todosRaw = data.todos || {};
    const dayTodos = todosRaw[dateStr] || {date: dateStr, items: []};
    const items = dayTodos.items || [];

    const newItem = {
      id: "todo_" + Date.now(),
      title: input.title,
      completed: false,
      order: items.length,
    };
    if (input.subject) newItem.subject = input.subject;
    if (input.estimatedMinutes) newItem.estimatedMinutes = input.estimatedMinutes;
    if (input.priority) newItem.priority = input.priority;
    if (input.type) newItem.type = input.type;

    items.push(newItem);
    await db.doc("users/" + UID + "/data/study").set(
      {todos: {[dateStr]: {date: dateStr, items, updatedAt: new Date().toISOString()}}},
      {merge: true});
    return "✅ 투두 추가: " + input.title;
  }

  if (name === "add_habit") {
    const studyData = await db.doc("users/" + UID + "/data/study").get();
    const data = studyData.exists ? studyData.data() : {};
    const orderData = data.orderData || {goals: [], habits: [], expenses: []};
    const habits = orderData.habits || [];

    const newHabit = {
      id: "habit_" + Date.now(),
      title: input.title,
      emoji: input.emoji || "✅",
      freq: "daily",
      targetPerWeek: 7,
      completedDates: [],
      createdAt: new Date().toISOString(),
      archived: false,
      rank: 0,
      targetDays: 21,
      streakHistory: [],
    };
    if (input.autoTrigger) newHabit.autoTrigger = input.autoTrigger;
    if (input.triggerTime) newHabit.triggerTime = input.triggerTime;

    habits.push(newHabit);
    await db.doc("users/" + UID + "/data/study").set(
      {orderData: {...orderData, habits}}, {merge: true});
    const triggerLabel = input.autoTrigger
      ? {wake: "기상", sleep: "취침", study: "공부", outing: "외출", meal: "식사"}[input.autoTrigger] || ""
      : "";
    return "✅ 습관 추가: " + input.title + (triggerLabel ? " (" + triggerLabel + " 시 자동)" : "");
  }

  if (name === "add_goal") {
    const studyData = await db.doc("users/" + UID + "/data/study").get();
    const data = studyData.exists ? studyData.data() : {};
    const orderData = data.orderData || {goals: [], habits: [], expenses: []};
    const goals = orderData.goals || [];

    const newGoal = {
      id: "goal_" + Date.now(),
      subject: input.subject,
      title: input.title,
      totalUnits: input.totalUnits,
      unitName: input.unitName || "강",
      goalType: input.goalType || "lecture",
      startPage: 0, endPage: 0,
      currentUnit: 0,
      completed: false,
      dailyLogs: [],
      completionHistory: [],
      createdAt: new Date().toISOString(),
    };
    if (input.endDate) newGoal.endDate = input.endDate;

    goals.push(newGoal);
    await db.doc("users/" + UID + "/data/study").set(
      {orderData: {...orderData, goals}}, {merge: true});
    return "✅ 목표 추가: " + input.title + " (" + input.totalUnits + (input.unitName || "강") + ")";
  }

  if (name === "today_summary") {
    const [todayDoc, studyDoc] = await Promise.all([
      db.doc("users/" + UID + "/data/today").get(),
      db.doc("users/" + UID + "/data/study").get(),
    ]);
    const today = todayDoc.exists ? todayDoc.data() : {};
    const study = studyDoc.exists ? studyDoc.data() : {};
    const tr = today.timeRecords || {};
    const str = (study.studyTimeRecords || {})[dateStr];
    const todos = ((study.todos || {})[dateStr] || {}).items || [];
    const doneTodos = todos.filter((t) => t.completed).length;

    let summary = "📊 오늘 요약\n";
    if (tr.wake) summary += "☀️ 기상: " + tr.wake + "\n";
    if (tr.outing) summary += "🚶 외출: " + tr.outing + (tr.returnHome ? " → 귀가 " + tr.returnHome : " (외출 중)") + "\n";
    if (tr.study) summary += "📖 공부: " + tr.study + (tr.studyEnd ? " → " + tr.studyEnd : " (진행 중)") + "\n";
    if (str) summary += "⏱ 순공: " + Math.floor((str.effectiveMinutes || str.totalMinutes || 0) / 60) + "h " + ((str.effectiveMinutes || str.totalMinutes || 0) % 60) + "m\n";
    summary += "📋 투두: " + doneTodos + "/" + todos.length + "개 완료\n";
    if (tr.bedTime) summary += "🛏️ 취침: " + tr.bedTime;
    return summary;
  }

  if (name === "set_light") {
    await setLight(input.on);
    return input.on ? "💡 전등 켰어" : "🌙 전등 껐어";
  }

  if (name === "list_todos") {
    const studyDoc = await db.doc("users/" + UID + "/data/study").get();
    const data = studyDoc.exists ? studyDoc.data() : {};
    const todos = ((data.todos || {})[dateStr] || {}).items || [];
    if (todos.length === 0) return "📋 오늘 투두 없음";
    return "📋 오늘 투두:\n" + todos.map((t, i) =>
      (t.completed ? "✅" : "⬜") + " " + t.title +
      (t.subject ? " [" + t.subject + "]" : "") +
      (t.estimatedMinutes ? " " + t.estimatedMinutes + "분" : "")
    ).join("\n");
  }

  if (name === "complete_todo") {
    const studyDoc = await db.doc("users/" + UID + "/data/study").get();
    const data = studyDoc.exists ? studyDoc.data() : {};
    const dayTodos = (data.todos || {})[dateStr] || {date: dateStr, items: []};
    const items = dayTodos.items || [];
    const idx = items.findIndex((t) => !t.completed && t.title.includes(input.keyword));
    if (idx < 0) return "❌ '" + input.keyword + "' 투두 못 찾음";
    items[idx].completed = true;
    items[idx].completedAt = new Date().toISOString();
    await db.doc("users/" + UID + "/data/study").set(
      {todos: {[dateStr]: {date: dateStr, items, updatedAt: new Date().toISOString()}}},
      {merge: true});
    return "✅ 완료: " + items[idx].title;
  }

  if (name === "iot_status") {
    const iotDoc = await db.doc("users/" + UID + "/data/iot").get();
    const iot = iotDoc.exists ? iotDoc.data() : {};
    const door = iot.door || {};
    const presence = iot.presence || {};
    const movement = iot.movement || {};

    let status = "🏠 IoT 상태\n";
    status += "🚪 도어: " + (door.state || "?") + (door.openedToday ? " (오늘 열림)" : "") + "\n";
    status += "📡 mmWave: " + (presence.state || "?");
    if (presence.distance != null) status += " " + presence.distance + "cm";
    status += "\n";
    status += "💡 전등: Firestore에 없음 (query_sensor로 실시간 조회)\n";
    if (movement.type) status += "🚶 이동: " + movement.type + "\n";
    return status;
  }

  if (name === "query_sensor") {
    const deviceMap = {
      door: process.env.TUYA_DEVICE_ID,
      mmwave: process.env.TUYA_MMWAVE_DEVICE_ID,
      plug_16a: process.env.TUYA_PLUG_16A_DEVICE_ID,
      plug_20a: "ebeaff0f5a69754067yfdv",
    };
    const did = deviceMap[input.device];
    if (!did) return "❌ 기기 없음: " + input.device;

    const {accessId, accessSecret} = getConfig();
    const token = await getTuyaToken(accessId, accessSecret);
    const statusArr = await getDeviceStatus(accessId, accessSecret, token, did);

    const labels = {door: "🚪 도어센서", mmwave: "📡 mmWave", plug_16a: "💡 16A 소켓(전등)", plug_20a: "🔌 20A 소켓"};
    let result = labels[input.device] + " 실시간:\n";
    for (const s of statusArr) {
      result += "  " + s.code + ": " + s.value + "\n";
    }
    return result;
  }

  return "⚠️ 알 수 없는 도구: " + name;
}

// ── Claude API 호출 ──

async function callClaude(userMessage) {
  const {data} = await axios.post(ANTHROPIC_URL, {
    model: "claude-sonnet-4-20250514",
    max_tokens: 1024,
    system: AI_SYSTEM,
    tools: AI_TOOLS,
    messages: [{role: "user", content: userMessage}],
  }, {
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    timeout: 30000,
  });

  // tool_use 처리
  const results = [];
  let textReply = "";

  for (const block of data.content) {
    if (block.type === "text") {
      textReply += block.text;
    } else if (block.type === "tool_use") {
      const toolResult = await executeTool(block.name, block.input);
      results.push(toolResult);
    }
  }

  // tool 결과가 있으면 그것만, 없으면 텍스트 응답
  if (results.length > 0) return results.join("\n");
  return textReply || "🤔 응답 없음";
}

// ── 내 봇 웹훅 ──

exports.myBotWebhook = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") { res.status(200).send("OK"); return; }

    const message = req.body && req.body.message;
    if (!message || !message.text) { res.status(200).send("OK"); return; }

    const chatId = String(message.chat.id);
    if (chatId !== MY_CHAT_ID) { res.status(200).send("OK"); return; }

    const text = message.text.trim();
    console.log("MyBot:", text);

    const reply = await callClaude(text);

    // 텔레그램 응답
    await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage", {
      chat_id: MY_CHAT_ID,
      text: reply,
      disable_web_page_preview: true,
    }).catch(() => {});

    res.status(200).send("OK");
  } catch (err) {
    console.error("myBotWebhook error:", err.message);
    // 에러 시 사용자에게 알림
    await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage", {
      chat_id: MY_CHAT_ID,
      text: "⚠️ AI 비서 에러: " + err.message,
    }).catch(() => {});
    res.status(200).send("OK");
  }
});
