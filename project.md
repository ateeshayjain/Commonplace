# SangrahAI (संग्रह) — Project Plan

Multi-format AI content aggregator, organizer, and repurposing pipeline. Users capture content from anywhere (web, Substack, YouTube, Instagram, physical books), Claude turns it into layered summaries and tags, and the app re-exports that knowledge as PDFs, carousels, quote graphics, and video scripts.

This repo started as **Commonplace** (a save-and-summarize iOS app). SangrahAI is built on top of it rather than as a rewrite. Coding conventions live in [`CLAUDE.md`](CLAUDE.md); this file covers scope, status, and the development plan.

---

## 1. Key decisions

| Topic | PRD said | We do | Why |
|---|---|---|---|
| iOS app | React Native | **SwiftUI** (existing app) | About half the PRD already exists natively; Share Extension, VisionKit scanning, and the native share sheet are first-class in Swift |
| Backend | Next.js 15 API routes | **Supabase Edge Functions** (Deno/TypeScript) | Already built: auth, RLS, 6 functions |
| Database / ORM | Prisma + PostgreSQL | **Supabase Postgres, plain SQL migrations** | RLS policies are the security model; Prisma bypasses them. PRD schema mapped in migration 004 |
| Job queue | BullMQ (Redis) | **Supabase Queues (pgmq) + a worker Edge Function on pg_cron** | No Redis to run; queue lives in the same database. Decide in Phase 0 (see §6) |
| File storage | S3 / Cloudflare R2 | **Supabase Storage** (`pdfs` public, `generated-assets` private + signed URLs) | Same auth and RLS as the database |
| AI | Unspecified | **Claude Opus 5.5** (summaries, posts, tags, scripts), **Claude Fable 5.1** (multi-doc synthesis) | Set in `supabase/functions/_shared/claude.ts` |
| Web app | Next.js | **Deferred** | iOS first; a web client can reuse the same Supabase backend later |

### PRD → codebase mapping

| PRD | Here |
|---|---|
| `SavedItem` | `documents` table (`ai_hook`, `metadata`, `book_ocr` added in migration 004) |
| `hook` / `executiveSummary` / `keyTakeaways` | `ai_hook` / `ai_summary_long` / `ai_key_points` |
| `Tag` | `tags` + `document_tags` (per user, deduplicated by slug) |
| `Collection` | `collections` + `collection_documents` (Swift: `DocumentCollection`) |
| `GeneratedAsset` | `generated_assets` + `generated-assets` bucket |
| `/types/generation.ts` | `supabase/functions/_shared/generation.ts` + `iOS/Commonplace/Core/Models/GeneratedAsset.swift` |
| `POST /api/v1/ingest` | `process-url` Edge Function |
| `POST /api/v1/export/pdf` | `generate-pdf` (single doc today; dossier planned) |
| `POST /api/v1/generate/*` | New Edge Functions, Phase 4 |

---

## 2. Current status (as of 2026-10-24)

### By PRD module

| Module | Feature | Status | Notes |
|---|---|---|---|
| iOS rules | Share Extension | ⚠️ Code exists, **not built** | `ShareView.swift` / `ShareViewController.swift` aren't in any Xcode target |
| | Camera / document scanning | ❌ Missing | |
| | Native share sheet for generated assets | ❌ Missing | |
| | Offline cache | ❌ Missing | `Config.enableOfflineMode` flag exists, unused |
| 1 Ingestion | Web / Substack | 🟡 Partial | Jina Reader extraction in `process-url`; plain text, not Markdown; images not kept |
| | YouTube transcripts | ❌ Missing | URL detected as `youtube`, but only page text is extracted |
| | Instagram (captions, carousel images, Reel audio) | ❌ Missing | URL detected only |
| | Book OCR | 🟡 Schema only | `book_ocr` source type and `BookOcrMetadata` exist |
| 2 AI | Hierarchical summary | 🟡 Partial | Short/long summary + key points exist; no `hook`; JSON parsed by regex |
| | Auto-tagging | 🟡 Schema only | `tags` tables exist; enrichment still writes `ai_topics` JSON |
| | Multi-doc synthesis | ✅ Built | `synthesize-content` (Fable 5.1, depth-scaled effort); Compose UI |
| 3 PDF | Single brief | ✅ Built | `generate-pdf` with pdf-lib |
| | Multi-doc dossier with TOC | ❌ Missing | |
| 4 Generation | Carousel | ❌ Missing | Types defined |
| | Quote graphic | ❌ Missing | Types defined |
| | Video script | ❌ Missing | Types defined |
| | Generated video | ❌ Missing | Optional in PRD |
| Extra | Social posting (Twitter/LinkedIn OAuth, voice profiles, campaigns) | ✅ Built | Commonplace Phase 2; keep |

