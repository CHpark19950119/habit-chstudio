const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();

// ★ AUDIT FIX: S-01, S-02 — 환경변수/config에서 읽기, 하드코딩 fallback
const UID = process.env.FIREBASE_UID || "sJ8Pxusw9gR0tNR44RhkIge7OiG2";
const TUYA_BASE = "https://openapi.tuyaus.com";
const MY_BOT_TOKEN = process.env.TG_MY_TOKEN || "8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50";
const MY_CHAT_ID = process.env.TG_MY_CHAT || "8724548311";
const GF_BOT_TOKEN = process.env.TG_GF_TOKEN || "8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc";
const GF_CHAT_ID = process.env.TG_GF_CHAT || "8624466505";
const KAKAO_REST_KEY = process.env.KAKAO_REST_KEY || "8987f9dd586416344444c7a59b5f0e73";
// ★ AUDIT FIX: S-02 — CF 인증용 시크릿 (firebase functions:config:set app.secret="YOUR_SECRET")
const CF_SECRET = (functions.config().app || {}).secret || process.env.CF_SECRET || "";

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

// ═══ Tuya 디바이스 이벤트 로그 조회 (DP report) ═══
// 1분 폴링으로 놓치는 짧은 이벤트(문 열림 등)를 로그로 잡음
async function getDeviceEventLogs(accessId, accessSecret, token, deviceId, startMs, endMs) {
  const t = Date.now().toString();
  const path = "/v1.0/devices/" + deviceId + "/logs?start_time=" + startMs
    + "&end_time=" + endMs + "&type=7&size=50";
  const sign = tuyaSign(accessId, accessSecret, t, token, "GET", path, "");

  const {data} = await axios.get(TUYA_BASE + path, {
    headers: {
      client_id: accessId,
      access_token: token,
      sign, t,
      sign_method: "HMAC-SHA256",
    },
    timeout: 10000,
  });

  if (!data.success) {
    console.warn("DeviceLogs fail:", JSON.stringify(data));
    return [];
  }
  const result = data.result || {};
  return result.logs || result.list || [];
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

// ═══ 스탠드(20A) 제어 — 전원순환으로 모드 변경 ═══
// 모드: 1단계→2단계→3단계→꺼짐 (항상 3단계 사용)
// 끄기: 1번 순환 (3단계→꺼짐)
// 켜기: 3번 순환 (꺼짐→1→2→3단계)
async function deskLightCycle(count) {
  try {
    const {accessId, accessSecret} = getConfig();
    const deskPlugId = "ebeaff0f5a69754067yfdv";
    const token = await getTuyaToken(accessId, accessSecret);
    for (let i = 0; i < count; i++) {
      await sendTuyaCommand(accessId, accessSecret, token, deskPlugId,
        [{code: "switch_1", value: false}]);
      await new Promise((r) => setTimeout(r, 800));
      await sendTuyaCommand(accessId, accessSecret, token, deskPlugId,
        [{code: "switch_1", value: true}]);
      if (i < count - 1) await new Promise((r) => setTimeout(r, 800));
    }
    console.log("DeskLight cycle x" + count);
  } catch (e) {
    console.error("deskLightCycle error:", e.message);
  }
}

async function setDeskLight(on) {
  await deskLightCycle(on ? 3 : 1);
}

async function pollDoorLogic() {
  const {accessId, accessSecret, deviceId} = getConfig();

  // ═══ Tuya API 호출 (쿼터 초과 시 fallback) ═══
  let token = null;
  let statusArr = [];
  let tuyaApiOk = false;
  let doorContactState = null;

  try {
    token = await getTuyaToken(accessId, accessSecret);
    statusArr = await getDeviceStatus(accessId, accessSecret, token, deviceId);
    tuyaApiOk = true;
    for (const s of statusArr) {
      if (s.code === "doorcontact_state") {
        doorContactState = s.value;
      }
    }
  } catch (e) {
    console.warn("Tuya API failed (quota?), using Firestore fallback:", e.message);
  }

  // Read IoT doc (Tuya 성공 여부와 무관하게 항상 읽기)
  const todayRef = db.doc("users/" + UID + "/data/iot");
  const doc = await todayRef.get();
  const iotData = doc.exists ? doc.data() : {};
  const currentDoor = iotData.door || {};
  const iotConfig = iotData.config || {};

  const isOpen = doorContactState; // null이면 도어센서 못 읽은 것

  if (isOpen === null && !tuyaApiOk) {
    console.log("Door sensor unavailable.");
  }

  const stateChanged = isOpen !== null &&
    (currentDoor.isOpen === undefined || currentDoor.isOpen !== isOpen);

  const doorUpdate = {};
  if (isOpen !== null) {
    doorUpdate.isOpen = isOpen;
    doorUpdate.state = isOpen ? "open" : "closed";
    doorUpdate.lastPolled = admin.firestore.FieldValue.serverTimestamp();
    doorUpdate.sensorId = "front_door";
    if (stateChanged) {
      doorUpdate.lastChanged = admin.firestore.FieldValue.serverTimestamp();
    }
  }

  // ═══ 문 열림 일별 추적 — 이벤트 로그 기반 (폴링 놓침 방지) ═══
  const todayDateStr = kstStudyDate();
  const prevOpenedDate = currentDoor.openedDate || "";

  // 날짜 넘어가면 리셋
  if (prevOpenedDate !== todayDateStr) {
    doorUpdate.openedToday = false;
    doorUpdate.openedDate = todayDateStr;
    doorUpdate.firstOpenTime = null;
  }

  // 1) 현재 열려있으면 당연히 openedToday
  if (isOpen) {
    doorUpdate.openedToday = true;
    doorUpdate.openedDate = todayDateStr;
    if (!currentDoor.firstOpenTime || prevOpenedDate !== todayDateStr) {
      const kstT = new Date(Date.now() + 9 * 60 * 60 * 1000);
      doorUpdate.firstOpenTime = String(kstT.getUTCHours()).padStart(2, "0") + ":" +
        String(kstT.getUTCMinutes()).padStart(2, "0");
    }
  }

  // 2) ★ 핵심: Tuya 이벤트 로그로 폴링 사이 놓친 문 열림 잡기
  if (!doorUpdate.openedToday && !(currentDoor.openedToday && prevOpenedDate === todayDateStr)) {
    try {
      const now = Date.now();
      const twoMinAgo = now - 2 * 60 * 1000;
      const logs = await getDeviceEventLogs(accessId, accessSecret, token, deviceId, twoMinAgo, now);

      let firstOpenTs = null;
      for (const log of logs) {
        if (log.code === "doorcontact_state") {
          // value는 boolean, string, 또는 "true"/"false" 모두 대응
          const val = log.value === true || log.value === "true";
          if (val) {
            const ts = log.event_time || log.time || log.t;
            if (ts && (!firstOpenTs || ts < firstOpenTs)) firstOpenTs = ts;
          }
        }
      }

      if (firstOpenTs) {
        // ★ 4AM 이전 이벤트는 어제 기록 → 무시
        const kstT = new Date(firstOpenTs + 9 * 60 * 60 * 1000);
        const evtHour = kstT.getUTCHours();
        const evtDate = kstStudyDate(kstT);
        if (evtDate === todayDateStr) {
          doorUpdate.openedToday = true;
          doorUpdate.openedDate = todayDateStr;
          if (!currentDoor.firstOpenTime || prevOpenedDate !== todayDateStr) {
            doorUpdate.firstOpenTime = String(evtHour).padStart(2, "0") + ":" +
              String(kstT.getUTCMinutes()).padStart(2, "0");
          }
          console.log("Door open caught from event log:", doorUpdate.firstOpenTime);
        } else {
          console.log("Door event log ignored — event date " + evtDate + " != today " + todayDateStr);
        }
      }
    } catch (e) {
      console.warn("Door event log check failed (fallback to poll):", e.message);
    }
  }

  // 이전 openedToday 보존 (이미 true면 유지)
  if (currentDoor.openedToday && prevOpenedDate === todayDateStr && !doorUpdate.openedToday) {
    doorUpdate.openedToday = true;
    doorUpdate.openedDate = todayDateStr;
    if (currentDoor.firstOpenTime) doorUpdate.firstOpenTime = currentDoor.firstOpenTime;
  }

  await todayRef.set({door: doorUpdate}, {merge: true});

  // ═══ 기상 감지 ═══
  let wakeTime = null;
  const doorMerged = {...currentDoor, ...doorUpdate};
  if (doorMerged.openedToday) {
    wakeTime = await checkWakeAndNotify(doc, doorMerged.firstOpenTime);
  }

  // ═══ 외출 20분 확정 체크 ═══
  let outingTime = null;
  outingTime = await checkMovementPending(doc);

  return {success: true, isOpen, stateChanged, wakeTime, outingTime, raw: statusArr};
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

  // Phase D: today doc + history for bedTime lookback
  // study doc read kept as fallback for multi-day lookback
  const studyDoc2 = await db.doc("users/" + UID + "/data/study").get();
  const allTr2 = (studyDoc2.exists ? studyDoc2.data() : {}).timeRecords || {};
  // Also check today doc for current day bedTime
  const todayDocCheck = await db.doc("users/" + UID + "/data/today").get();
  const todayDataCheck = todayDocCheck.exists ? todayDocCheck.data() : {};
  const todayTrCheck = todayDataCheck.timeRecords || {};
  if (todayDataCheck.date === dateStr && todayTrCheck.bedTime) {
    allTr2[dateStr] = {...(allTr2[dateStr] || {}), bedTime: todayTrCheck.bedTime};
  }
  if (todayDataCheck.date === dateStr && todayTrCheck.wake) {
    allTr2[dateStr] = {...(allTr2[dateStr] || {}), wake: todayTrCheck.wake};
  }
  let lastBedDate = null;
  for (let i = 0; i < 4; i++) {
    const d = kstStudyDate(new Date(kstNow.getTime() - i * 24 * 60 * 60 * 1000));
    if (allTr2[d]?.bedTime) { lastBedDate = d; break; }
  }
  if (!lastBedDate) {
    if (allTr2[dateStr]?.wake) {
      return null;
    }
    console.log("Wake fallback — no bedTime but allowing wake for " + dateStr);
  } else {
    for (let i = 0; i < 4; i++) {
      const d = kstStudyDate(new Date(kstNow.getTime() - i * 24 * 60 * 60 * 1000));
      if (d > lastBedDate && allTr2[d]?.wake) {
        console.log("Wake skip — already woke on " + d + " after bedTime on " + lastBedDate);
        return null;
      }
    }
  }

  // ★ 기상 시각: 첫 문 열림 시간 사용 (7시 이전이면 현재 시간)
  let timeStr;
  if (firstOpenTime) {
    const fp = firstOpenTime.split(":").map(Number);
    // 4AM 이전 firstOpenTime은 어제 잔존 → 현재 시간 사용
    timeStr = (fp[0] >= 7) ? firstOpenTime
      : String(kstHour).padStart(2, "0") + ":" + String(kstMin).padStart(2, "0");
  } else {
    timeStr = String(kstHour).padStart(2, "0") + ":" + String(kstMin).padStart(2, "0");
  }

  // 오늘 wake 이미 기록되었는지 확인
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  // ★ FIX: today doc flat 구조 — date가 오늘인 경우만 유효 (어제 잔존 방지)
  const todayTr = todayData.timeRecords || {};
  const isTodayDoc = todayData.date === dateStr;
  if ((isTodayDoc && todayTr.wake) || todayTr[dateStr]?.wake) return null; // 이미 기상 기록됨

  // Phase D: today doc only (single source of truth)
  const todayRef = db.doc("users/" + UID + "/data/today");
  await todayRef.update({"timeRecords.wake": timeStr, "date": dateStr})
    .catch(() => todayRef.set({timeRecords: {wake: timeStr}, date: dateStr}, {merge: true}));

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

  console.log("Movement pending: type=" + movement.type + " leftAtLocal=" + movement.leftAtLocal);

  const leftAt = movement.leftAt; // Firestore Timestamp
  if (!leftAt || !leftAt.toDate) {
    console.log("Movement: leftAt missing or invalid");
    return null;
  }

  const leftTime = leftAt.toDate();
  const now = new Date();
  const diffMin = (now - leftTime) / (1000 * 60);

  if (diffMin < 20) {
    console.log("Movement: " + Math.round(diffMin) + "min elapsed (need 20)");
    return null;
  }
  console.log("Movement: confirming outing after " + Math.round(diffMin) + "min");

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

  // Phase D: today doc only
  const todayRef2 = db.doc("users/" + UID + "/data/today");
  await todayRef2.update({"timeRecords.outing": outTimeStr, "date": dateStr})
    .catch(() => todayRef2.set({timeRecords: {outing: outTimeStr}, date: dateStr}, {merge: true}));

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
    "movement.date": kstStudyDate(),
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

// ★ AUDIT FIX: CF-01 — TODO: 폴링 간격을 상태에 따라 동적 조절 (야간 5분, 주간 2분) 또는 Tuya Webhook 전환
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

// ★ AUDIT FIX: CF-02 — TODO: 모놀리식 15+ 분기를 기능별 함수로 분리 또는 라우터 패턴 적용
// Manual test endpoint
exports.checkDoorManual = functions.https.onRequest(async (req, res) => {
  // ★ AUDIT FIX: S-02 — secret 파라미터 검증 (설정 안 된 경우 경고만, 차단 안 함)
  if (CF_SECRET && req.query.secret !== CF_SECRET) {
    console.warn("Unauthorized request from " + (req.ip || "unknown"));
    res.status(403).json({error: "unauthorized"});
    return;
  }
  try {
    // ?q=config&key=bedThresholdCm&value=400 → iot config 설정
    if (req.query.q === "config") {
      const key = req.query.key;
      const value = req.query.value;
      if (!key) { res.status(400).json({error: "key required"}); return; }
      const numVal = Number(value);
      await db.doc("users/" + UID + "/data/iot").set(
        {config: {[key]: isNaN(numVal) ? value : numVal}}, {merge: true});

      res.status(200).json({ok: true, key, value: isNaN(numVal) ? value : numVal});
      return;
    }
    // ?q=light&on=true/false&device=16a/20a → 플러그 제어
    if (req.query.q === "light") {
      const device = req.query.device || "16a";
      // on 파라미터 없으면 → 상태 조회만 (제어 안 함)
      if (req.query.on === undefined) {
        if (device === "20a") {
          const {accessId, accessSecret} = getConfig();
          const deskPlugId = "ebeaff0f5a69754067yfdv";
          const token = await getTuyaToken(accessId, accessSecret);
          const statusArr = await getDeviceStatus(accessId, accessSecret, token, deskPlugId);
          const sw = statusArr.find((s) => s.code === "switch_1");
          res.status(200).json({ok: true, device: "20a", light: sw && sw.value ? "ON" : "OFF"});
        } else {
          const {accessId, accessSecret} = getConfig();
          const plugId = process.env.TUYA_PLUG_16A_DEVICE_ID;
          const token = await getTuyaToken(accessId, accessSecret);
          const statusArr = await getDeviceStatus(accessId, accessSecret, token, plugId);
          const sw = statusArr.find((s) => s.code === "switch_1");
          res.status(200).json({ok: true, device: "16a", light: sw && sw.value ? "ON" : "OFF"});
        }
        return;
      }
      const on = req.query.on !== "false";
      if (device === "20a") {
        // 20A: 단순 on/off (스탠드/충전기)
        const {accessId, accessSecret} = getConfig();
        const deskPlugId = "ebeaff0f5a69754067yfdv";
        const token = await getTuyaToken(accessId, accessSecret);
        await sendTuyaCommand(accessId, accessSecret, token, deskPlugId,
          [{code: "switch_1", value: on}]);
        res.status(200).json({ok: true, device: "20a", light: on ? "ON" : "OFF"});
      } else {
        await setLight(on);
        res.status(200).json({ok: true, device: "16a", light: on ? "ON" : "OFF"});
      }
      return;
    }
    // ?q=date&doc=today/iot → 해당 doc 전체 조회
    // ?q=date&date=2026-03-20 → study doc timeRecords 조회
    if (req.query.q === "date") {
      if (req.query.doc === "today") {
        const todayDoc = await db.doc("users/" + UID + "/data/today").get();
        res.status(200).json(todayDoc.exists ? todayDoc.data() : {});
        return;
      }
      // history/YYYY-MM 지원
      const histDateMatch = (req.query.doc || "").match(/^history\/(\d{4}-\d{2})$/);
      if (histDateMatch) {
        const histDoc = await db.doc("users/" + UID + "/history/" + histDateMatch[1]).get();
        res.status(200).json(histDoc.exists ? histDoc.data() : {});
        return;
      }
      if (req.query.doc === "iot") {
        const iotDoc = await db.doc("users/" + UID + "/data/iot").get();
        const d = iotDoc.exists ? iotDoc.data() : {};
        res.status(200).json({presence: d.presence, door: d.door, phone: d.phone, movement: d.movement, config: d.config, agent: d.agent});
        return;
      }
      const qDate = req.query.date || kstStudyDate();
      const studyDoc = await db.doc("users/" + UID + "/data/study").get();
      const studyData = studyDoc.exists ? studyDoc.data() : {};
      const tr = (studyData.timeRecords || {})[qDate];
      // ★ 전체 study doc 반환 (studyTimeRecords, studyTime 등 포함)
      res.status(200).json(studyData);
      return;
    }
    // ?q=set&date=2026-03-20&field=bedTime&value=05:30 → timeRecords 수정
    // ?q=set&date=2026-03-21&field=bedTime&value=__DELETE__ → 필드 삭제
    if (req.query.q === "set") {
      const qDate = req.query.date;
      const field = req.query.field;
      const value = req.query.value;
      if (!qDate || !field) { res.status(400).json({error: "date, field required"}); return; }
      const isDel = value === "__DELETE__";
      const fv = isDel ? admin.firestore.FieldValue.delete() : value;
      // Phase D: today doc only (single source of truth)
      const fieldMap = {wakeTime: "wake", outingTime: "outing"};
      const appField = fieldMap[field];
      const writes = [
        db.doc("users/" + UID + "/data/today").update({["timeRecords." + field]: isDel ? admin.firestore.FieldValue.delete() : fv}).catch(() => {}),
      ];
      if (appField) {
        writes.push(db.doc("users/" + UID + "/data/today").update({
          ["timeRecords." + appField]: isDel ? admin.firestore.FieldValue.delete() : fv
        }).catch(() => {}));
      }
      // ★ outingTime 설정 시 iot.movement도 outing으로 동기화
      if (field === "outingTime" && !isDel) {
        writes.push(db.doc("users/" + UID + "/data/iot").update({
          "movement.type": "outing",
          "movement.pending": true,
          "movement.leftAtLocal": value,
          "movement.leftAt": admin.firestore.FieldValue.serverTimestamp(),
          "movement.date": kstStudyDate(),
        }).catch(() => {}));
      }
      // ★ returnHome 설정 시 iot.movement를 home으로
      if (field === "returnHome" && !isDel) {
        writes.push(db.doc("users/" + UID + "/data/iot").update({
          "movement.type": "home",
          "movement.pending": false,
          "movement.returnedAtLocal": value,
          "movement.date": kstStudyDate(),
        }).catch(() => {}));
      }
      await Promise.all(writes);
      res.status(200).json({ok: true, date: qDate, field, value: isDel ? "DELETED" : value});
      return;
    }

    // ═══ 범용 Firestore 읽기 ═══
    // ?q=read&doc=today|study|iot&field=studyTime.total
    if (req.query.q === "read") {
      const docName = req.query.doc || "today";
      const field = req.query.field;
      const allowed = {today: "data/today", study: "data/study", iot: "data/iot"};
      // history/YYYY-MM 지원
      const histReadMatch = docName.match(/^history\/(\d{4}-\d{2})$/);
      if (histReadMatch) allowed[docName] = "history/" + histReadMatch[1];
      // life_logs/YYYY-MM-DD 지원 (합의 26)
      const llReadMatch = docName.match(/^life_logs\/(\d{4}-\d{2}-\d{2})$/);
      if (llReadMatch) allowed[docName] = "life_logs/" + llReadMatch[1];
      if (!allowed[docName]) { res.status(400).json({error: "doc must be today|study|iot|history/YYYY-MM|life_logs/YYYY-MM-DD"}); return; }
      const snap = await db.doc("users/" + UID + "/" + allowed[docName]).get();
      if (!snap.exists) { res.status(200).json({}); return; }
      if (!field) { res.status(200).json(snap.data()); return; }
      // dot-notation 필드 탐색
      const parts = field.split(".");
      let val = snap.data();
      for (const p of parts) {
        if (val == null || typeof val !== "object") { val = null; break; }
        val = val[p];
      }
      res.status(200).json({field, value: val !== undefined ? val : null});
      return;
    }

    // ═══ 범용 Firestore 쓰기 ═══
    // ?q=write&doc=today|study&field=studyTime.total&value=120
    // value: 숫자면 parseInt/parseFloat, JSON이면 parse, 아니면 string
    if (req.query.q === "write") {
      const docName = req.query.doc || "today";
      const field = req.query.field;
      const rawValue = req.query.value;
      if (!field) { res.status(400).json({error: "field required"}); return; }
      const allowed = {today: "data/today", study: "data/study", iot: "data/iot"};
      // history/YYYY-MM 지원
      const histMatch = docName.match(/^history\/(\d{4}-\d{2})$/);
      if (histMatch) allowed[docName] = "history/" + histMatch[1];
      // life_logs/YYYY-MM-DD 지원 (HB 세션 기입 전용 · 2026-04-24 합의 26)
      const llMatch = docName.match(/^life_logs\/(\d{4}-\d{2}-\d{2})$/);
      if (llMatch) allowed[docName] = "life_logs/" + llMatch[1];
      if (!allowed[docName]) { res.status(400).json({error: "doc must be today|study|iot|history/YYYY-MM|life_logs/YYYY-MM-DD"}); return; }

      // 타입 자동 변환 (__DELETE__ → FieldValue.delete())
      let parsed;
      if (rawValue === "__DELETE__") parsed = admin.firestore.FieldValue.delete();
      else if (rawValue === "true") parsed = true;
      else if (rawValue === "false") parsed = false;
      else if (rawValue === "null") parsed = null;
      else if (!isNaN(rawValue) && rawValue !== "") {
        parsed = rawValue.includes(".") ? parseFloat(rawValue) : parseInt(rawValue, 10);
      } else {
        try { parsed = JSON.parse(rawValue); } catch (_) { parsed = rawValue; }
      }

      const docRef = db.doc("users/" + UID + "/" + allowed[docName]);

      // ★ __SET__ 모드: 전체 doc 덮어쓰기 (rollover용)
      if (field === "__SET__") {
        await docRef.set(parsed);
        res.status(200).json({ok: true, doc: docName, mode: "set"});
        return;
      }
      // dot-notation → Firestore set merge (중첩 필드 지원 + doc 부재 시 자동 생성)
      await docRef.set({[field]: parsed}, {merge: true});

      // Phase D: dual-write removed. today doc is single source of truth.
      // study doc mirror removed (2026-04-03)

      res.status(200).json({ok: true, doc: docName, field, value: rawValue === "__DELETE__" ? "__DELETED__" : parsed});
      return;
    }

    // ═══ life_logs 배열 필드 append ═══ (합의 28 · 2026-04-24)
    // ?q=append&doc=life_logs/2026-04-24&field=study&value={"time":"18:00",...}
    // value 는 JSON object/array. 기존 배열에 arrayUnion 으로 추가.
    // set+merge 의 배열 덮어쓰기 문제 해결 + dedup.
    if (req.query.q === "append") {
      const docName = req.query.doc || "";
      const field = req.query.field;
      const rawValue = req.query.value;
      if (!field) { res.status(400).json({error: "field required"}); return; }
      if (!rawValue) { res.status(400).json({error: "value required (JSON)"}); return; }

      // doc 화이트리스트 (write 와 동일)
      const allowed = {today: "data/today", study: "data/study", iot: "data/iot"};
      const histMatch = docName.match(/^history\/(\d{4}-\d{2})$/);
      if (histMatch) allowed[docName] = "history/" + histMatch[1];
      const llMatch = docName.match(/^life_logs\/(\d{4}-\d{2}-\d{2})$/);
      if (llMatch) allowed[docName] = "life_logs/" + llMatch[1];
      if (!allowed[docName]) {
        res.status(400).json({error: "doc must be today|study|iot|history/YYYY-MM|life_logs/YYYY-MM-DD"});
        return;
      }

      let entry;
      try { entry = JSON.parse(rawValue); }
      catch (e) { res.status(400).json({error: "value must be valid JSON: " + e.message}); return; }

      const docRef = db.doc("users/" + UID + "/" + allowed[docName]);
      const elements = Array.isArray(entry) ? entry : [entry];
      await docRef.set(
        {[field]: admin.firestore.FieldValue.arrayUnion(...elements)},
        {merge: true}
      );
      res.status(200).json({ok: true, doc: docName, field, appended: elements.length});
      return;
    }

    // ═══ 범용 Firestore 필드 삭제 ═══
    // ?q=delete&doc=today|study&field=studyTime.subjects.test
    if (req.query.q === "delete") {
      const docName = req.query.doc || "today";
      const field = req.query.field;
      if (!field) { res.status(400).json({error: "field required"}); return; }
      const allowed = {today: "data/today", study: "data/study", iot: "data/iot"};
      if (!allowed[docName]) { res.status(400).json({error: "doc must be today|study|iot"}); return; }
      const docRef = db.doc("users/" + UID + "/" + allowed[docName]);
      await docRef.update({[field]: admin.firestore.FieldValue.delete()});
      res.status(200).json({ok: true, doc: docName, field, deleted: true});
      return;
    }

    // ═══ 포커스 세션 추가 ═══
    // ?q=focus&action=add&subject=경제학&start=10:00&end=11:30&studyMin=80&lectureMin=0&restMin=10&date=2026-03-24
    if (req.query.q === "focus") {
      const action = req.query.action;
      if (action !== "add") { res.status(400).json({error: "action must be 'add'"}); return; }
      const subject = req.query.subject;
      const startTime = req.query.start;
      const endTime = req.query.end || "";
      const studyMin = parseInt(req.query.studyMin || "0", 10);
      const lectureMin = parseInt(req.query.lectureMin || "0", 10);
      const restMin = parseInt(req.query.restMin || "0", 10);
      const date = req.query.date || kstStudyDate();
      if (!subject || !startTime) { res.status(400).json({error: "subject, start required"}); return; }

      const sessionId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
      const session = {
        id: sessionId,
        subject: subject,
        startTime: startTime,
        endTime: endTime,
        studyMinutes: studyMin,
        lectureMinutes: lectureMin,
        restMinutes: restMin,
        date: date,
      };

      // Phase D: today doc only (single source of truth)
      const todayRef = db.doc("users/" + UID + "/data/today");
      const todaySnap = await todayRef.get();
      const todayData2 = todaySnap.exists ? todaySnap.data() : {};
      const st = todayData2.studyTime || {};
      const subjects = st.subjects || {};
      const newTotal = (st.total || 0) + studyMin;
      const newSubject = (subjects[subject] || 0) + studyMin;

      await todayRef.set({
        "studyTime.total": newTotal,
        ["studyTime.subjects." + subject]: newSubject,
      }, {merge: true});

      res.status(200).json({ok: true, session, studyTime: {total: newTotal, subjects: {...subjects, [subject]: newSubject}}});
      return;
    }

    // ═══ 투두 추가 ═══
    // ?q=todo&action=add&title=미시경제+1장&subject=경제학&priority=1&date=2026-03-24
    if (req.query.q === "todo") {
      const action = req.query.action;
      if (action !== "add") { res.status(400).json({error: "action must be 'add'"}); return; }
      const title = req.query.title;
      const subject = req.query.subject || "";
      const priority = parseInt(req.query.priority || "0", 10);
      const date = req.query.date || kstStudyDate();
      if (!title) { res.status(400).json({error: "title required"}); return; }

      const todoId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
      const todo = {
        id: todoId,
        title: title,
        completed: false,
        subject: subject,
        priority: priority,
        type: "daily",
      };

      // Phase D: today doc only (single source of truth)
      const todayRef = db.doc("users/" + UID + "/data/today");
      const todaySnap = await todayRef.get();
      const todayData = todaySnap.exists ? todaySnap.data() : {};
      const todayTodos = todayData.todos || [];
      todayTodos.push(todo);
      await todayRef.set({todos: todayTodos}, {merge: true});

      res.status(200).json({ok: true, todo, date});
      return;
    }

    // ═══ 습관 체크 ═══
    // ?q=habit&action=check&habitId=abc123&date=2026-03-24
    if (req.query.q === "habit") {
      const action = req.query.action;
      if (action !== "check") { res.status(400).json({error: "action must be 'check'"}); return; }
      const habitId = req.query.habitId;
      const date = req.query.date || kstStudyDate();
      if (!habitId) { res.status(400).json({error: "habitId required"}); return; }

      // today doc의 orderData.habits 배열에서 해당 습관 찾아 completedDates에 추가
      const todayRef = db.doc("users/" + UID + "/data/today");
      const todaySnap = await todayRef.get();
      const todayData = todaySnap.exists ? todaySnap.data() : {};
      const orderData = todayData.orderData || {};
      const habits = orderData.habits || [];
      let found = false;
      for (const h of habits) {
        if (h.id === habitId) {
          if (!h.completedDates) h.completedDates = [];
          if (!h.completedDates.includes(date)) {
            h.completedDates.push(date);
          }
          found = true;
          break;
        }
      }
      if (!found) { res.status(404).json({error: "habit not found: " + habitId}); return; }
      await todayRef.set({orderData: {...orderData, habits}}, {merge: true});
      res.status(200).json({ok: true, habitId, date, checked: true});
      return;
    }

    // ═══ 시간 기록 (timeRecords) ═══
    // ?q=timerecord&field=wakeTime&value=07:30&date=2026-03-24
    if (req.query.q === "timerecord") {
      const field = req.query.field;
      const value = req.query.value;
      const date = req.query.date || kstStudyDate();
      if (!field) { res.status(400).json({error: "field required"}); return; }
      const isDel = value === "__DELETE__";
      const fv = isDel ? admin.firestore.FieldValue.delete() : value;
      // Phase D: today doc only
      await db.doc("users/" + UID + "/data/today").update({["timeRecords." + field]: isDel ? admin.firestore.FieldValue.delete() : fv}).catch(() => {});
      res.status(200).json({ok: true, date, field, value: isDel ? "DELETED" : value});
      return;
    }

    // ═══ 알려진 학습 장소 (체류 감지용) ═══
    const STUDY_PLACES = [
      {name: "스카", lat: 37.5596, lng: 126.9453, radius: 150},  // 이대앞 스터디카페
    ];
    function haversineM(lat1, lng1, lat2, lng2) {
      const R = 6371000;
      const toRad = d => d * Math.PI / 180;
      const dLat = toRad(lat2 - lat1), dLng = toRad(lng2 - lng1);
      const a = Math.sin(dLat/2)**2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng/2)**2;
      return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    }
    function findStudyPlace(lat, lng) {
      for (const p of STUDY_PLACES) {
        if (haversineM(lat, lng, p.lat, p.lng) <= p.radius) return p.name;
      }
      return null;
    }

    // ═══ OwnTracks 위치 기반 외출/귀가 감지 ═══
    // ?q=movement_check → cndstatus Firestore에서 isHome 읽기 → 상태 변경 시 기록
    if (req.query.q === "movement_check") {
      const CND_PROJECT = "cndstatus-ad114";
      const CND_KEY = "AIzaSyCJpRU73rCVobvW5saMrInxJuLW1HHMr5E";
      const cndUrl = `https://firestore.googleapis.com/v1/projects/${CND_PROJECT}/databases/(default)/documents/locations/cheonhong?key=${CND_KEY}`;
      const cndResp = await fetch(cndUrl);
      if (!cndResp.ok) { res.status(502).json({error: "cndstatus read fail"}); return; }
      const cndDoc = await cndResp.json();
      const f = cndDoc.fields || {};
      const isHome = f.isHome?.booleanValue ?? true;
      const lat = f.lat?.doubleValue;
      const lng = f.lng?.doubleValue;
      const battery = parseInt(f.battery?.integerValue ?? "-1");
      const ts = f.timestamp?.timestampValue;

      // 현재 movement 상태 읽기
      const iotSnap = await db.doc("users/" + UID + "/data/iot").get();
      const iotData = iotSnap.exists ? iotSnap.data() : {};
      const mv = iotData.movement || {};
      const wasHome = mv.type === "home" || !mv.type;
      const nowHome = isHome;
      const date = kstStudyDate();
      const timeStr = new Date(ts || Date.now()).toLocaleTimeString("ko-KR", {timeZone: "Asia/Seoul", hour: "2-digit", minute: "2-digit", hour12: false});

      const result = {isHome, wasHome: wasHome, lat, lng, battery, timestamp: ts, changed: false};

      // 외출 감지: wasHome → !nowHome
      if (wasHome && !nowHome) {
        await Promise.all([
          db.doc("users/" + UID + "/data/iot").update({
            "movement.type": "outing", "movement.pending": true,
            "movement.leftAtLocal": timeStr,
            "movement.leftAt": admin.firestore.FieldValue.serverTimestamp(),
            "movement.date": date,
          }),
          db.doc("users/" + UID + "/data/today").update({"timeRecords.outingTime": timeStr, "timeRecords.outing": timeStr}),
        ]);
        result.changed = true;
        result.action = "outing";
        result.time = timeStr;
      }

      // 체류 감지: 외출 중 + 학습 장소 근처 → studying
      if (!nowHome && lat && lng) {
        const studyPlace = findStudyPlace(lat, lng);
        if (studyPlace && mv.type === "outing") {
          await db.doc("users/" + UID + "/data/iot").update({
            "movement.type": "studying",
            "movement.locationName": studyPlace,
            "movement.studyingSince": timeStr,
            "movement.date": date,
          });
          result.changed = true;
          result.action = "studying";
          result.place = studyPlace;
          result.time = timeStr;
        }
      }

      // 귀가 감지: !wasHome → nowHome
      if (!wasHome && nowHome) {
        await Promise.all([
          db.doc("users/" + UID + "/data/iot").update({
            "movement.type": "home", "movement.pending": false,
            "movement.returnedAtLocal": timeStr,
            "movement.date": date,
          }),
          db.doc("users/" + UID + "/data/today").update({"timeRecords.returnHome": timeStr}),
        ]);
        result.changed = true;
        result.action = "return";
        result.time = timeStr;
      }

      res.status(200).json(result);
      return;
    }

    // ═══ 이동 추적 로그 ═══
    // ?q=transit_log&place=스카&lat=37.5594&lng=126.945&vel=25&tst=1234567890&batt=80
    // cndstatus Worker에서 매 위치 업데이트마다 호출
    if (req.query.q === "transit_log") {
      const place = req.query.place || null; // 현재 장소 (빈 문자열 = 이동 중)
      const lat = parseFloat(req.query.lat || "0");
      const lng = parseFloat(req.query.lng || "0");
      const vel = parseInt(req.query.vel || "0", 10);
      const tst = parseInt(req.query.tst || "0", 10);
      const batt = parseInt(req.query.batt || "-1", 10);
      const date = kstStudyDate();
      const timeStr = new Date(tst * 1000).toLocaleTimeString("ko-KR", {timeZone: "Asia/Seoul", hour: "2-digit", minute: "2-digit", hour12: false});
      const placeName = place && place.length > 0 ? place : null;

      // iot.transit 에서 현재 상태 읽기
      const iotRef = db.doc("users/" + UID + "/data/iot");
      const iotSnap = await iotRef.get();
      const iot = iotSnap.exists ? iotSnap.data() : {};
      const transit = iot.transit || {};
      const wasTransit = transit.inTransit || false;
      const nowTransit = !placeName; // 장소 없으면 이동 중

      const result = {place: placeName, vel, time: timeStr, wasTransit, nowTransit, changed: false};

      if (!wasTransit && nowTransit) {
        // 장소 → 이동 시작
        await iotRef.update({
          "transit.inTransit": true,
          "transit.startTime": timeStr,
          "transit.startTst": tst,
          "transit.fromPlace": transit.currentPlace || "?",
          "transit.currentPlace": null,
        });
        result.changed = true;
        result.action = "transit_start";
        result.from = transit.currentPlace || "?";
      } else if (wasTransit && !nowTransit) {
        // 이동 → 장소 도착
        const startTst = transit.startTst || tst;
        const durationMin = Math.round((tst - startTst) / 60);
        const segment = {
          from: transit.fromPlace || "?",
          to: placeName,
          startTime: transit.startTime || timeStr,
          endTime: timeStr,
          durationMin: durationMin,
          date: date,
        };
        // 오늘 이동 구간 리스트에 추가
        const segments = iot.transitSegments || {};
        const todaySegments = segments[date] || [];
        todaySegments.push(segment);

        await iotRef.update({
          "transit.inTransit": false,
          "transit.currentPlace": placeName,
          "transit.lastArrival": timeStr,
          [`transitSegments.${date}`]: todaySegments,
        });

        // today doc에도 이동시간 합계 기록
        const totalMin = todaySegments.reduce((s, seg) => s + (seg.durationMin || 0), 0);
        await db.doc("users/" + UID + "/data/today").update({
          "transitTime": totalMin,
          "transitSegments": todaySegments,
        }).catch(() => {});

        result.changed = true;
        result.action = "transit_end";
        result.segment = segment;
        result.totalMin = totalMin;

        // 학습 장소 도착 → movement.type = studying
        const sp = findStudyPlace(lat, lng);
        if (sp) {
          const mv2 = iot.movement || {};
          if (mv2.type === "outing" || mv2.type === "pending") {
            await iotRef.update({
              "movement.type": "studying",
              "movement.locationName": sp,
              "movement.studyingSince": timeStr,
              "movement.date": kstStudyDate(),
            });
            result.studyPlace = sp;
          }
        }
      } else if (!wasTransit && !nowTransit && placeName !== transit.currentPlace) {
        // 장소 변경 (이동 없이 — GPS 드리프트 또는 인접 장소)
        await iotRef.update({"transit.currentPlace": placeName});
      }

      // 마지막 위치 항상 업데이트
      await iotRef.update({
        "transit.lastLat": lat, "transit.lastLng": lng,
        "transit.lastVel": vel, "transit.lastTime": timeStr,
        "transit.lastBatt": batt,
      }).catch(() => {});

      res.status(200).json(result);
      return;
    }

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

    // ── 도어센서 → 기상 판정 (CF가 판단) ──
    const doorBefore = before.door || {};
    const doorAfter = after.door || {};
    if (doorAfter.state === "open" && doorBefore.state !== "open" && doorAfter.lastChanged) {
      await handleDoorWake(doorAfter);
    }

    // ── 귀가 감지: movement.type → "home" ──
    // cf_rollover 가 강제로 home 으로 reset 한 경우는 진짜 귀가가 아니므로 스킵
    if (mvAfter.type === "home" && mvBefore.type !== "home"
        && mvAfter.resetBy !== "cf_rollover") {
      await handleReturnHome(mvAfter, after);
    }

    // ── Geofence 직접 외출: source=geofence*, type → "out" ──
    if (mvAfter.type === "out" && mvBefore.type !== "out"
        && !mvAfter.pending
        && (mvAfter.source || "").startsWith("geofence")) {
      await handleGeofenceOuting(mvAfter, after);
    }
  });

// ═══ 도어센서 → 기상 판정 (CF가 판단) ═══
async function handleDoorWake(door) {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const hour = kstNow.getUTCHours();
  const dateStr = kstStudyDate(kstNow);
  const wakeTime = door.lastEventTime || String(hour).padStart(2, "0") + ":" + String(kstNow.getUTCMinutes()).padStart(2, "0");

  // 07:00~15:00만 기상 판정
  if (hour < 7 || hour >= 15) {
    console.log(`[DoorWake] outside wake window (${hour}h), skip`);
    return;
  }

  // 이미 wake 있으면 스킵
  const todayDoc = await db.doc("users/" + UID + "/data/today").get();
  const todayData = todayDoc.exists ? todayDoc.data() : {};
  const todayTr = todayData.timeRecords || {};
  if (todayTr.wake) {
    console.log(`[DoorWake] wake already recorded: ${todayTr.wake}`);
    return;
  }

  // ★ 기상 기록 — today doc only
  const todayRef = db.doc("users/" + UID + "/data/today");
  await todayRef.update({"timeRecords.wake": wakeTime, "date": dateStr})
    .catch(() => todayRef.set({timeRecords: {wake: wakeTime}, date: dateStr}, {merge: true}));

  // iot.door에 기상 판정 결과 기록
  await db.doc("users/" + UID + "/data/iot").update({
    "door.openedToday": true,
    "door.openedDate": dateStr,
    "door.firstOpenTime": wakeTime,
  }).catch(() => {});

  console.log(`[DoorWake] ★ Wake recorded: ${wakeTime} (${dateStr})`);
  await sendTelegram(`⏰ 자동 기상 ${wakeTime} (도어센서→CF판정)`, true);
}

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

  // Phase D: today doc only
  const todayRef3 = db.doc("users/" + UID + "/data/today");
  await todayRef3.update({"timeRecords.returnHome": returnTime, "date": dateStr})
    .catch(() => todayRef3.set({timeRecords: {returnHome: returnTime}, date: dateStr}, {merge: true}));

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

  // Phase D: today doc only
  const todayRef4 = db.doc("users/" + UID + "/data/today");
  await todayRef4.update({"timeRecords.outing": outTime, "date": dateStr})
    .catch(() => todayRef4.set({timeRecords: {outing: outTime}, date: dateStr}, {merge: true}));

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

  // 2. 공지사항 페이지 크롤링 (GCP IP 차단 → Google Cache 우회)
  let html;
  const targets = [
    // 1차: Google 웹 캐시
    `https://webcache.googleusercontent.com/search?q=cache:${encodeURIComponent(GOSI_BBS_URL)}`,
    // 2차: 직접 접속
    GOSI_BBS_URL,
  ];
  for (let i = 0; i < targets.length; i++) {
    try {
      const resp = await axios.get(targets[i], {
        timeout: 20000,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language": "ko-KR,ko;q=0.9",
        },
        maxRedirects: 5,
      });
      html = resp.data;
      if (html && html.includes("fn_egov_inqire_notice")) break;
    } catch (e) {
      console.log(`Gosi fetch target ${i} failed: ${e.message}`);
      if (i === targets.length - 1) throw e;
    }
  }

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
      // gosi.kr 클라우드 IP 차단 — PC 크론으로 대체됨. 에러 알림 불필요.
      console.log("Gosi poll skip (cloud IP blocked):", err.message);
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
    description: "방 전등(천장) 켜기/끄기",
    input_schema: {
      type: "object",
      properties: {
        on: {type: "boolean", description: "true=켜기, false=끄기"},
      },
      required: ["on"],
    },
  },
  {
    name: "set_desk_light",
    description: "책상 스탠드 켜기/끄기",
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
    description: "IoT 센서 전체 상태 조회 — 도어센서, 전등, 위치",
    input_schema: {type: "object", properties: {}, required: []},
  },
  {
    name: "query_sensor",
    description: "특정 Tuya 센서/기기 실시간 상태 직접 조회 (API 호출)",
    input_schema: {
      type: "object",
      properties: {
        device: {type: "string", enum: ["door", "plug_16a", "plug_20a"], description: "조회할 기기"},
      },
      required: ["device"],
    },
  },
  {
    name: "audit_today",
    description: "오늘 기록 감사. timeRecords(기상/외출/귀가/취침), IoT 로그, 이상 데이터 감지. 빠진 시간, 순서 역전, 의심 데이터 보고",
    input_schema: {type: "object", properties: {}, required: []},
  },
  {
    name: "query_date",
    description: "특정 날짜의 timeRecords 조회. 어제/그저께 등 과거 데이터 확인 가능",
    input_schema: {
      type: "object",
      properties: {
        date: {type: "string", description: "조회할 날짜 yyyy-MM-dd"},
      },
      required: ["date"],
    },
  },
  {
    name: "fix_timerecord",
    description: "timeRecords 시간 수정. 예: wake를 09:00으로 변경, bedTime 삭제(null)",
    input_schema: {
      type: "object",
      properties: {
        field: {type: "string", enum: ["wake", "outing", "returnHome", "study", "studyEnd", "bedTime", "meal"], description: "수정할 필드"},
        value: {type: "string", description: "새 값 (HH:mm 형식). 삭제하려면 'null'"},
      },
      required: ["field", "value"],
    },
  },
];

