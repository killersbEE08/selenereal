import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { premiumFromDodo, uidFromMetadata, verifyDodoSignature } from "./dodo";

const secretBytes = Buffer.from("super-secret-signing-key-0123456789");
const secret = `whsec_${secretBytes.toString("base64")}`;
const sign = (id: string, ts: string, body: string) => createHmac("sha256", secretBytes).update(`${id}.${ts}.${body}`).digest("base64");

describe("dodo webhook signature", () => {
  const now = 1_790_000_000;
  const body = JSON.stringify({ type: "subscription.active", data: {} });
  const ts = String(now);
  const good = sign("msg_1", ts, body);

  it("accepts a valid v1 signature (with and without whsec_ prefix, multiple entries)", () => {
    expect(verifyDodoSignature(secret, { id: "msg_1", timestamp: ts, signature: `v1,${good}` }, body, now)).toBe(true);
    expect(verifyDodoSignature(secretBytes.toString("base64"), { id: "msg_1", timestamp: ts, signature: `v1,${good}` }, body, now)).toBe(true);
    expect(verifyDodoSignature(secret, { id: "msg_1", timestamp: ts, signature: `v1,AAAA v1,${good}` }, body, now)).toBe(true);
  });
  it("rejects tampered body, wrong id, wrong version, missing headers and stale timestamps", () => {
    expect(verifyDodoSignature(secret, { id: "msg_1", timestamp: ts, signature: `v1,${good}` }, body + " ", now)).toBe(false);
    expect(verifyDodoSignature(secret, { id: "msg_2", timestamp: ts, signature: `v1,${good}` }, body, now)).toBe(false);
    expect(verifyDodoSignature(secret, { id: "msg_1", timestamp: ts, signature: `v2,${good}` }, body, now)).toBe(false);
    expect(verifyDodoSignature(secret, { id: "msg_1", timestamp: ts }, body, now)).toBe(false);
    expect(verifyDodoSignature("", { id: "msg_1", timestamp: ts, signature: `v1,${good}` }, body, now)).toBe(false);
    expect(verifyDodoSignature(secret, { id: "msg_1", timestamp: ts, signature: `v1,${good}` }, body, now + 301)).toBe(false);
  });
});

describe("dodo premium decision", () => {
  const now = Date.parse("2026-10-01T00:00:00Z");
  const base = { subscription_id: "sub_1", product_id: "pdt_year", customer: { customer_id: "cus_1" } };

  it("active until next billing date plus grace", () => {
    const d = premiumFromDodo({ ...base, status: "active", next_billing_date: "2026-10-31T00:00:00Z" }, now);
    expect(d).toMatchObject({ active: true, plan: "pdt_year", customerId: "cus_1", subscriptionId: "sub_1" });
    expect(d.expiresAt).toBe(Date.parse("2026-10-31T00:00:00Z") + 2 * 86400000);
  });
  it("cancel-at-period-end keeps access while status is active", () => {
    expect(premiumFromDodo({ ...base, status: "active", cancel_at_next_billing_date: true, next_billing_date: "2026-10-15T00:00:00Z" }, now).active).toBe(true);
  });
  it("past_due keeps access only inside the retry window", () => {
    expect(premiumFromDodo({ ...base, status: "past_due", past_due_ends_at: "2026-10-03T00:00:00Z" }, now).active).toBe(true);
    expect(premiumFromDodo({ ...base, status: "past_due", past_due_ends_at: "2026-09-30T00:00:00Z" }, now).active).toBe(false);
  });
  it("ended states revoke", () => {
    for (const status of ["cancelled", "expired", "on_hold", "failed", "paused", "pending"]) {
      expect(premiumFromDodo({ ...base, status, next_billing_date: "2026-12-01T00:00:00Z" }, now)).toMatchObject({ active: false, expiresAt: null });
    }
  });
  it("an active sub whose period long ended is not premium", () => {
    expect(premiumFromDodo({ ...base, status: "active", next_billing_date: "2026-09-01T00:00:00Z" }, now).active).toBe(false);
  });
  it("only trusts well-formed Firebase uids from metadata", () => {
    expect(uidFromMetadata({ firebase_uid: "abcDEF1234567890abcdEF12" })).toBe("abcDEF1234567890abcdEF12");
    expect(uidFromMetadata({ firebase_uid: "../users/x" })).toBeNull();
    expect(uidFromMetadata(null)).toBeNull();
  });
});