### Infrastructure

| Item | Status |
|---|---|
| Supabase project `commonplace` (`gfnqjaombxxkiinxhahv`, ap-south-1) | **Live.** Migrations 001–004 applied (non-destructive variant: old search fn revoked not dropped; `book_ocr` deferred to 005). All 6 Edge Functions deployed 2026-10-26 |
| Migrations 001–004 | Written; verified on local Postgres (PGlite) including RLS checks |
| Edge Functions | Pass `deno check`; never run against live services |
| iOS app | **Never compiled in this effort** (no Swift toolchain in the dev container) |
| `ANTHROPIC_API_KEY` secret | **Not set** — must be added in the Supabase dashboard (Edge Functions → Secrets); the classifier blocks secret writes from here. Until then AI calls fall back to plain excerpts |
| Tests / CI | None |

### Known issues and tech debt

| # | Issue | Where | Phase |
|---|---|---|---|
| 1 | Share Extension has no Xcode target | `iOS/CommonplaceShareExtension/` | 0 |
| 2 | Stale duplicate `DocumentDetailView` (not in project) | `iOS/Commonplace/Features/Library/DocumentDetailView.swift` | 0 |
| 3 | `Config.swift` points at the old, inaccessible project `mliivcgiyezaltfbnpzb` | `iOS/Commonplace/App/Config.swift`, `supabase/config.toml` | 0 |
| 4 | `process-url` fires background work without `EdgeRuntime.waitUntil`, so the runtime can kill it mid-processing | `supabase/functions/process-url/index.ts` | 0 |
| 5 | Some decoders use plain `.iso8601`, which fails on Postgres fractional-second timestamps | `SupabaseService.swift`, `APIClient.swift` | 0 |
| 6 | AI responses parsed with `text.match(/\{[\s\S]*\}/)` instead of structured outputs | 4 AI functions | 2 |
| 7 | `users` UPDATE policy lets a user change their own `subscription_tier` | migration 001 | 5 |
| 8 | Subscription limits enforced in UI only | — | 5 |
| 9 | No automated tests | — | 0 onward |

---

## 3. Target architecture

```
iOS app (SwiftUI)                    Supabase
─────────────────                    ────────────────────────────────────────────
Share Extension ──┐                  Edge Functions
Library / Search  │   HTTPS + JWT    ├─ ingest (process-url)  ──► enqueue job
Compose           ├────────────────► ├─ ingest-ocr            ──► enqueue job
Scanner (VisionKit)│                 ├─ generate/* (carousel, graphic, script, dossier)
Generated assets ─┘                  │        └─► insert generated_assets (queued) + enqueue
   ▲                                 │
   │ Realtime / poll status          ├─ worker (pg_cron, every ~10s)
   └──────────────────────────────── │    pops pgmq jobs → extract → Claude → render → store
                                     │
                                     Postgres (RLS)  documents, tags, collections,
                                                     generated_assets, campaigns, ...
                                     Storage         pdfs (public), generated-assets (private)
                                     Claude API      Opus 5.5 / Fable 5.1 via _shared/claude.ts
```

**Async job pattern** (ingestion and every generator):
1. The request function validates input, inserts the row (`documents` or `generated_assets`) with status `pending`/`queued`, enqueues `{ kind, id }`, and returns the id immediately.
2. The worker pulls jobs, sets status `processing`, runs the step, writes results, and sets `completed`/`failed` with `error`.
3. The app watches the row (Supabase Realtime, or polling as a fallback) and updates the UI.