const AI_SYSTEM = `너는 CHEONHONG STUDIO 앱의 AI 비서야. 사용자(천홍)의 공부/루틴/IoT를 관리해.
오늘 날짜: ${kstStudyDate()}
간결하게 답하되 친근한 반말 사용. 이모지 적절히.
tool 호출이 필요하면 반드시 tool을 사용해. 일반 대화도 가능.

IoT 기기:
- 도어센서(door): 방문 열림/닫힘
- 16A 소켓(plug_16a): 방 전등(천장) ON/OFF
- 20A 소켓(plug_20a): 책상 스탠드 ON/OFF

"센서 상태" → iot_status, "전등 상태" → query_sensor(plug_16a)
"기록 확인" / "감사" → audit_today로 이상 데이터 감지 후 사용자에게 보고.
시간 수정 요청 시 반드시 사용자 확인 후 fix_timerecord 실행. 절대 자동 수정 금지.`;

// ── tool 실행 ──

async function executeTool(name, input) {
  const dateStr = kstStudyDate();

  if (name === "add_todo") {
    // Phase D: today doc only
    const todaySnap = await db.doc("users/" + UID + "/data/today").get();
    const todayData = todaySnap.exists ? todaySnap.data() : {};
    const items = todayData.todos || [];

    const newItem = {
      id: "todo_" + Date.now(),
      title: input.title,
      done: false,
      order: items.length,
    };
    if (input.subject) newItem.subject = input.subject;
    if (input.estimatedMinutes) newItem.estimatedMinutes = input.estimatedMinutes;
    if (input.priority) newItem.priority = input.priority;
    if (input.type) newItem.type = input.type;

    items.push(newItem);
    await db.doc("users/" + UID + "/data/today").set({todos: items}, {merge: true});
    return "✅ 투두 추가: " + input.title;
  }

  if (name === "add_habit") {
    // Phase D: today doc for orderData
    const todaySnap = await db.doc("users/" + UID + "/data/today").get();
    const data = todaySnap.exists ? todaySnap.data() : {};
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
    await db.doc("users/" + UID + "/data/today").set(
      {orderData: {...orderData, habits}}, {merge: true});
    const triggerLabel = input.autoTrigger
      ? {wake: "기상", sleep: "취침", study: "공부", outing: "외출", meal: "식사"}[input.autoTrigger] || ""
      : "";
    return "✅ 습관 추가: " + input.title + (triggerLabel ? " (" + triggerLabel + " 시 자동)" : "");
  }

  if (name === "add_goal") {
    // Phase D: today doc for orderData
    const todaySnap = await db.doc("users/" + UID + "/data/today").get();
    const data = todaySnap.exists ? todaySnap.data() : {};
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
    await db.doc("users/" + UID + "/data/today").set(
      {orderData: {...orderData, goals}}, {merge: true});
    return "✅ 목표 추가: " + input.title + " (" + input.totalUnits + (input.unitName || "강") + ")";
  }

  if (name === "today_summary") {
    // Phase D: today doc only
    const todaySnap = await db.doc("users/" + UID + "/data/today").get();
    const today = todaySnap.exists ? todaySnap.data() : {};
    const tr = today.timeRecords || {};
    const st = today.studyTime || {};
    const todos = today.todos || [];
    const doneTodos = todos.filter((t) => t.done || t.completed).length;

    let summary = "📊 오늘 요약\n";
    if (tr.wake) summary += "☀️ 기상: " + tr.wake + "\n";
    if (tr.outing) summary += "🚶 외출: " + tr.outing + (tr.returnHome ? " → 귀가 " + tr.returnHome : " (외출 중)") + "\n";
    if (tr.study) summary += "📖 공부: " + tr.study + (tr.studyEnd ? " → " + tr.studyEnd : " (진행 중)") + "\n";
    if (st.total) summary += "⏱ 순공: " + Math.floor(st.total / 60) + "h " + (st.total % 60) + "m\n";
    summary += "📋 투두: " + doneTodos + "/" + todos.length + "개 완료\n";
    if (tr.bedTime) summary += "🛏️ 취침: " + tr.bedTime;
    return summary;
  }

  if (name === "set_light") {
    await setLight(input.on);
    return input.on ? "💡 전등 켰어" : "🌙 전등 껐어";
  }

  if (name === "set_desk_light") {
    await setDeskLight(input.on);
    // 수동 OFF → 자동화 잠금 (책상 떠날 때까지)
    if (!input.on) {
      await db.doc("users/" + UID + "/data/iot").set(
        {"presence.deskLightLock": true}, {merge: true});
    } else {
      await db.doc("users/" + UID + "/data/iot").set(
        {"presence.deskLightLock": false}, {merge: true});
    }
    return input.on ? "💡 스탠드 켰어" : "🌙 스탠드 껐어 (자동 잠금)";
  }

  if (name === "list_todos") {
    // Phase D: today doc only
    const todaySnap = await db.doc("users/" + UID + "/data/today").get();
    const data = todaySnap.exists ? todaySnap.data() : {};
    const todos = data.todos || [];
    if (todos.length === 0) return "📋 오늘 투두 없음";
    return "📋 오늘 투두:\n" + todos.map((t, i) =>
      (t.completed ? "✅" : "⬜") + " " + t.title +
      (t.subject ? " [" + t.subject + "]" : "") +
      (t.estimatedMinutes ? " " + t.estimatedMinutes + "분" : "")
    ).join("\n");
  }

  if (name === "complete_todo") {
    // Phase D: today doc only
    const todaySnap = await db.doc("users/" + UID + "/data/today").get();
    const data = todaySnap.exists ? todaySnap.data() : {};
    const items = data.todos || [];
    const idx = items.findIndex((t) => !(t.done || t.completed) && t.title.includes(input.keyword));
    if (idx < 0) return "❌ '" + input.keyword + "' 투두 못 찾음";
    items[idx].done = true;
    items[idx].completedAt = new Date().toISOString();
    await db.doc("users/" + UID + "/data/today").set({todos: items}, {merge: true});
    return "✅ 완료: " + items[idx].title;
  }

  if (name === "iot_status") {
    const iotDoc = await db.doc("users/" + UID + "/data/iot").get();
    const iot = iotDoc.exists ? iotDoc.data() : {};
    const door = iot.door || {};
    const movement = iot.movement || {};

    let status = "🏠 IoT 상태\n";
    status += "🚪 도어: " + (door.state || "?") + (door.openedToday ? " (오늘 열림)" : "") + "\n";
    status += "💡 전등: Firestore에 없음 (query_sensor로 실시간 조회)\n";
    if (movement.type) status += "🚶 이동: " + movement.type + "\n";
    return status;
  }

  if (name === "query_sensor") {
    const deviceMap = {
      door: process.env.TUYA_DEVICE_ID,
      plug_16a: process.env.TUYA_PLUG_16A_DEVICE_ID,
      plug_20a: "ebeaff0f5a69754067yfdv",
    };
    const did = deviceMap[input.device];
    if (!did) return "❌ 기기 없음: " + input.device;

    const {accessId, accessSecret} = getConfig();
    const token = await getTuyaToken(accessId, accessSecret);
    const statusArr = await getDeviceStatus(accessId, accessSecret, token, did);

    const labels = {door: "🚪 도어센서", plug_16a: "💡 16A 소켓(전등)", plug_20a: "🔌 20A 소켓"};
    let result = labels[input.device] + " 실시간:\n";
    for (const s of statusArr) {
      result += "  " + s.code + ": " + s.value + "\n";
    }
    return result;
  }

  if (name === "audit_today") {
    const [todayDoc, iotDoc] = await Promise.all([
      db.doc("users/" + UID + "/data/today").get(),
      db.doc("users/" + UID + "/data/iot").get(),
    ]);
    const today = todayDoc.exists ? todayDoc.data() : {};
    const tr = today.timeRecords || {};
    const iot = iotDoc.exists ? iotDoc.data() : {};
    const door = iot.door || {};

    let report = "🔍 오늘 기록 감사\n\n";

    // 1. timeRecords 현황
    report += "📋 timeRecords:\n";
    const fields = ["wake", "outing", "returnHome", "study", "studyEnd", "meal", "bedTime"];
    for (const f of fields) {
      report += "  " + f + ": " + (tr[f] || "❌ 미기록") + "\n";
    }

    // 2. 이상 감지
    const issues = [];

    // 순서 역전 체크
    const timeToMin = (t) => { const p = (t || "").split(":").map(Number); return p[0] * 60 + p[1]; };
    if (tr.wake && tr.outing && timeToMin(tr.wake) > timeToMin(tr.outing)) {
      issues.push("⚠️ 기상(" + tr.wake + ") > 외출(" + tr.outing + ") 순서 역전");
    }
    if (tr.outing && tr.returnHome && timeToMin(tr.outing) > timeToMin(tr.returnHome)) {
      issues.push("⚠️ 외출(" + tr.outing + ") > 귀가(" + tr.returnHome + ") 순서 역전");
    }
    if (tr.wake && tr.bedTime && timeToMin(tr.wake) > timeToMin(tr.bedTime)) {
      issues.push("⚠️ 기상(" + tr.wake + ") > 취침(" + tr.bedTime + ") 순서 역전");
    }

    // 기상 시간 의심 (11시 이후)
    if (tr.wake && timeToMin(tr.wake) > 660) {
      issues.push("🤔 기상 " + tr.wake + " — 11시 이후, 실제 기상 시간 맞는지 확인 필요");
    }

    // 도어 첫 열림 vs 기상 시간 차이
    if (door.firstOpenTime && tr.wake) {
      const doorMin = timeToMin(door.firstOpenTime);
      const wakeMin = timeToMin(tr.wake);
      if (Math.abs(doorMin - wakeMin) > 30) {
        issues.push("🚪 문 첫 열림 " + door.firstOpenTime + " vs 기상 " + tr.wake + " — " + Math.abs(doorMin - wakeMin) + "분 차이");
      }
    }

    // 기상 미기록 (현재 7시 이후인데)
    const kstH = new Date(Date.now() + 9 * 60 * 60 * 1000).getUTCHours();
    if (!tr.wake && kstH >= 10) {
      issues.push("❌ 기상 미기록 (현재 " + kstH + "시)");
    }

    // 3. IoT 상태
    report += "\n🏠 IoT 현재:\n";
    report += "  🚪 문: " + (door.state || "?") + " (첫열림: " + (door.firstOpenTime || "없음") + ")\n";

    if (issues.length > 0) {
      report += "\n⚠️ 이상 감지 " + issues.length + "건:\n" + issues.join("\n");
    } else {
      report += "\n✅ 이상 없음";
    }

    return report;
  }

  if (name === "query_date") {
    const qDate = input.date;
    // Phase D: today doc for current date, history for past
    if (qDate === dateStr) {
      const todaySnap = await db.doc("users/" + UID + "/data/today").get();
      const todayData = todaySnap.exists ? todaySnap.data() : {};
      const tr = todayData.timeRecords || {};
      if (Object.keys(tr).length === 0) return "📅 " + qDate + " — 데이터 없음";
      let result = "📅 " + qDate + "\n";
      for (const [k, v] of Object.entries(tr)) {
        result += "  " + k + ": " + v + "\n";
      }
      return result;
    }
    // history fallback for past dates
    const parts = qDate.split("-");
    const monthKey = parts[0] + "-" + parts[1];
    const dayKey = parts[2];
    const histDoc = await db.doc("users/" + UID + "/history/" + monthKey).get();
    if (histDoc.exists) {
      const days = histDoc.data().days || {};
      const dayData = days[dayKey];
      if (dayData && dayData.timeRecords) {
        const htr = dayData.timeRecords;
        let result = "📅 " + qDate + " (history)\n";
        for (const [k, v] of Object.entries(htr)) {
          result += "  " + k + ": " + v + "\n";
        }
        return result;
      }
    }
    return "📅 " + qDate + " — 데이터 없음";
  }

  if (name === "fix_timerecord") {
    const val = input.value === "null" ? admin.firestore.FieldValue.delete() : input.value;
    const displayVal = input.value === "null" ? "삭제" : input.value;

    // Phase D: today doc only
    const todayRef = db.doc("users/" + UID + "/data/today");
    await todayRef.update({["timeRecords." + input.field]: val, "date": dateStr})
      .catch(() => todayRef.set({timeRecords: {[input.field]: input.value === "null" ? null : input.value}, date: dateStr}, {merge: true}));

    return "✏️ " + input.field + " → " + displayVal + " (today doc 반영)";
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

// ═══════════════════════════════════════════════════════════
//  📊 매일 아침 센서 로그 분석 → 텔레그램 보고
//  KST 08:00 실행 (어젯밤 ~ 오늘 새벽 분석)
// ═══════════════════════════════════════════════════════════

// ★ dailySensorReport 비활성화 (사용자 요청 2026-04-05)
exports.dailySensorReport = functions.pubsub
  .schedule("0 23 * * *")
  .timeZone("Asia/Seoul")
  .onRun(async () => { return null; });

// ═══════════════════════════════════════════════════════════
//  🌤️ 매일 아침 7시 날씨 예보 → 텔레그램
// ═══════════════════════════════════════════════════════════

exports.dailyWeatherForecast = functions.pubsub
  .schedule("3 7 * * *")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    try {
      const OWM_KEY = "0aa8ab8d78e7f3b2ff5dd159446d0a13";
      const lat = 37.3137, lon = 126.926; // 군포 금강4단지
      const url = `https://api.openweathermap.org/data/2.5/forecast?lat=${lat}&lon=${lon}&appid=${OWM_KEY}&units=metric&lang=kr`;
      const r = await axios.get(url, {timeout: 10000});
      const list = r.data.list || [];

      const lines = ["🌤️ 오늘 날씨 예보 (군포)"];
      let hasRain = false;

      for (const item of list.slice(0, 8)) {
        const dt = item.dt_txt.slice(11, 16);
        const temp = Math.round(item.main.temp);
        const desc = item.weather[0].description;
        const pop = Math.round((item.pop || 0) * 100);
        const rain = (item.rain && item.rain["3h"]) || 0;
        if (pop >= 30 || rain > 0) hasRain = true;
        lines.push(`${dt} ${temp}° ${desc} 💧${pop}%${rain > 0 ? ` ${rain}mm` : ""}`);
      }

      if (hasRain) {
        lines.push("");
        lines.push("☂️ 비 예보 있음 — 우산 챙겨!");
      }

      const msg = lines.join("\n");
      await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
        {chat_id: MY_CHAT_ID, text: msg}).catch(() => {});
      console.log("Daily weather forecast sent");
    } catch (err) {
      console.error("dailyWeatherForecast error:", err.message);
    }
    return null;
  });

