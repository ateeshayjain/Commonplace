// App Store subscriptions: asks Apple's App Store Server API for the status of
// a purchase and turns it into a tier.
//
// Signed data from the app or from a notification is decoded without checking
// its signature, and is only used to learn which subscription to ask Apple
// about. The tier comes from Apple's answer (over TLS, to a request signed with
// our key), so a forged transaction or notification can at most trigger a
// re-check of a real subscription. Who owns a purchase comes from Apple's
// record too: the app sets appAccountToken to the user's id at purchase.

import type { Tier } from './tiers.ts';

export type AppStoreEnvironment = 'Production' | 'Sandbox';

const API_BASE: Record<AppStoreEnvironment, string> = {
  Production: 'https://api.storekit.itunes.apple.com',
  Sandbox: 'https://api.storekit-sandbox.itunes.apple.com',
};

// App Store subscription status codes
export const STATUS = {
  active: 1,
  expired: 2,
  billingRetry: 3,
  gracePeriod: 4,
  revoked: 5,
} as const;

// JWSTransactionDecodedPayload (the fields used here)
export interface TransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  expiresDate?: number;
  appAccountToken?: string;
  environment: AppStoreEnvironment | 'Xcode' | 'LocalTesting';
  // 1 introductory offer, 2 promotional, 3 offer code, 4 win-back
  offerType?: number;
  offerDiscountType?: 'FREE_TRIAL' | 'PAY_AS_YOU_GO' | 'PAY_UP_FRONT';
  revocationDate?: number;
}

// JWSRenewalInfoDecodedPayload (the fields used here)
export interface RenewalInfo {
  autoRenewStatus: 0 | 1;
  gracePeriodExpiresDate?: number;
}

// GET /inApps/v1/subscriptions/{transactionId}
export interface StatusResponse {
  environment: AppStoreEnvironment;
  bundleId: string;
  data: {
    subscriptionGroupIdentifier: string;
    lastTransactions: {
      originalTransactionId: string;
      status: number;
      signedTransactionInfo: string;
      signedRenewalInfo: string;
    }[];
  }[];
}

// App Store Server Notifications V2 (responseBodyV2DecodedPayload)
export interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  data?: {
    bundleId?: string;
    environment?: AppStoreEnvironment;
    signedTransactionInfo?: string;
  };
}

// One subscription as stored in app_store_subscriptions
export interface SubscriptionState {
  originalTransactionId: string;
  productId: string;
  status: number;
  expiresAt: string | null;
  trialEndsAt: string | null;
  autoRenews: boolean;
  environment: AppStoreEnvironment;
  appAccountToken: string | null;
}

// MARK: JWS

function base64UrlToBytes(input: string): Uint8Array {
  const base64 = input.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(input.length / 4) * 4, '=');
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// The payload of a JWS, NOT signature-checked (see the note at the top)
export function decodeJWSPayload<T>(jws: string): T {
  const parts = jws.split('.');
  if (parts.length !== 3) {
    throw new Error('Not a signed App Store payload');
  }
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(parts[1]))) as T;
}

// MARK: App Store Server API

// An In-App Purchase key from App Store Connect (Users and Access >
// Integrations > In-App Purchase), stored as Supabase secrets
export interface AppStoreCredentials {
  issuerId: string;
  keyId: string;
  privateKey: string; // the .p8 file's PEM text
  bundleId: string;
}

export function credentialsFromEnv(): AppStoreCredentials | null {
  const issuerId = Deno.env.get('APP_STORE_ISSUER_ID');
  const keyId = Deno.env.get('APP_STORE_KEY_ID');
  const privateKey = Deno.env.get('APP_STORE_PRIVATE_KEY');
  if (!issuerId || !keyId || !privateKey) return null;
  return {
    issuerId,
    keyId,
    // Pasted secrets sometimes carry literal \n instead of line breaks
    privateKey: privateKey.replace(/\\n/g, '\n'),
    bundleId: Deno.env.get('APP_STORE_BUNDLE_ID') ?? 'app.commonplace.ios',
  };
}