This replaces BullMQ, gives retries via pgmq visibility timeouts, and keeps long Claude calls (Fable can take minutes) out of request handlers, which have wall-clock limits.

**Rendering** (carousels and quote graphics): Satori (JSX → SVG) + resvg-wasm (SVG → PNG) inside an Edge Function, with fonts bundled (including a Devanagari font such as Noto Sans Devanagari). Carousels are also stitched into a single PDF with pdf-lib for LinkedIn document posts. If Edge Function CPU/memory limits are too tight, rendering moves to a small container service; it sits behind the same job interface, so callers don't change.

---

## 4. Development plan

Each phase ends in something testable on a device. Sizes are relative: S ≈ a day or two, M ≈ a week, L ≈ two or more weeks.

### Phase 0 — Foundation: make the existing app run end to end

Goal: a real user can sign up, share a URL from Safari, and see an AI summary in the Library on a real backend.

| Task | Size |
|---|---|
| Add the Share Extension target in Xcode (App Group `group.app.commonplace`, shared Keychain), register its files | S |
| Delete the stale `Features/Library/DocumentDetailView.swift`; build the app in Xcode and fix any compile errors | S |
| Fix date decoding to accept fractional seconds everywhere (one shared decoder) | S |
| Wrap `process-url` background work in `EdgeRuntime.waitUntil` (stopgap until the queue lands) | S |
| ~~Deploy migrations 001–004 to `commonplace`; run Supabase security and performance advisors; fix findings~~ ✅ done 2026-10-26 | S |
| ~~Deploy all 6 Edge Functions~~ ✅; set `ANTHROPIC_API_KEY` (you, in dashboard) | S |
| ~~Point `Config.swift` and `supabase/config.toml` at the new project~~ ✅ | S |
| Configure auth: Magic Link redirect `commonplace://auth/callback`, Sign in with Apple | S |
| End-to-end test on device: sign up → share URL → summary → search → Compose → PDF | S |
| Test setup: Deno tests for Edge Function helpers; XCTest target for model decoding; pgTAP or a PGlite script for RLS | M |
| CI (GitHub Actions): `deno check` + Deno tests, migration replay on Postgres, `xcodebuild` on a macOS runner | M |

**Exit:** the end-to-end test passes on a physical iPhone, and CI is green.

### Phase 1 — Ingestion drivers (PRD Module 1)

Goal: every PRD source type lands as a clean `documents` row with source metadata.

| Task | Size |
|---|---|
| Job queue: enable pgmq + pg_cron, `worker` Edge Function, move `process-url` processing onto it with retries | M |
| Web/Substack: keep Markdown and image URLs from Jina Reader (`body_structured` + `media` rows); strip cookie, nav and paywall boilerplate | M |
| YouTube: transcript + metadata (channel, views, upload date, thumbnail, chapters) into `metadata`; transcript chunked by chapter | M |
| Instagram: caption, ordered carousel images into `media`, Reel audio transcription | L |
| Book OCR (iOS): VisionKit document camera (edge detection + perspective correction) → Vision text recognition on device → upload text and page images via a new `ingest-ocr` function | M |
| Share Extension: route images and PDFs (not just URLs) into ingestion | S |

**Exit:** each of the 5 PRD content types can be captured from the share sheet or camera and shows correct metadata in Detail.

### Phase 2 — AI transformation layer (PRD Module 2)

Goal: every document gets the PRD summary structure and tags, reliably.

| Task | Size |
|---|---|
| Switch enrichment to Claude structured outputs (`output_config.format` with a JSON schema) and drop regex parsing; apply to all 4 AI functions | M |
| Hierarchical summary: `hook` (≤150 chars, enforced in schema and code), executive summary (markdown bullets), exactly 3 key takeaways | S |
| Auto-tagging: Claude proposes tags, upserted into `tags` by slug, linked via `document_tags` (`source = 'ai'`); reuse the user's existing tags in the prompt to reduce drift | M |
| Retire `ai_topics` / `user_categories` in favour of tags (migration + UI) | M |
| Tags in the iOS UI: chips on Detail, filter in Library (`?tag=`), edit/merge | M |
| Synthesis: accept any mix of source types; output a comparative report saved as a document | S |
| Citations: summaries and synthesis link each claim to the source passage it came from (answers the AI-trust complaint, §8) | M |
| Output language: Hindi and Hinglish summaries, tags and posts as a user setting (no competitor offers this, §8) | M |
| Prompt eval set: 20–30 real saved items per source type, scored for summary quality and tag stability | M |

