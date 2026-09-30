// Smoke test against the DEPLOYED backend (real Auth, App Check, Firestore, Storage, Functions, Gemini).
// Usage: APPCHECK_DEBUG_TOKEN=<registered debug token> node functions/scripts/prod-smoke.mjs
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const opts = readFileSync(resolve(root, "lib/firebase_options.dart"), "utf8");
const API_KEY = opts.match(/android = FirebaseOptions\([\s\S]*?apiKey: '([^']+)'/)[1];
const APP_ID = opts.match(/android = FirebaseOptions\([\s\S]*?appId: '([^']+)'/)[1];
const P = "selene-ai-34251", REGION = "asia-south1", BUCKET = `${P}.firebasestorage.app`;
const DEBUG = process.env.APPCHECK_DEBUG_TOKEN;
if (!DEBUG) throw new Error("Set APPCHECK_DEBUG_TOKEN");

const results = [];
const ok = (n, c, i = "") => { results.push(!!c); console.log(`${c ? "PASS" : "FAIL"}  ${n}${i ? "  — " + i : ""}`); };
const j = async (url, o = {}) => { const r = await fetch(url, o); const t = await r.text(); let b; try { b = JSON.parse(t); } catch { b = t; } return { status: r.status, body: b }; };

// App Check token from the registered debug token
const ac = await j(`https://firebaseappcheck.googleapis.com/v1/projects/${P}/apps/${APP_ID}:exchangeDebugToken?key=${API_KEY}`, {
  method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ debugToken: DEBUG }),
});
const AC = ac.body?.token;
ok("app check: debug token exchanged", !!AC, `status ${ac.status}`);

const su = await j(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Firebase-AppCheck": AC }, body: '{"returnSecureToken":true}' });
const uid = su.body.localId, token = su.body.idToken;
ok("auth: anonymous sign-in (production)", !!token);

const call = (fn, data, appCheck = AC) => j(`https://${REGION}-${P}.cloudfunctions.net/${fn}`, {
  method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, ...(appCheck ? { "X-Firebase-AppCheck": appCheck } : {}) },
  body: JSON.stringify({ data }),
});

let r = await call("getHoroscope", { sign: "libra", period: "daily" }, null);
ok("security: call WITHOUT App Check is rejected", r.status === 401 || r.body?.error?.status === "UNAUTHENTICATED", `status ${r.status}`);

const fsBody = (o) => JSON.stringify({ fields: Object.fromEntries(Object.entries(o).map(([k, v]) => [k, Array.isArray(v) ? { arrayValue: { values: v.map((s) => ({ stringValue: s })) } } : typeof v === "boolean" ? { booleanValue: v } : { stringValue: v }])) });
r = await j(`https://firestore.googleapis.com/v1/projects/${P}/databases/(default)/documents/users/${uid}`, {
  method: "PATCH", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, "X-Firebase-AppCheck": AC },
  body: fsBody({ displayName: "Smoke Test", zodiac: "libra", language: "en", focusAreas: ["love"], profileComplete: true }),
});
ok("firestore rules: user can create own profile", r.status === 200, `status ${r.status}`);
r = await j(`https://firestore.googleapis.com/v1/projects/${P}/databases/(default)/documents/users/${uid}`, { headers: { Authorization: `Bearer ${token}` } });
ok("security: Firestore read WITHOUT App Check is rejected", r.status === 401 || r.status === 403, `status ${r.status}`);

let t = Date.now();
r = await call("getHoroscope", { sign: "libra", period: "daily" });
ok("functions+gemini: daily horoscope", r.body?.result?.overview?.length > 40, `${Date.now() - t} ms ${r.status !== 200 ? JSON.stringify(r.body).slice(0, 200) : ""}`);
t = Date.now();
r = await call("startTarotReading", { question: "What should I focus on this month?", topic: "growth", spreadId: "three_card", aiEnabled: true });
ok("functions+gemini: three-card tarot", r.body?.result?.interpretation?.cards?.length === 3, `${Date.now() - t} ms ${r.status !== 200 ? JSON.stringify(r.body).slice(0, 200) : ""}`);
t = Date.now();
r = await call("sendChatMessage", { readerId: "selene", text: "Pull one card for me today" });
ok("functions+gemini: chat with card draw", r.body?.result?.reply?.length > 20 && r.body?.result?.cards?.length >= 1, `${Date.now() - t} ms`);

// Palm: upload to Storage then analyze
const jpg = resolve(root, "..", "tools", "smoke_palm.jpg");
execFileSync("python", ["-c", `from PIL import Image; im=Image.open(r"${resolve(root, "..", "Mystical Celestial Palmistry Hand.png")}").convert("RGB"); im.thumbnail((1600,1600)); im.save(r"${jpg}","JPEG",quality=85)`]);
r = await j(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?name=${encodeURIComponent(`palms/${uid}/smoke00001.jpg`)}`, {
  method: "POST", headers: { "Content-Type": "image/jpeg", Authorization: `Firebase ${token}`, "X-Firebase-AppCheck": AC }, body: readFileSync(jpg),
});
ok("storage: palm upload (own folder)", r.status === 200, `status ${r.status}`);
t = Date.now();
r = await call("analyzePalm", { readingId: "smoke00001", hand: "right" });
ok("functions+gemini: palm reading", r.body?.result?.status === "done" && r.body.result.result.lines.length === 4, `${Date.now() - t} ms ${r.status !== 200 ? JSON.stringify(r.body).slice(0, 200) : ""}`);

r = await call("devSetPremium", { active: true });
ok("security: dev premium grant disabled in production", r.body?.error?.status === "PERMISSION_DENIED");

r = await call("deleteMyData", { deleteAccount: true });
ok("cleanup: test account deleted", r.body?.result?.ok === true);

console.log(`\n${results.filter(Boolean).length}/${results.length} passed`);
process.exit(results.every(Boolean) ? 0 : 1);
