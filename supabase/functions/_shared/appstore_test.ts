import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  appStoreToken,
  decodeJWSPayload,
  grantsAccess,
  STATUS,
  type StatusResponse,
  subscriptionState,
  tierFromSubscriptions,
} from "./appstore.ts";
import { PRO_PRODUCT_IDS } from "./tiers.ts";

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
// An unsigned stand-in for Apple's JWS: decodeJWSPayload never checks the signature
const jws = (payload: unknown) =>
  `${b64url(new TextEncoder().encode('{"alg":"ES256"}'))}.${b64url(new TextEncoder().encode(JSON.stringify(payload)))}.sig`;

const USER = "6F1D2C3B-0000-4000-8000-00000000ABCD";
const day = 24 * 60 * 60 * 1000;
const now = new Date("2026-10-30T12:00:00Z");

function statusResponse(
  entries: { productId: string; status: number; purchase: number; expires: number; trial?: boolean; autoRenew?: 0 | 1; grace?: number }[],
): StatusResponse {
  return {
    environment: "Sandbox",
    bundleId: "app.commonplace.ios",
    data: [{
      subscriptionGroupIdentifier: "21500000",
      lastTransactions: entries.map((e, i) => ({
        originalTransactionId: `20000000000000${i}`,
        status: e.status,
        signedTransactionInfo: jws({
          transactionId: `30000000000000${i}`,
          originalTransactionId: `20000000000000${i}`,
          bundleId: "app.commonplace.ios",
          productId: e.productId,
          purchaseDate: e.purchase,
          expiresDate: e.expires,
          appAccountToken: USER,
          environment: "Sandbox",
          ...(e.trial ? { offerType: 1, offerDiscountType: "FREE_TRIAL" } : {}),
        }),
        signedRenewalInfo: jws({ autoRenewStatus: e.autoRenew ?? 1, ...(e.grace ? { gracePeriodExpiresDate: e.grace } : {}) }),
      })),
    }],
  };
}

Deno.test("decodeJWSPayload reads the middle part and rejects other shapes", () => {
  assertEquals(decodeJWSPayload<{ a: number }>(jws({ a: 1 })), { a: 1 });
  // Base64url characters (- and _) and missing padding
  assertEquals(decodeJWSPayload<{ s: string }>(jws({ s: "ü?>>" })).s, "ü?>>");
  assertThrows(() => decodeJWSPayload("not-a-jws"));
});

Deno.test("appStoreToken is an ES256 JWT Apple can verify with the key's public half", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----`;

  const token = await appStoreToken({ issuerId: "issuer-1", keyId: "KEY123", privateKey: pem, bundleId: "app.commonplace.ios" }, now);
  const [header, payload, signature] = token.split(".");
  assertEquals(decodeJWSPayload(`x.${header}.x`), { alg: "ES256", kid: "KEY123", typ: "JWT" });
  assertEquals(decodeJWSPayload(token), {
    iss: "issuer-1",
    iat: now.getTime() / 1000,
    exp: now.getTime() / 1000 + 1200,
    aud: "appstoreconnect-v1",
    bid: "app.commonplace.ios",
  });
  const sig = Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - signature.length % 4) % 4)), (c) => c.charCodeAt(0));
  assertEquals(sig.length, 64); // r||s, as JWS ES256 requires
  assert(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, sig, new TextEncoder().encode(`${header}.${payload}`)));
});

Deno.test("grantsAccess: active and billing grace period only", () => {
  assertEquals(grantsAccess(STATUS.active), true);
  assertEquals(grantsAccess(STATUS.gracePeriod), true);
  assertEquals(grantsAccess(STATUS.expired), false);
  assertEquals(grantsAccess(STATUS.billingRetry), false);
  assertEquals(grantsAccess(STATUS.revoked), false);
});

Deno.test("subscriptionState: a free trial reports when it ends and who bought it", () => {
  const start = now.getTime() - 3 * day;
  const state = subscriptionState(
    statusResponse([{ productId: "sangrah.pro.monthly", status: STATUS.active, purchase: start, expires: start + 30 * day, trial: true }]),
    PRO_PRODUCT_IDS,
  )!;
  assertEquals(state.productId, "sangrah.pro.monthly");
  assertEquals(state.status, 1);
  assertEquals(state.expiresAt, new Date(start + 30 * day).toISOString());
  assertEquals(state.trialEndsAt, new Date(start + 30 * day).toISOString());
  assertEquals(state.autoRenews, true);
  assertEquals(state.environment, "Sandbox");
  assertEquals(state.appAccountToken, USER.toLowerCase());
});

Deno.test("subscriptionState: grace period access runs to the grace end; no trial date once paid", () => {
  const grace = now.getTime() + 10 * day;
  const state = subscriptionState(
    statusResponse([{ productId: "sangrah.pro.yearly", status: STATUS.gracePeriod, purchase: now.getTime() - 365 * day, expires: now.getTime() - day, grace }]),
    PRO_PRODUCT_IDS,
  )!;
  assertEquals(state.expiresAt, new Date(grace).toISOString());
  assertEquals(state.trialEndsAt, null);
});

Deno.test("subscriptionState: picks the latest of our products and ignores others", () => {
  const response = statusResponse([
    { productId: "sangrah.pro.monthly", status: STATUS.expired, purchase: now.getTime() - 60 * day, expires: now.getTime() - 30 * day },
    { productId: "sangrah.pro.yearly", status: STATUS.active, purchase: now.getTime() - 20 * day, expires: now.getTime() + 345 * day, autoRenew: 0 },
    { productId: "someone.else.product", status: STATUS.active, purchase: now.getTime(), expires: now.getTime() + day },
  ]);
  const state = subscriptionState(response, PRO_PRODUCT_IDS)!;
  assertEquals(state.productId, "sangrah.pro.yearly");
  assertEquals(state.autoRenews, false);
  assertEquals(subscriptionState(statusResponse([]), PRO_PRODUCT_IDS), null);
  assertEquals(subscriptionState(
    statusResponse([{ productId: "someone.else.product", status: 1, purchase: 1, expires: 2 }]),
    PRO_PRODUCT_IDS,
  ), null);
});

Deno.test("tierFromSubscriptions: Pro while any subscription grants access and hasn't run out", () => {
  const future = new Date(now.getTime() + 5 * day).toISOString();
  const later = new Date(now.getTime() + 40 * day).toISOString();
  const past = new Date(now.getTime() - day).toISOString();

  assertEquals(tierFromSubscriptions([], now), { tier: "free", expiresAt: null });
  assertEquals(tierFromSubscriptions([{ status: 1, expires_at: future }], now), { tier: "pro", expiresAt: future });
  assertEquals(tierFromSubscriptions([{ status: 1, expires_at: future }, { status: 1, expires_at: later }], now).expiresAt, later);
  // Refunded (revoked) with time left: no access
  assertEquals(tierFromSubscriptions([{ status: 5, expires_at: future }], now), { tier: "free", expiresAt: future });
  // Billing retry without a grace period: no access
  assertEquals(tierFromSubscriptions([{ status: 3, expires_at: future }], now).tier, "free");
  // Status not updated yet but the date has passed
  assertEquals(tierFromSubscriptions([{ status: 1, expires_at: past }], now), { tier: "free", expiresAt: past });
  // An expired subscription doesn't hide an active one
  assertEquals(tierFromSubscriptions([{ status: 2, expires_at: later }, { status: 4, expires_at: future }], now), { tier: "pro", expiresAt: future });
});