**Exit:** structured-output failures are under 1% on the eval set, and tags dedupe across a user's library.

### Phase 3 — PDF engine (PRD Module 3)

| Task | Size |
|---|---|
| Single brief redesign: metadata typography, source links, tag groups, layered summary; 1–2 pages | M |
| Dossier: `generate-dossier` job builds a multi-doc PDF with cover, table of contents with real page numbers, headers/footers, pagination; stored as a `pdf_dossier` asset | L |
| Collections UI (create, add, reorder) as the main way to pick dossier contents | M |
| Unicode/Devanagari font embedding in PDFs | S |
| Full library export (Markdown + JSON, with tags and collections), reachable from Profile (Pocket/Omnivore shutdowns made this a buying criterion, §8) | S |

**Exit:** a 10-document collection exports to a paginated dossier with a correct TOC, and Hindi text renders.

### Phase 4 — Generative repurposing (PRD Module 4)

| Task | Size |
|---|---|
| Generation framework: `generate/*` functions insert a `generated_assets` row and enqueue; worker dispatches by `format`; status shown in the app via Realtime | M |
| Carousel: Claude writes a 5–10 slide script (`CarouselContent`) → Satori templates (light/dark, 1080×1350) → PNG per slide + combined PDF | L |
| Quote graphic: Claude picks or accepts a quote → 3 presets (`minimal_card`, `dark_chart`, `bold_overlay`) → PNG | M |
| Video script: hook/body/CTA script timed to `targetDurationSec` (15–90 s) with on-screen text and visual cues | S |
| iOS: "Create" menu on Detail and Collections; asset gallery; preview; native share sheet to Instagram, LinkedIn, X, WhatsApp; save to Photos | M |
| Template design pass (brand, typography, safe areas per platform) | M |
| Attribution: every generated asset credits its sources (author, link); quotes length-capped | S |

**Exit:** from any saved item, the user can produce and post a carousel, a quote graphic and a video script in under a minute.

### Phase 5 — Polish, limits, and launch

| Task | Size |
|---|---|
| Offline: cache summaries and pinned PDFs on device; queue captures made offline | M |
| Public collections: share link + read-only view (needs a policy exposing documents in public collections, via a SECURITY DEFINER helper to avoid RLS recursion) | M |
| Subscription tiers: StoreKit 2, server-side enforcement of save/generation limits, lock `subscription_tier` to service role. Visible usage counters, one-tap cancel, INR pricing (≈₹199–299/mo, §8) | L |
| Rename to SangrahAI: display name, bundle id, App Group, URL scheme, repo docs | S |
| Observability: Edge Function logs, Claude usage/cost per user, job failure alerts | S |
| App Store: privacy labels, screenshots, review notes (scraping and social-platform terms) | M |

**Optional / later:** generated video (TTS + text-on-screen over captured media), web app, Android.

---

## 5. Dependencies and order

```
Phase 0 ──► Phase 1 (queue) ──► Phase 2 ──► Phase 3 ──► Phase 4 ──► Phase 5
                 │                  │                       ▲
                 └── job queue ─────┴───────────────────────┘ (reused by every generator)
```

- The job queue (Phase 1) blocks dossiers (Phase 3) and every generator (Phase 4).
- Structured outputs (Phase 2) block Phase 4: generators need schema-valid JSON.
- Collections UI (Phase 3) feeds dossiers and multi-item generation.
- Phase 4 rendering can be prototyped in parallel with Phase 2–3 against fixture JSON.

---

## 6. Open decisions

