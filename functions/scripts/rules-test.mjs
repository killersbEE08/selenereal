// Firestore security-rules checks against the local emulator (unsigned test tokens).
// Run: firebase emulators:exec --only firestore "node scripts/rules-test.mjs"
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
const PROJECT = "selene-ai-34251";
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const token = (uid, provider, verified, email) =>
  `${b64({ alg: "none", typ: "JWT" })}.${b64({
    sub: uid, user_id: uid, email, email_verified: verified, iat: 1, exp: 9999999999, aud: PROJECT,
    iss: `https://securetoken.google.com/${PROJECT}`, firebase: { sign_in_provider: provider },
  })}.`;

const toValue = (v) =>
  typeof v === "string" ? { stringValue: v } : typeof v === "boolean" ? { booleanValue: v } : typeof v === "number" ? { integerValue: String(v) }
  : Array.isArray(v) ? { arrayValue: { values: v.map(toValue) } } : v === null ? { nullValue: null }
  : { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toValue(x)])) } };

async function write(tok, path, data) {
  const url = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents/${path}`;
  const r = await fetch(url, { method: "PATCH", headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" }, body: JSON.stringify({ fields: toValue(data).mapValue.fields }) });
  return r.status === 200;
}
async function read(tok, path) {
  const r = await fetch(`http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents/${path}`, { headers: { Authorization: `Bearer ${tok}` } });
  return r.status !== 403;
}

const good = token("alice", "password", true, "alice@example.com");
const unverified = token("bob", "password", false, "bob@example.com");
const google = token("gina", "google.com", false, "gina@example.com");
const guest = token("gus", "anonymous", false, undefined);
const profile = { displayName: "Priya Sharma", language: "en", profileComplete: true, focusAreas: ["love"] };

const cases = [
  ["verified email user can write profile", await write(good, "users/alice", profile), true],
  ["unverified email user is blocked", await write(unverified, "users/bob", profile), false],
  ["unverified email user cannot read", await read(unverified, "users/bob"), false],
  ["google user allowed", await write(google, "users/gina", profile), true],
  ["guest allowed", await write(guest, "users/gus", profile), true],
  ["Hindi name allowed", await write(good, "users/alice", { ...profile, displayName: "प्रिया शर्मा" }), true],
  ["name with digits rejected", await write(good, "users/alice", { ...profile, displayName: "Priya123" }), false],
  ["name with symbols rejected", await write(good, "users/alice", { ...profile, displayName: "<script>" }), false],
  ["name with emoji rejected", await write(good, "users/alice", { ...profile, displayName: "Priya ✨" }), false],
  ["name with double space rejected", await write(good, "users/alice", { ...profile, displayName: "Priya  S" }), false],
  ["cannot grant self premium", await write(good, "users/alice", { ...profile, premium: { active: true } }), false],
  ["cannot store someone else's email", await write(good, "users/alice", { ...profile, email: "evil@x.com" }), false],
  ["own email ok", await write(good, "users/alice", { ...profile, email: "alice@example.com" }), true],
  ["bad focus area rejected", await write(good, "users/alice", { ...profile, focusAreas: ["hack"] }), false],
  ["cannot write other user's doc", await write(good, "users/gina", profile), false],
  ["valid collection card", await write(good, "users/alice/collection/major_19", {}), true],
  ["bad collection id rejected", await write(good, "users/alice/collection/..%2Fx", {}), false],
  ["valid custom spread", await write(good, "users/alice/customSpreads/s1", { name: "Mine", positions: [{ label: "A", meaning: "B" }] }), true],
  ["custom spread with junk position rejected", await write(good, "users/alice/customSpreads/s2", { name: "Mine", positions: [{ label: "A", meaning: "B", evil: "x" }] }), false],
  ["cannot write tarot reading", await write(good, "users/alice/tarotReadings/r1", { title: "fake" }), false],
  ["cannot write random collection", await write(good, "anything/x", { a: "b" }), false],
];
let failed = 0;
for (const [name, got, want] of cases) {
  const ok = got === want;
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}`);
}
console.log(failed ? `${failed} FAILED` : `all ${cases.length} rules checks passed`);
process.exit(failed ? 1 : 0);
