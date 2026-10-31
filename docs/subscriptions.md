# Sangrah Pro: subscriptions

How the free and Pro tiers work, what to set up in App Store Connect, and how to switch it on. Code: `supabase/functions/_shared/tiers.ts` (limits), `supabase/migrations/010_subscription_tiers.sql`, `process-url`, `verify-purchase`, `app-store-notifications`, iOS `SubscriptionService`, `PaywallView`, `Plan.swift`, and the Share Extension's `ScreenshotReader` with `Shared/ScreenshotText.swift`.

## 1. The tiers

Decided by the owner on 31 Oct 2026: saving is free, the smart summary is Pro, because every summary is a paid call to Claude's API.

| | Free | Pro |
|---|---|---|
| Saves | 5 per day (UTC; 5:30 am in India). The 6th gets "limit reached" and the paywall | Unlimited |
| Clean article text, Read Full Article PDF, Listen, Library search, manual categories, notes, widget, Weekly Summary | Yes | Yes |
| Smart summary: Key Idea, short and long summary, key points, verbatim quotes and quote cards, AI tags and auto-categories | No: the save's page shows a "Smart summary" card explaining it's Pro | Yes, on Claude Sonnet 5.5 (about 1.4¢ an article), fair use 300 a month (UTC); after that saves are kept and get their summary next month |
| Screenshot saves | Read on the iPhone by Apple's text recognition (Vision, English and Hindi), joined into one article; nothing uploaded, no Claude | Uploaded and read by Claude (about 4¢ a save), with the smart summary |
| Compose (`synthesize-content`) | Paywall | 10 runs a month, on Claude Opus 5.5 |
| Writing posts and voice analysis (`generate-posts`, `analyze-style`) | Paywall | Yes, on Opus 5.5 (no monthly cap yet) |
| Price | | India ₹299/month or ₹2,499/year; US $5.99/month or $49.99/year; first month free |

Everything is enforced in Edge Functions; the app only shows the numbers `verify-purchase` returns.