| Decision | Options | Needed by |
|---|---|---|
| Queue implementation | Supabase Queues (pgmq) + pg_cron worker (recommended) / Edge Function `waitUntil` only / external worker | Phase 1 |
| YouTube transcripts | Official captions API works only for your own videos, and YouTube blocks transcript fetching from cloud IPs (so it fails from Edge Functions). Options: fetch on the user's device and upload / paid transcript API (e.g. Supadata) / audio + speech-to-text. Recommended: on-device fetch, paid API as fallback | Phase 1 |
| Instagram capture | No public API for others' posts. Options: oEmbed caption only / user-shared media through the Share Extension / third-party scraper (terms-of-service risk). Recommended: process what the user shares, store derived notes + link rather than re-hosting media | Phase 1 |
| OCR engine | On-device Vision (free, private, offline; recommended) / Claude vision (better on complex layouts, costs per page) | Phase 1 |
| Speech-to-text for Reels and audio | Vendor TBD | Phase 1 |
| Rendering host | Satori + resvg-wasm in Edge Functions / container service | Phase 4 |
| Generated video | TTS + template animation / video model vendor / skip for v1 | Post-launch |
| Model cost controls | Fable 5.1 for synthesis only, or Opus 5.5 everywhere on the free tier | Phase 5 |
| App name and bundle id | Keep Commonplace ids / move to SangrahAI before App Store submission | Phase 5 |

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Platform terms (Instagram, YouTube) block or ban scraping | Prefer user-shared content and official endpoints; isolate each source in its own driver so one can be disabled |
| Edge Function time limits (≈150 s free / 400 s paid) vs long Claude calls | All heavy work runs in queued jobs; effort tuned per task; fallbacks write `failed` with a reason |
| Claude cost on heavy users | Per-user usage tracking, tier limits, effort tuning, prompt caching for repeated context |
| Render quality and fonts across scripts | Bundle fonts; snapshot tests of templates in CI |
| Untested iOS code (built without a compiler so far) | Phase 0 builds in Xcode first; CI with `xcodebuild` from then on |
| NotebookLM or Readwise adds share-sheet capture + post generation | Compete on what they lack: social-native capture, Hindi/Indic output, cited dossiers, voice-matched posting (§8) |

---

## 8. Competitive landscape

Full research with sources: [`docs/competitive-landscape.md`](docs/competitive-landscape.md) (October 2026; prices approximate).

**Who's out there**

| Category | Main tools | Typical gap |
|---|---|---|
| Read-later | Readwise Reader, Matter, Instapaper, GoodLinks, Raindrop, mymind (Pocket and Omnivore shut down) | Stop at reading; no repurposing; weak social capture; rising prices |
| AI second brain | NotebookLM, Recall, Glasp, Mem, Fabric, Heptabase, Eightify, Snipd | Hidden caps; hallucination complaints; no share-sheet social capture |
| Book capture | Readwise (paper OCR), Kindle export | Readwise is pricey for OCR alone; Kindle silently truncates highlights |
| Repurposing | Taplio, Supergrow, aiCarousels, Canva, Typefully, Castmagic, OpusClip | Start from a blank page or a URL; no knowledge library; billing complaints |
| Closest full-loop | resaw (new, Indian, share-anything → sorted actions), Second Brain/Rescroll (claims unverified), iOS capture apps (Stashwise, Fofo), Reel savers (Sorti, Siloe) | None covers capture → synthesis → dossier → voice-matched posts; resaw targets life admin (recipes, places), not knowledge |

**Where SangrahAI wins**
1. The only full loop: saved knowledge → cited synthesis → PDF dossier / carousel / post.
2. Social-native capture (Reels, carousels, captions) plus paper-book OCR.
3. Trust: citations, visible limits, easy cancel, full export from day one.
4. India: Hindi/Hinglish output and INR pricing. No competitor targets this.

**Biggest threats:** NotebookLM (already synthesizes and makes short videos) and Readwise Reader (has the library; adding "generate a post" is easy). Capture plus summary alone is a commodity, so the moat is synthesis quality, output formats, and India.

**What changed in this plan because of it:** citations and Hindi output (Phase 2), full export (Phase 3), attribution on generated assets (Phase 4), transparent limits and INR pricing (Phase 5), and on-device YouTube transcript fetching (§6).