// The bearer token for the App Store Server API: an ES256 JWT, valid for at
// most an hour. WebCrypto's ECDSA signature is already JWS's r||s form.
export async function appStoreToken(credentials: AppStoreCredentials, now: Date = new Date()): Promise<string> {
  const pem = credentials.privateKey.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
  const issuedAt = Math.floor(now.getTime() / 1000);
  const encode = (value: unknown) => bytesToBase64Url(new TextEncoder().encode(JSON.stringify(value)));
  const signingInput = `${encode({ alg: 'ES256', kid: credentials.keyId, typ: 'JWT' })}.${encode({
    iss: credentials.issuerId,
    iat: issuedAt,
    exp: issuedAt + 20 * 60,
    aud: 'appstoreconnect-v1',
    bid: credentials.bundleId,
  })}`;
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );
  return `${signingInput}.${bytesToBase64Url(new Uint8Array(signature))}`;
}

// The subscription's current status from Apple. Tries the environment the
// purchase says it came from first, then the other one (TestFlight and App
// Review buy in Sandbox against this same backend). Null when Apple has no
// such transaction in either.
export async function fetchSubscriptionStatus(
  credentials: AppStoreCredentials,
  transactionId: string,
  hint: string | undefined
): Promise<StatusResponse | null> {
  const first: AppStoreEnvironment = hint === 'Sandbox' ? 'Sandbox' : 'Production';
  const order: AppStoreEnvironment[] = first === 'Sandbox' ? ['Sandbox', 'Production'] : ['Production', 'Sandbox'];
  const token = await appStoreToken(credentials);
  for (const environment of order) {
    const response = await fetch(
      `${API_BASE[environment]}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`,
      { headers: { Authorization: `Bearer ${token}` } }
    );
    if (response.status === 404) {
      await response.body?.cancel();
      continue;
    }
    if (!response.ok) {
      throw new Error(`App Store Server API returned ${response.status}: ${await response.text()}`);
    }
    return await response.json() as StatusResponse;
  }
  return null;
}

// MARK: Status → tier

export function grantsAccess(status: number): boolean {
  return status === STATUS.active || status === STATUS.gracePeriod;
}

const isoOrNull = (ms: number | undefined) => (ms ? new Date(ms).toISOString() : null);

// Our subscription in Apple's status response: the most recent transaction
// for one of `productIds`. Null when the response has none.
export function subscriptionState(
  response: StatusResponse,
  productIds: readonly string[]
): SubscriptionState | null {
  let best: SubscriptionState | null = null;
  let bestPurchase = -1;
  for (const group of response.data ?? []) {
    for (const last of group.lastTransactions ?? []) {
      const transaction = decodeJWSPayload<TransactionInfo>(last.signedTransactionInfo);
      if (!productIds.includes(transaction.productId)) continue;
      const renewal = last.signedRenewalInfo ? decodeJWSPayload<RenewalInfo>(last.signedRenewalInfo) : null;

      // In the grace period, access lasts until the grace period ends
      const expiresMs = last.status === STATUS.gracePeriod && renewal?.gracePeriodExpiresDate
        ? renewal.gracePeriodExpiresDate
        : transaction.expiresDate;
      const inTrial = transaction.offerType === 1 && transaction.offerDiscountType === 'FREE_TRIAL';

      if (transaction.purchaseDate <= bestPurchase) continue;
      bestPurchase = transaction.purchaseDate;
      best = {
        originalTransactionId: last.originalTransactionId,
        productId: transaction.productId,
        status: last.status,
        expiresAt: isoOrNull(expiresMs),
        trialEndsAt: inTrial && grantsAccess(last.status) ? isoOrNull(transaction.expiresDate) : null,
        autoRenews: renewal ? renewal.autoRenewStatus === 1 : false,
        environment: response.environment,
        appAccountToken: transaction.appAccountToken?.toLowerCase() ?? null,
      };
    }
  }
  return best;
}

export interface StoredSubscription {
  status: number;
  expires_at: string | null;
}

// A user's tier from every App Store subscription they own: Pro while any of
// them grants access and hasn't run out. expiresAt is the latest end of access
// (kept when they've all lapsed, for the record).
export function tierFromSubscriptions(
  rows: StoredSubscription[],
  now: Date = new Date()
): { tier: Tier; expiresAt: string | null } {
  let latestActive: number | null = null;
  let latest: number | null = null;
  for (const row of rows) {
    const expires = row.expires_at ? new Date(row.expires_at).getTime() : null;
    if (expires !== null && (latest === null || expires > latest)) latest = expires;
    if (grantsAccess(row.status) && expires !== null && expires > now.getTime()) {
      if (latestActive === null || expires > latestActive) latestActive = expires;
    }
  }
  if (latestActive !== null) {
    return { tier: 'pro', expiresAt: new Date(latestActive).toISOString() };
  }
  return { tier: 'free', expiresAt: latest !== null ? new Date(latest).toISOString() : null };
}