// ═══════════════════════════════════════════════════════════
//  🔋 (DEPRECATED 2026-04-15) batteryWatchdog 제거
//  배경: battery_manager 전면 폐기 + Lenovo Vantage 관리 이관.
//  heartbeat 공급원이 없으므로 watchdog은 오탐만 발생 → 삭제.
// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
//  🔄 일일 롤오버 — 매일 04:10 KST
//  today doc 아카이빙 → history/{month}.days.{dd}
//  today doc 리셋 (orderData 보존)
//  iot doc 리셋 (movement, activity)
//  멱등: 여러 번 실행해도 안전 (date 비교 + _rolloverInProgress 가드)
// ═══════════════════════════════════════════════════════════

async function dailyRolloverLogic() {
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const todayKey = kstStudyDate(kstNow);
  const log = [];
  log.push("Rollover check at KST " +
    String(kstNow.getUTCHours()).padStart(2, "0") + ":" +
    String(kstNow.getUTCMinutes()).padStart(2, "0") +
    " todayKey=" + todayKey);

  // 1. Read today doc
  const todayRef = db.doc("users/" + UID + "/data/today");
  const todaySnap = await todayRef.get();
  if (!todaySnap.exists) {
    log.push("today doc does not exist — skip");
    return {rolled: false, log};
  }
  const todayData = todaySnap.data();
  const savedDate = todayData.date;

  // Already current date — no rollover needed
  if (!savedDate || savedDate === todayKey) {
    log.push("date=" + (savedDate || "null") + " == todayKey — no rollover");
    // Still reset iot even if today doc is current (idempotent daily iot reset)
    await resetIotDoc(todayKey, log);
    return {rolled: false, log};
  }

  // Guard: _rolloverInProgress (stuck flag from app crash)
  if (todayData._rolloverInProgress) {
    log.push("_rolloverInProgress stuck flag found — clearing");
    await todayRef.update({
      _rolloverInProgress: admin.firestore.FieldValue.delete(),
    });
  }

  log.push("Rolling " + savedDate + " → " + todayKey);

  // 2. Mark rollover in progress (date NOT changed yet — Phase D safety)
  await todayRef.update({
    _rolloverInProgress: true,
  });

  try {
    // 3. Archive today data to history/{month}.days.{dd}
    const month = savedDate.substring(0, 7); // "yyyy-MM"
    const day = savedDate.substring(8, 10);   // "dd"

    // Clone todayData for archive (exclude internal fields)
    const archiveData = {...todayData};
    delete archiveData._rolloverInProgress;

    const historyRef = db.doc("users/" + UID + "/history/" + month);
    await historyRef.set({
      month: month,
      days: {[day]: archiveData},
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    log.push("Archived to history/" + month + ".days." + day);

    // Phase D: verify archive before resetting today doc
    const verifySnap = await historyRef.get();
    const verifyData = verifySnap.exists ? verifySnap.data() : {};
    const verifyDay = (verifyData.days || {})[day];
    if (!verifyDay) {
      log.push("ABORT: archive verification failed — history/" + month + ".days." + day + " is null");
      return {rolled: false, error: "archive_verification_failed", log};
    }
    log.push("Archive verified OK");

    // 4. Reset today doc — preserve orderData, reset everything else
    const newToday = {
      date: todayKey,
      timeRecords: {},
      studyTime: {total: 0, subjects: {}},
      todos: [],
      orderData: todayData.orderData || {},
      lastModified: Date.now(),
      lastDevice: "cf_rollover",
    };
    await todayRef.set(newToday);
    log.push("Today doc reset for " + todayKey);

    // 5. Reset iot doc (movement + activity)
    await resetIotDoc(todayKey, log);

    // 6. Recalculate month summary (fire-and-forget)
    recalculateMonthSummary(month).catch((e) =>
      console.error("Rollover summary error:", e.message));

    // 7. Telegram notification
    const msg = "🔄 CF 롤오버 완료\n" + savedDate + " → " + todayKey;
    await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
      {chat_id: MY_CHAT_ID, text: msg}).catch(() => {});

    log.push("Rollover complete");
    return {rolled: true, from: savedDate, to: todayKey, log};
  } finally {
    // Always clear rollover flag
    try {
      await todayRef.update({
        _rolloverInProgress: admin.firestore.FieldValue.delete(),
      });
    } catch (_) {}
  }
}

// iot doc daily reset — movement + activity
async function resetIotDoc(todayKey, log) {
  const iotRef = db.doc("users/" + UID + "/data/iot");
  const iotSnap = await iotRef.get();
  if (!iotSnap.exists) {
    log.push("iot doc does not exist — skip iot reset");
    return;
  }
  const iotData = iotSnap.data();

  const iotUpdate = {};
  let changed = false;

  // Reset movement (stale outing from yesterday OR stale date)
  const movement = iotData.movement || {};
  const movementDate = movement.date || "";
  const isStaleDate = movementDate !== todayKey;
  if (movement.type !== "home" || movement.pending || isStaleDate) {
    iotUpdate.movement = {
      type: "home",
      pending: false,
      date: todayKey,
      resetBy: "cf_rollover",
      resetAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    changed = true;
    log.push("iot.movement reset to home (staleDate=" + isStaleDate + " prevDate=" + movementDate + ")");
  }

  // Reset activity transitions for new day
  const activity = iotData.activity || {};
  if (activity.date !== todayKey) {
    iotUpdate.activity = {
      date: todayKey,
      current: activity.current || "still",
      transitions: [],
    };
    changed = true;
    log.push("iot.activity reset for " + todayKey);
  }

  if (changed) {
    // update() atomically replaces the nested `movement`/`activity` maps entirely,
    // whereas set({merge:true}) merges nested maps field-by-field and would leave
    // stale subfields (studyingSince, leftAtLocal, returnedAtLocal, ...) alive.
    await iotRef.update(iotUpdate);
    log.push("iot movement/activity atomically replaced");
  } else {
    log.push("iot doc already current — no reset needed");
  }
}

// Month summary recalculation (mirrors Flutter _calculateMonthlySummary)
async function recalculateMonthSummary(month) {
  const historyRef = db.doc("users/" + UID + "/history/" + month);
  const snap = await historyRef.get();
  if (!snap.exists) return;
  const data = snap.data();
  const days = data.days || {};

  let totalMinutes = 0;
  const subjectTotals = {};
  let todosCompleted = 0;
  let todosTotal = 0;
  let daysWithStudy = 0;

  for (const [, dayData] of Object.entries(days)) {
    const st = dayData.studyTime || {};
    const dayMin = st.total || 0;
    if (dayMin > 0) {
      totalMinutes += dayMin;
      daysWithStudy++;
    }
    const subs = st.subjects || {};
    for (const [subj, min] of Object.entries(subs)) {
      subjectTotals[subj] = (subjectTotals[subj] || 0) + (min || 0);
    }
    const todos = dayData.todos || [];
    if (Array.isArray(todos)) {
      todosTotal += todos.length;
      todosCompleted += todos.filter((t) => t.completed).length;
    }
  }

  await historyRef.update({
    summary: {
      totalMinutes,
      subjectTotals,
      todosCompleted,
      todosTotal,
      daysWithStudy,
      daysCount: Object.keys(days).length,
    },
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// Scheduled: 04:10 KST daily
exports.dailyRollover = functions.pubsub
  .schedule("10 4 * * *")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    try {
      const result = await dailyRolloverLogic();
      console.log("DailyRollover:", JSON.stringify(result));
    } catch (err) {
      console.error("DailyRollover error:", err.message);
      await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
        {chat_id: MY_CHAT_ID, text: "⚠️ 롤오버 실패\n" + err.message}).catch(() => {});
    }
    return null;
  });

// Manual rollover test endpoint
exports.rolloverManual = functions.https.onRequest(async (req, res) => {
  try {
    const result = await dailyRolloverLogic();
    res.status(200).json(result);
  } catch (err) {
    res.status(500).json({success: false, error: err.message});
  }
});

// ═══ 부곡도서관 좌석 프록시 ═══
exports.librarySeats = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const url = "http://210.90.190.249:8081/RoomStatus.aspx";
  try {
    const r1 = await axios.get(url, {timeout: 5000, responseType: "arraybuffer"});
    const body1 = Buffer.from(r1.data).toString("utf-8");
    const vs = (body1.match(/id="__VIEWSTATE"\s+value="([^"]*)"/)||[])[1]||"";
    const vg = (body1.match(/id="__VIEWSTATEGENERATOR"\s+value="([^"]*)"/)||[])[1]||"";
    const ev = (body1.match(/id="__EVENTVALIDATION"\s+value="([^"]*)"/)||[])[1]||"";

    const params = new URLSearchParams();
    params.append("__VIEWSTATE", vs);
    params.append("__VIEWSTATEGENERATOR", vg);
    params.append("__VIEWSTATEENCRYPTED", "");
    params.append("__EVENTVALIDATION", ev);
    params.append("Roon_no", "2");
    const r2 = await axios.post(url, params.toString(), {
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      timeout: 5000, responseType: "arraybuffer",
    });
    const body2 = Buffer.from(r2.data).toString("utf-8");

    const trM = body2.match(/data-room_no=["']2["'][^>]*>(.*?)<\/tr>/s);
    let summary = {name:"일반열람실",total:0,used:0,available:0,rate:"0%",waiting:0};
    if (trM) {
      const tds = [...trM[1].matchAll(/<td[^>]*>(.*?)<\/td>/gs)].map(m=>m[1].replace(/<[^>]*>/g,"").replace(/&nbsp;/g," ").trim());
      if (tds.length >= 6) {
        summary = {name:tds[0]||"일반열람실",total:+tds[1]||0,used:+tds[2]||0,available:+tds[3]||0,rate:tds[4],waiting:+tds[5]||0};
      }
    }

    const seats = {};
    const ri = body2.indexOf("room_content");
    const sh = ri>=0?body2.substring(ri):body2;
    const sr = /class='Style(\d+)\s+normal_seat'[^>]*>\s*(\d+)/gs;
    let m;
    while((m=sr.exec(sh))!==null){
      seats[m[2]] = +m[1];
    }

    res.json({ok:true, summary, seats, fetchedAt: new Date().toISOString()});
  } catch(e) {
    res.status(500).json({ok:false, error: e.message});
  }
});

// ═══════════════════════════════════════════════════════════
//  고시공고 파싱 — gongmuwon.gosi.kr 시험 공고 목록
//  ?q=fetch → 사이트 파싱 → Firestore 저장 → 새 공고 텔레그램 알림
//  ?q=list → Firestore에서 저장된 공고 목록 반환
// ═══════════════════════════════════════════════════════════
exports.gosiNotice = functions.https.onRequest(async (req, res) => {
  try {
    const q = req.query.q || "fetch";

    if (q === "list") {
      // Firestore에서 저장된 공고 반환
      const doc = await db.doc("users/" + UID + "/data/study").get();
      const data = doc.exists ? doc.data() : {};
      const notices = data.gosiNotices || [];
      res.json({ok: true, notices, count: notices.length});
      return;
    }

    // q === "fetch" → 사이트에서 파싱
    const GOSI_URL = "https://gongmuwon.gosi.kr/oprut/RpaRpTestPbancLst.do";
    const cheerio = require("cheerio");

    const {data: html} = await axios.get(GOSI_URL, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "ko-KR,ko;q=0.9",
      },
      timeout: 10000,
    });

    const $ = cheerio.load(html);
    const notices = [];

    // 파싱 — gongmuwon.gosi.kr ul.tbody 구조
    $("ul.tbody").each((_, ul) => {
      const $ul = $(ul);
      const hiddenLis = $ul.find('li[style*="display"]');
      const noticeId = hiddenLis.eq(0).text().trim();
      const no = $ul.find("li.num").text().trim();
      const category = $ul.find('li[data-title="시험종류"]').text().trim();
      const title = $ul.find("li.subj a").first().text().trim();
      const date = $ul.find("li.datetime").text().trim();
      if (noticeId && title) {
        notices.push({id: noticeId, no: +no || 0, category, title, date, url: GOSI_URL});
      }
    });

    if (notices.length === 0) {
      res.json({ok: true, notices: [], message: "파싱 결과 없음 — 사이트 구조 변경 가능", htmlLength: html.length});
      return;
    }

    // Firestore에서 기존 공고 읽기
    const studyRef = db.doc("users/" + UID + "/data/study");
    const studySnap = await studyRef.get();
    const existingData = studySnap.exists ? studySnap.data() : {};
    const existingNotices = existingData.gosiNotices || [];
    const existingIds = new Set(existingNotices.map(n => n.id));

    // 새 공고 필터링
    const newNotices = notices.filter(n => !existingIds.has(n.id));

    // 최신 20개만 저장
    const merged = [...newNotices, ...existingNotices].slice(0, 20);
    await studyRef.set({gosiNotices: merged, gosiLastFetched: new Date().toISOString()}, {merge: true});

    // 새 공고가 있으면 텔레그램 알림
    if (newNotices.length > 0) {
      const lines = newNotices.slice(0, 5).map(n =>
        "📋 " + n.title + "\n   " + n.category + " | " + n.date
      );
      const msg = "🔔 새 고시 공고 " + newNotices.length + "건\n\n" + lines.join("\n\n");
      await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
        {chat_id: MY_CHAT_ID, text: msg, disable_web_page_preview: true}).catch(() => {});
    }

    res.json({ok: true, total: notices.length, new: newNotices.length, notices: notices.slice(0, 10)});
  } catch(e) {
    console.error("gosiNotice error:", e.message);
    res.status(500).json({ok: false, error: e.message});
  }
});