- Free saves stop after extraction: `processing_status = completed`, AI fields empty, `documents.ai_waiting = true`. Upgrading summarises the newest 10 straight away; on Pro, Summarise on a save does one.
- The daily save and the monthly smart summary are claimed with `claim_usage` (one SQL statement, so two saves can't both take the last one) in `usage_counts`, not counted from `documents`, so deleting saves doesn't give them back. A save that fails to insert, or a summary Claude doesn't write, is given back.
- If the daily check itself fails, a free save goes through (it costs no Claude call). If the smart-summary check fails, the Pro save waits rather than running Claude unmetered.
- Free screenshot uploads (an older build, or the Share Extension acting on a stale plan) are refused with `pro_required` and deleted; the extension then reads them on the device.
- Users can't change `users.subscription_tier` or `subscription_expires_at`: a trigger rejects it for the `authenticated` and `anon` roles (project.md known issue 7).
- "Why does Sangrah cost money?" is answered on the paywall and in the FAQ (`ProCopy.whyItCosts`).

## 2. How a purchase becomes Pro

1. The paywall buys `sangrah.pro.monthly` or `sangrah.pro.yearly` with `appAccountToken` = the user's id.
2. The app sends the StoreKit transaction (JWS) to `verify-purchase`.
3. `verify-purchase` reads only the transaction id from it, asks Apple's App Store Server API for that subscription's status (signed with the In-App Purchase key), checks that Apple's record names this user (`appAccountToken`), stores it in `app_store_subscriptions`, and sets the tier and expiry on `users`.
4. Apple calls `app-store-notifications` on renewals, expiries, refunds and billing problems. It re-reads the status from Apple the same way, so a forged notification can't change anything.
5. The app re-sends its current entitlement at every launch, and Restore Purchases does the same after `AppStore.sync()`.

Access runs while Apple says the subscription is active (status 1) or in the billing grace period (status 4), and only until the stored expiry, so a missed renewal notification lapses to free instead of leaving Pro on forever. Sandbox purchases (TestFlight, App Review) are accepted too; Apple renews them every few minutes and stops after a few renewals.

A purchase with no `appAccountToken` (an offer code redeemed in the App Store app) isn't linked automatically: anyone who learned its transaction id could otherwise claim it. To link one by hand, insert its row into `app_store_subscriptions` for the right user, then the user taps Restore Purchases.

## 3. App Store Connect setup (owner)

Do these in order. Product ids are permanent: once created they can never be used again, even if deleted.

1. **Agreements.** Business > Agreements, Tax, and Banking: the Paid Apps agreement must be active, with bank and tax details. Until it is, the products don't load, not even in TestFlight.
2. **Subscription group.** Apps > Sangrah: Commonplace Book > Monetization > Subscriptions > Subscription Groups > Create. Reference name `Sangrah Pro`. Add an App Store localization (English): display name `Sangrah Pro`.
3. **Monthly subscription.** In the group, Create: reference name `Sangrah Pro Monthly`, product id **`sangrah.pro.monthly`**. Then:
   - Subscription Duration: 1 month. Family Sharing: off.
   - Availability: all countries and regions.
   - Subscription Prices > Add Subscription Price: base country India, **₹299**. Accept the generated prices, then edit United States to **$5.99**.
   - App Store Localization (English): display name `Sangrah Pro Monthly`, description `Smart summaries, unlimited saves and Compose`.
   - Review Information: a screenshot of the paywall (Profile > Upgrade to Pro), and the review note from step 9.
4. **Yearly subscription.** Same group, Create: reference name `Sangrah Pro Yearly`, product id **`sangrah.pro.yearly`**, duration 1 year, base price India **₹2,499**, United States **$49.99** (if Apple's price list doesn't have the exact point, pick the nearest and tell me so the paywall copy can match). Same localization pattern (`Sangrah Pro Yearly`). Both subscriptions stay at level 1 in the group: same features, different billing period.
5. **Free month.** For each subscription: Subscription Prices > Introductory Offers > Create: all countries, start today, no end date, **Free**, duration **1 month**. The paywall reads eligibility from the App Store and shows "Start Free Month" only to Apple IDs that haven't had it.
6. **Billing grace period.** Subscriptions (the page with the groups) > Billing Grace Period: turn on (16 days, all renewals). The server keeps Pro during grace.
7. **Server notifications.** App Information > App Store Server Notifications: version **Version 2**, Production Server URL and Sandbox Server URL both `https://gfnqjaombxxkiinxhahv.supabase.co/functions/v1/app-store-notifications`. Use "Request a Test Notification" afterwards: the function logs `App Store notification TEST ignored`.
8. **In-App Purchase key.** Users and Access > Integrations > In-App Purchase > Generate In-App Purchase Key (name `Sangrah server`). Download the `.p8` (only once) and note the Key ID and the Issuer ID shown on that page. This is a different key from the App Store Connect API key used by `scripts/upload-build.sh`; that one can't call the App Store Server API.
9. **Review notes** (on each subscription, and in the app version's App Review Information): "Sangrah Pro is offered from Profile > Upgrade to Pro, from the Smart summary card on a saved article, after a free account's 5th save of the day, and from Compose. Restore Purchases and Manage Subscription are in Profile. Terms of Use: Apple's standard EULA. Privacy Policy: in the app under Profile > Privacy Policy."
10. **Privacy policy URL.** Apps with subscriptions need a public privacy policy URL in App Information. The policy exists only inside the app today; it needs a web page before App Store submission.
11. **Submit together.** The first subscriptions must be submitted with an app version: on the version page, In-App Purchases and Subscriptions > add both. TestFlight builds can buy them (free, in Sandbox) once their metadata is complete ("Ready to Submit").
12. **Your own account.** After the migration, every account starts free. To keep yours on Pro without paying: `UPDATE users SET subscription_tier = 'pro', subscription_expires_at = NULL WHERE email = '<you>';` in the SQL editor (a null expiry never lapses).

If the bundle id moves to `app.sangrah.*` with a new App Store record (project.md §6), the subscriptions have to be created again on that record, and `APP_STORE_BUNDLE_ID` changed.

## 4. Switching it on (each step needs the owner's go-ahead)

Order matters: the functions call `claim_usage` and read the new columns, so the migration goes first. Without it, saves never finish processing (the `ai_waiting` column is missing).

1. Apply `supabase/migrations/010_subscription_tiers.sql`.
2. Set the secrets (Project Settings > Edge Functions > Secrets, or `supabase secrets set`):
   - `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`
   - `APP_STORE_PRIVATE_KEY`: the whole `.p8` file, header lines included
   - `APP_STORE_BUNDLE_ID` = `app.commonplace.ios`
3. Deploy `process-url`, `synthesize-content`, `generate-posts`, `analyze-style`, `verify-purchase`, and `app-store-notifications` (JWT verification off for that one; `config.toml` sets it).
4. Ship the app build with the paywall. Builds 27 and 28 keep working against the new functions, but on a free account they show new saves without a summary and no explanation, a generic error on the 6th save of the day, and an error for screenshot saves. Ship the new build before or with the deploy.

Once deployed, every existing account (TestFlight testers included) is free: new saves get no smart summary until they subscribe or are set to Pro by hand.

## 5. Testing

- `deno test supabase/functions/_shared`: limits, daily and monthly periods, refusal codes, App Store status → tier, the account-token rules.
- iOS `CommonplaceTests`: `ScreenshotTextTests` (chrome, paragraphs, overlap between screenshots, cut-off lines, Devanagari), `PlanTests` (plan card text, footnotes, trial reminder date, yearly savings, decoding) and `SubscriptionStoreKitTests`, which buys both plans from `iOS/Sangrah.storekit` with StoreKitTest and checks the transaction fields `verify-purchase` reads. The products test passes once the app has been run from Xcode on that simulator (which applies the test file) and skips otherwise, as in CI. The two purchase tests are opt-in (`SANGRAH_STOREKIT_PURCHASE_TESTS=1`) and haven't passed yet: here purchases went to the real Sandbox instead of the local StoreKit environment.
- Running from Xcode uses `iOS/Sangrah.storekit` (scheme > Run > Options > StoreKit Configuration), so the paywall shows ₹299 / ₹2,499 and purchases go through locally. Add `-SangrahDemoFreePlan` to the Run arguments to see the free plan (today's 5 saves used) in demo mode. Those purchases are signed by Xcode, so `verify-purchase` refuses them (`local_storekit`); the app says the purchase couldn't be confirmed. To test end to end, use a TestFlight build (Sandbox).
- Sandbox timing: a 1-month period lasts about 5 minutes and a year about an hour, so a free month converts within minutes.
