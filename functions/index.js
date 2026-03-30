const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();

const UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2";
const TUYA_BASE = "https://openapi.tuyaus.com";
const MY_BOT_TOKEN = "8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50";
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

// ═══ 거리 중앙값 필터 (노이즈 제거) ═══
function medianOf(arr) {
  if (!arr || arr.length === 0) return null;
  const sorted = [...arr].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

// ═══ 침대/책상 임계값 (Firestore iot.config.bedThresholdCm 오버라이드 가능) ═══
const DEFAULT_BED_THRESHOLD = 220; // cm (침대 ~150, 책상 300+)

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
  const bedThreshold = iotConfig.bedThresholdCm || DEFAULT_BED_THRESHOLD;

  // ═══ Tuya API 실패 시 → Firestore fallback (battery_manager가 쓴 데이터) ═══
  const isOpen = doorContactState; // null이면 도어센서 못 읽은 것
  const mmPresence = iotConfig.mmwave_presence || null; // battery_manager가 로컬 폴링→Firestore
  const mmDistance = Number(iotConfig.mmwave_distance) || 0;

  // 도어센서 못 읽었으면 도어 업데이트 스킵
  if (isOpen === null && !tuyaApiOk) {
    console.log("Door sensor unavailable, mmWave-only mode. presence=" + mmPresence);
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
    // 도어센서 기반 기상
    wakeTime = await checkWakeAndNotify(doc, doorMerged.firstOpenTime);
  }
  // ★ mmWave fallback 기상: 도어센서 못 읽고, mmWave가 재실 감지하면 기상 시도
  if (!wakeTime && isOpen === null && mmPresence && mmPresence !== "none") {
    console.log("mmWave wake fallback — presence=" + mmPresence);
    wakeTime = await checkWakeAndNotify(doc, null);
  }

  // ═══ 외출 20분 확정 체크 ═══
  let outingTime = null;
  outingTime = await checkMovementPending(doc);

  // ═══ mmWave presence 폴링 (Tuya API 또는 Firestore fallback) ═══
  let sleepTime = null;
  const {mmwaveId} = getConfig();
  if (mmwaveId) {
    let presenceState = null;
    let targetDist = null;

    if (tuyaApiOk && token) {
      try {
        const mmStatus = await getDeviceStatus(accessId, accessSecret, token, mmwaveId);
        for (const s of mmStatus) {
          if (s.code === "presence_state") presenceState = s.value;
          if (s.code === "target_dis_closest") targetDist = s.value;
        }
      } catch (e) {
        console.warn("mmWave Tuya API failed:", e.message);
      }
    }

    // ★ Firestore fallback: battery_manager.py가 로컬 폴링한 데이터
    if (!presenceState && mmPresence) {
      presenceState = mmPresence;
      targetDist = mmDistance;
      console.log("mmWave using Firestore fallback: " + presenceState + " " + targetDist + "cm");
    }

    if (presenceState) {

      const prevPresence = iotData.presence || {};
      const presenceUpdate = {
        state: presenceState,
        distance: targetDist,
        lastPolled: admin.firestore.FieldValue.serverTimestamp(),
        sensorId: "mmwave_room",
      };

      // ═══ 거리 중앙값 필터 (5개 롤링 윈도우) ═══
      const prevHistory = prevPresence.distHistory || [];
      const newHistory = targetDist !== null
        ? [...prevHistory, targetDist].slice(-5) : prevHistory;
      presenceUpdate.distHistory = newHistory;
      const filteredDist = medianOf(newHistory);
      presenceUpdate.filteredDistance = filteredDist;

      // ═══ zone 판별: 필터된 거리 + configurable 임계값 ═══
      const zoneDist = filteredDist !== null ? filteredDist : targetDist;
      const inBed = presenceState === "peaceful" && zoneDist !== null && zoneDist >= bedThreshold;

      // stationarySince 추적 — peaceful + 침대 zone (220cm+)
      if (inBed) {
        const prevInBed = prevPresence.state === "peaceful"
          && (prevPresence.filteredDistance || prevPresence.distance) !== undefined
          && (prevPresence.filteredDistance || prevPresence.distance) >= bedThreshold;
        if (!prevPresence.stationarySince || !prevInBed) {
          presenceUpdate.stationarySince = admin.firestore.FieldValue.serverTimestamp();
        }
      } else {
        presenceUpdate.stationarySince = null;
      }

      // noneSince 추적
      if (presenceState === "none") {
        if (!prevPresence.noneSince || prevPresence.state !== "none") {
          presenceUpdate.noneSince = admin.firestore.FieldValue.serverTimestamp();
        }
      } else {
        presenceUpdate.noneSince = null;
      }

      await todayRef.set({presence: presenceUpdate}, {merge: true});

      // ═══ bedTime 가드 + 수면 zone 가드 읽기 ═══
      const todayDoc2 = await db.doc("users/" + UID + "/data/today").get();
      const todayTr2 = (todayDoc2.exists ? todayDoc2.data() : {}).timeRecords || {};
      const hasBedTime = !!(todayTr2.bedTime || todayTr2[kstStudyDate()]?.bedTime);
      const kstH = new Date(Date.now() + 9 * 60 * 60 * 1000).getUTCHours();
      const isNightTime = kstH >= 23 || kstH < 7;

      // ★ 수면 보호: bedTime 기록됨 OR (야간 + 침대 zone) → 전등 자동화 억제
      const sleepGuard = hasBedTime || (isNightTime && inBed);

      // ═══ 방 비움 5분 → 전등 OFF ═══
      if (presenceState === "none" && !hasBedTime) {
        const ns = prevPresence.noneSince;
        if (ns && ns.toDate) {
          const noneMin = (Date.now() - ns.toDate().getTime()) / (1000 * 60);
          if (noneMin >= 5) {
            setLight(false);
            console.log("Room empty 5min → light OFF");
          }
        }
      }

      // ═══ 방 복귀 → 전등 ON (수면 보호 적용) ═══
      if (prevPresence.state === "none" && presenceState !== "none" && !sleepGuard) {
        if (kstH >= 18 || kstH < 7) {
          setLight(true);
          console.log("Room entry → light ON");
        }
      }

      // ═══ 취침 자동 감지 (필터된 거리 사용) ═══
      sleepTime = await checkSleepByPresence(doc, presenceState, prevPresence, zoneDist, bedThreshold);
    } // end if (presenceState)
  } // end if (mmwaveId)

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

  // ★ bedTime 기록 있으면 → 아직 안 일어난 것 (문 열림은 화장실 등)
  // wake 기반: 가장 최근 bedTime이 있는 날 이후에 문이 열려야 진짜 기상
  const studyDoc2 = await db.doc("users/" + UID + "/data/study").get();
  const allTr2 = (studyDoc2.exists ? studyDoc2.data() : {}).timeRecords || {};
  // ★ wake 기반: 가장 최근 bedTime 찾고, 그 이후에 wake가 없어야 진짜 기상
  let lastBedDate = null;
  for (let i = 0; i < 4; i++) {
    const d = kstStudyDate(new Date(kstNow.getTime() - i * 24 * 60 * 60 * 1000));
    if (allTr2[d]?.bedTime) { lastBedDate = d; break; }
  }
  if (!lastBedDate) {
    // fallback: bedTime 없어도 오늘 wake 없고 문 열렸으면 기상 허용
    // (bedTime 연속 실패 시 wake까지 죽는 cascade 방지)
    if (allTr2[dateStr]?.wake) {
      return null; // 이미 오늘 wake 있음
    }
    console.log("Wake fallback — no bedTime but allowing wake for " + dateStr);
  } else {
    // bedTime 이후에 이미 wake가 있는 날짜가 있으면 → 이미 일어남
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

async function checkSleepByPresence(iotDoc, presenceState, prevPresence, zoneDist, bedThreshold) {
  const thresh = bedThreshold || DEFAULT_BED_THRESHOLD;
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const kstHour = kstNow.getUTCHours();
  const kstMin = kstNow.getUTCMinutes();

  // 시간 조건: 23~07시
  if (kstHour >= 7 && kstHour < 23) return null;

  // presence 조건: thresh(220cm) 이상 = 침대, 미만 = 책상
  // softMargin(80%): 176cm~220cm = soft zone (45분), 220cm+ = 침대 (30분), 176cm 미만 = 차단
  const softMargin = Math.round(thresh * 0.8);
  if (presenceState !== "peaceful" || zoneDist === null || zoneDist < softMargin) {
    if (kstMin % 10 === 0) {
      console.log("Sleep gate2: state=" + presenceState + " dist=" + zoneDist + " thresh=" + thresh + " softMargin=" + softMargin);
    }
    return null;
  }
  const requiredMin = zoneDist >= thresh ? 30 : 45; // 침대=30분, soft zone=45분

  // ★ wake 기반 날짜 귀속: study doc (nested) → today doc (flat) fallback → 직전 날짜
  const studyDoc = await db.doc("users/" + UID + "/data/study").get();
  const studyData = studyDoc.exists ? studyDoc.data() : {};
  const allTr = studyData.timeRecords || {};

  // today doc fallback (flat 구조)
  const todayDoc2 = await db.doc("users/" + UID + "/data/today").get();
  const todayData2 = todayDoc2.exists ? todayDoc2.data() : {};
  const todayTr2 = todayData2.timeRecords || {};

  const sleepDateStr = kstStudyDate(kstNow);
  let targetDate = null;

  // 1) study doc 날짜별 구조
  const rec = allTr[sleepDateStr];
  if (rec && rec.wake && !rec.bedTime) {
    targetDate = sleepDateStr;
  }

  // 2) study doc flat 구조 fallback (레거시 호환)
  if (!targetDate && allTr.wake && !allTr.bedTime && todayData2.date === sleepDateStr) {
    targetDate = sleepDateStr;
  }

  // 3) today doc flat 구조 fallback
  if (!targetDate && todayTr2.wake && !todayTr2.bedTime && todayData2.date === sleepDateStr) {
    targetDate = sleepDateStr;
  }

  // 4) 4AM 경계 넘긴 경우: 직전 study date 1개만 확인 (cascade 방지)
  if (!targetDate) {
    const parts = sleepDateStr.split("-");
    const prevDate = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    prevDate.setDate(prevDate.getDate() - 1);
    const prevStr = prevDate.getFullYear() + "-" +
      String(prevDate.getMonth() + 1).padStart(2, "0") + "-" +
      String(prevDate.getDate()).padStart(2, "0");
    const prevRec = allTr[prevStr];
    if (prevRec && prevRec.wake && !prevRec.bedTime) {
      targetDate = prevStr;
    }
    // prev도 flat fallback
    if (!targetDate && allTr.wake && !allTr.bedTime && todayData2.date === prevStr) {
      targetDate = prevStr;
    }
  }

  if (!targetDate) {
    if (kstMin % 10 === 0) {
      console.log("Sleep gate3: " + sleepDateStr + " wake=" + (rec?.wake || allTr.wake || "none") + " bed=" + (rec?.bedTime || allTr.bedTime || "none"));
    }
    return null;
  }

  // ★ 화면 상태 체크: lastScreenOn이 30분 이내면 스킵 (폰 사용 중)
  const iotSnap = iotDoc.exists ? iotDoc.data() : {};
  const phone = iotSnap.phone || {};
  if (phone.lastScreenOn && phone.lastScreenOn.toDate) {
    const screenMin = (Date.now() - phone.lastScreenOn.toDate().getTime()) / (1000 * 60);
    if (screenMin < 30) {
      console.log("Sleep gate4: screen active " + Math.round(screenMin) + "min ago");
      return null;
    }
  }

  // stationarySince 30분 경과 확인
  const since = prevPresence.stationarySince;
  if (!since || !since.toDate) {
    console.log("Sleep gate5: no stationarySince");
    return null;
  }
  const sinceTime = since.toDate();
  const elapsedMin = (Date.now() - sinceTime.getTime()) / (1000 * 60);
  if (elapsedMin < requiredMin) {
    if (kstMin % 10 === 0) {
      console.log("Sleep gate5: stationary " + Math.round(elapsedMin) + "min (need " + requiredMin + ")");
    }
    return null;
  }

  // ═══ 취침 확정 ═══
  const dateStr = targetDate;
  const timeStr = String(kstHour).padStart(2, "0") + ":" + String(kstMin).padStart(2, "0");

  // 1. 전등 OFF
  setLight(false);

  // 2. bedTime 듀얼라이트 — targetDate에 기록
  const studySleepUpdate = {timeRecords: {}};
  studySleepUpdate.timeRecords[dateStr] = {bedTime: timeStr};
  const studyRef = db.doc("users/" + UID + "/data/study");
  const todayRef = db.doc("users/" + UID + "/data/today");
  // ★ study doc flat 키 정리 (레거시 호환)
  const flatCleanup = {};
  for (const k of ["wake", "outing", "returnHome", "bedTime", "study", "studyEnd", "meal"]) {
    flatCleanup["timeRecords." + k] = admin.firestore.FieldValue.delete();
  }
  await Promise.all([
    todayRef.update({"timeRecords.bedTime": timeStr, "date": dateStr})
      .catch(() => todayRef.set({timeRecords: {bedTime: timeStr}, date: dateStr}, {merge: true})),
    studyRef.set(studySleepUpdate, {merge: true}),
    studyRef.update(flatCleanup).catch(() => {}),
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
      if (req.query.doc === "iot") {
        const iotDoc = await db.doc("users/" + UID + "/data/iot").get();
        const d = iotDoc.exists ? iotDoc.data() : {};
        res.status(200).json({presence: d.presence, door: d.door, phone: d.phone, movement: d.movement, config: d.config});
        return;
      }
      const qDate = req.query.date || kstStudyDate();
      const studyDoc = await db.doc("users/" + UID + "/data/study").get();
      const studyData = studyDoc.exists ? studyDoc.data() : {};
      const tr = (studyData.timeRecords || {})[qDate];
      res.status(200).json({date: qDate, timeRecords: tr || null});
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
      await Promise.all([
        db.doc("users/" + UID + "/data/study").update({["timeRecords." + qDate + "." + field]: fv}),
        db.doc("users/" + UID + "/data/today").update({["timeRecords." + field]: isDel ? admin.firestore.FieldValue.delete() : fv}).catch(() => {}),
      ]);
      res.status(200).json({ok: true, date: qDate, field, value: isDel ? "DELETED" : value});
      return;
    }

    // ═══ 범용 Firestore 읽기 ═══
    // ?q=read&doc=today|study|iot&field=studyTime.total
    if (req.query.q === "read") {
      const docName = req.query.doc || "today";
      const field = req.query.field;
      const allowed = {today: "data/today", study: "data/study", iot: "data/iot"};
      if (!allowed[docName]) { res.status(400).json({error: "doc must be today|study|iot"}); return; }
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
      if (!allowed[docName]) { res.status(400).json({error: "doc must be today|study|iot"}); return; }

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
      // dot-notation → Firestore update (중첩 필드 지원)
      await docRef.update({[field]: parsed});

      // ★ dual-write: today↔study 자동 동기화
      // __DELETE__는 미러링 건너뜀 — today/study 문서 구조가 다르므로
      // 삭제는 각 문서에 명시적으로 보내야 한다 (?q=delete 또는 doc별 개별 write)
      if (rawValue !== "__DELETE__" && (docName === "today" || docName === "study")) {
        const mirrorName = docName === "today" ? "study" : "today";
        const mirrorRef = db.doc("users/" + UID + "/" + allowed[mirrorName]);
        try { await mirrorRef.update({[field]: parsed}); } catch (_) { /* mirror doc 없으면 무시 */ }
      }

      res.status(200).json({ok: true, doc: docName, field, value: rawValue === "__DELETE__" ? "__DELETED__" : parsed});
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

      // study doc: studyTimeRecords.{date} 배열에 추가
      const studyRef = db.doc("users/" + UID + "/data/study");
      const studySnap = await studyRef.get();
      const studyData = studySnap.exists ? studySnap.data() : {};
      const str = studyData.studyTimeRecords || {};
      const raw = str[date];
      const dayRecords = Array.isArray(raw) ? [...raw] : [];
      dayRecords.push(session);

      // studyTime 총합 계산
      const st = studyData.studyTime || {};
      const subjects = st.subjects || {};
      const newTotal = (st.total || 0) + studyMin;
      const newSubject = (subjects[subject] || 0) + studyMin;

      // pendingSessions에 세션 추가 (앱이 Hive로 머지할 수 있도록)
      const pending = studyData.pendingSessions || {};
      const pendingDay = Array.isArray(pending[date]) ? [...pending[date]] : [];
      pendingDay.push(session);

      await studyRef.set({
        ["pendingSessions." + date]: pendingDay,
        "studyTime.total": newTotal,
        ["studyTime.subjects." + subject]: newSubject,
      }, {merge: true});

      // today doc 동기화
      const todayRef = db.doc("users/" + UID + "/data/today");
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

      // study doc: todos.{date} 배열에 추가
      const studyRef = db.doc("users/" + UID + "/data/study");
      const studySnap = await studyRef.get();
      const studyData = studySnap.exists ? studySnap.data() : {};
      const todos = (studyData.todos || {})[date] || [];
      todos.push(todo);

      await studyRef.set({["todos." + date]: todos}, {merge: true});

      // today doc 동기화
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
      await Promise.all([
        db.doc("users/" + UID + "/data/study").update({["timeRecords." + date + "." + field]: fv}),
        db.doc("users/" + UID + "/data/today").update({["timeRecords." + field]: isDel ? admin.firestore.FieldValue.delete() : fv}).catch(() => {}),
      ]);
      res.status(200).json({ok: true, date, field, value: isDel ? "DELETED" : value});
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
- mmWave(mmwave): 존재감지 (none=비어있음, presence=움직임, peaceful=정지), distance=거리cm
- 16A 소켓(plug_16a): 방 전등(천장) ON/OFF
- 20A 소켓(plug_20a): 책상 스탠드 ON/OFF

"센서 상태" → iot_status, "전등 상태" → query_sensor(plug_16a)
"기록 확인" / "감사" → audit_today로 이상 데이터 감지 후 사용자에게 보고.
시간 수정 요청 시 반드시 사용자 확인 후 fix_timerecord 실행. 절대 자동 수정 금지.`;

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

  if (name === "audit_today") {
    const [todayDoc, iotDoc] = await Promise.all([
      db.doc("users/" + UID + "/data/today").get(),
      db.doc("users/" + UID + "/data/iot").get(),
    ]);
    const today = todayDoc.exists ? todayDoc.data() : {};
    const tr = today.timeRecords || {};
    const iot = iotDoc.exists ? iotDoc.data() : {};
    const door = iot.door || {};
    const presence = iot.presence || {};

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
    report += "  📡 mmWave: " + (presence.state || "?") + " " + (presence.filteredDistance || presence.distance || "?") + "cm\n";

    if (issues.length > 0) {
      report += "\n⚠️ 이상 감지 " + issues.length + "건:\n" + issues.join("\n");
    } else {
      report += "\n✅ 이상 없음";
    }

    return report;
  }

  if (name === "query_date") {
    const qDate = input.date;
    // study doc에서 해당 날짜 timeRecords 조회
    const studyDoc = await db.doc("users/" + UID + "/data/study").get();
    const studyData = studyDoc.exists ? studyDoc.data() : {};
    const tr = (studyData.timeRecords || {})[qDate];
    if (!tr) {
      // history fallback
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
    let result = "📅 " + qDate + "\n";
    for (const [k, v] of Object.entries(tr)) {
      result += "  " + k + ": " + v + "\n";
    }
    return result;
  }

  if (name === "fix_timerecord") {
    const val = input.value === "null" ? admin.firestore.FieldValue.delete() : input.value;
    const displayVal = input.value === "null" ? "삭제" : input.value;

    // today doc (flat)
    const todayRef = db.doc("users/" + UID + "/data/today");
    await todayRef.update({["timeRecords." + input.field]: val, "date": dateStr})
      .catch(() => todayRef.set({timeRecords: {[input.field]: input.value === "null" ? null : input.value}, date: dateStr}, {merge: true}));

    // study doc (nested)
    const studyUpdate = {timeRecords: {}};
    studyUpdate.timeRecords[dateStr] = {[input.field]: input.value === "null" ? null : input.value};
    await db.doc("users/" + UID + "/data/study").set(studyUpdate, {merge: true});

    return "✏️ " + input.field + " → " + displayVal + " (today + study 반영)";
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

exports.dailySensorReport = functions.pubsub
  .schedule("0 23 * * *")  // UTC 23:00 = KST 08:00
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    try {
      const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
      const yesterday = kstStudyDate(new Date(kstNow.getTime() - 24 * 60 * 60 * 1000));
      const today = kstStudyDate(kstNow);

      // 데이터 수집
      const [studyDoc, iotDoc, todayDoc] = await Promise.all([
        db.doc("users/" + UID + "/data/study").get(),
        db.doc("users/" + UID + "/data/iot").get(),
        db.doc("users/" + UID + "/data/today").get(),
      ]);

      const studyData = studyDoc.exists ? studyDoc.data() : {};
      const iotData = iotDoc.exists ? iotDoc.data() : {};
      const todayData = todayDoc.exists ? todayDoc.data() : {};

      const yTr = (studyData.timeRecords || {})[yesterday] || {};
      const tTr = todayData.timeRecords || {};
      const presence = iotData.presence || {};
      const door = iotData.door || {};
      const phone = iotData.phone || {};
      const config = iotData.config || {};

      // ═══ 보고서 작성 ═══
      const lines = [];
      lines.push("📊 일일 센서 보고 (" + today + " 08:00)");
      lines.push("━━━━━━━━━━━━━━━━━━");

      // 1. 어제 타임라인
      lines.push("");
      lines.push("📅 어제 (" + yesterday + "):");
      lines.push("  기상: " + (yTr.wake || "❌ 미기록"));
      if (yTr.outing) lines.push("  외출: " + yTr.outing);
      if (yTr.returnHome) lines.push("  귀가: " + yTr.returnHome);
      if (yTr.noOuting) lines.push("  외출: 🏠 홈데이");
      lines.push("  취침: " + (yTr.bedTime || "❌ 미기록"));

      if (!yTr.bedTime) {
        lines.push("  ⚠️ 취침 자동감지 실패!");
      }

      // 2. 오늘 현재
      lines.push("");
      lines.push("📌 오늘 (" + today + "):");
      lines.push("  기상: " + (tTr.wake || "아직 미기록"));

      // 3. 센서 상태
      lines.push("");
      lines.push("🔧 센서 상태:");
      lines.push("  mmWave: " + (presence.state || "unknown"));
      lines.push("  거리: " + (presence.filteredDistance || presence.distance || 0) + "cm");
      lines.push("  문: " + (door.state || "unknown"));

      // 4. 설정값
      lines.push("");
      lines.push("⚙️ 설정:");
      lines.push("  bedThreshold: " + (config.bedThresholdCm || DEFAULT_BED_THRESHOLD) + "cm");

      // 5. 이상 감지
      const anomalies = [];
      if (!yTr.wake) anomalies.push("어제 기상 미기록");
      if (!yTr.bedTime) anomalies.push("어제 취침 미기록");
      if (presence.state === "none" && !door.isOpen) {
        if (presence.noneSince && presence.noneSince.toDate) {
          const noneHours = (Date.now() - presence.noneSince.toDate().getTime()) / 3600000;
          if (noneHours > 12) anomalies.push("mmWave none " + Math.round(noneHours) + "시간 (센서 점검)");
        }
      }
      if (phone.lastScreenOn && phone.lastScreenOn.toDate) {
        const screenHours = (Date.now() - phone.lastScreenOn.toDate().getTime()) / 3600000;
        if (screenHours > 24) anomalies.push("폰 화면 " + Math.round(screenHours) + "시간 전 (BixbyListener 점검)");
      }

      if (anomalies.length > 0) {
        lines.push("");
        lines.push("🚨 이상 감지:");
        for (const a of anomalies) lines.push("  • " + a);
      } else {
        lines.push("");
        lines.push("✅ 이상 없음");
      }

      const msg = lines.join("\n");
      await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
        {chat_id: MY_CHAT_ID, text: msg}).catch(() => {});

      console.log("Daily sensor report sent");
    } catch (err) {
      console.error("dailySensorReport error:", err.message);
      await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
        {chat_id: MY_CHAT_ID, text: "⚠️ 센서 보고 에러: " + err.message}).catch(() => {});
    }
    return null;
  });

// ═══════════════════════════════════════════════════════════
//  🔋 배터리 안전장치 — heartbeat 15분 끊기면 충전 ON
//  매 5분 실행, PC 크래시/셧다운 대비
// ═══════════════════════════════════════════════════════════

exports.batteryWatchdog = functions.pubsub
  .schedule("every 5 minutes")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    try {
      const doc = await db.doc("users/" + UID + "/data/iot").get();
      const config = (doc.exists ? doc.data() : {}).config || {};
      const lastBeat = Number(config.batteryHeartbeat || 0);
      const pct = Number(config.batteryPercent || 50);
      const plugOn = config.batteryPlugOn;

      if (!lastBeat) return null; // heartbeat 없으면 무시 (매니저 미실행)

      const elapsed = (Date.now() / 1000) - lastBeat;
      const deadMin = Math.round(elapsed / 60);

      // 15분 이상 heartbeat 없고, 플러그가 OFF 상태면 → 안전 충전 ON
      if (elapsed > 15 * 60 && plugOn === "false") {
        console.log("Battery watchdog: no heartbeat " + deadMin + "min, pct=" + pct + "% → forcing charge ON");

        // 20A 플러그 ON
        const {accessId, accessSecret} = getConfig();
        const deskPlugId = "ebeaff0f5a69754067yfdv";
        const token = await getTuyaToken(accessId, accessSecret);
        await sendTuyaCommand(accessId, accessSecret, token, deskPlugId,
          [{code: "switch_1", value: true}]);

        // 상태 기록
        await db.doc("users/" + UID + "/data/iot").set(
          {config: {batteryPlugOn: "true"}}, {merge: true});

        const msg = "🔋 안전장치 발동 — PC heartbeat " + deadMin + "분 끊김, 충전 강제 ON (" + pct + "%)";
        await axios.post("https://api.telegram.org/bot" + MY_BOT_TOKEN + "/sendMessage",
          {chat_id: MY_CHAT_ID, text: msg}).catch(() => {});

        console.log("Battery watchdog: charge forced ON");
      }
    } catch (err) {
      console.error("batteryWatchdog error:", err.message);
    }
    return null;
  });

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

  // 2. Mark rollover in progress (prevent concurrent runs)
  await todayRef.update({
    date: todayKey,
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

  // Reset movement (stale outing from yesterday)
  const movement = iotData.movement || {};
  if (movement.type !== "home" || movement.pending) {
    iotUpdate.movement = {
      type: "home",
      pending: false,
      resetBy: "cf_rollover",
      resetAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    changed = true;
    log.push("iot.movement reset to home");
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
    await iotRef.set(iotUpdate, {merge: true});
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
