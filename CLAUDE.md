# Commonplace - Project Context

## Project Overview
iOS app for saving web content with AI-powered summaries. Users share URLs from any app → content gets extracted, summarized by Claude, and stored in a searchable library.

**Current State:**
- ✅ Built: iOS app with Library (search reads the saved text), Quotes, Profile, Auth flows
- ✅ Built: Supabase backend (project `gfnqjaombxxkiinxhahv`, live) with RLS, Edge Functions
- ✅ Built: Share Extension for links and up to 10 screenshots (combined into one save)
- ✅ Built: Quote cards (Key Idea + verbatim quotes, swipeable, share as image with caption), bookmarks in the Quotes tab, Save as Quote from selected text
- ✅ Built: Clean PDFs (Read Full Article, Share, Save to Files), Weekly Summary, Edit Title, saved categories, Delete Account
- ✅ Built: Daily Quote home-screen widget (`SangrahWidget`) with Shuffle
- ✅ Built: Phase 2 - Compose (multi-doc synthesis), Campaigns (social publishing), voice profiles, OAuth (Twitter/LinkedIn)
- 🚧 Shipping to TestFlight (see Release below); not yet on the App Store

**Target Users:** Knowledge workers who save articles/threads and want AI insights.

**Roadmap:** the app is becoming **Sangrah** (संग्रह; display name set, bundle ids still `app.commonplace.*`). See [`project.md`](project.md) for the PRD mapping, current status, and the phased development plan.

**Branding and design rules:** [`docs/branding.md`](docs/branding.md). Use design-system tokens (`cp*` colours, `cp*` fonts, `CPSpacing`), never literals; no custom brand exists yet (open decisions listed there).

## Tech Stack
- **iOS:** Swift 5.9+, SwiftUI, iOS 17+ target
- **Backend:** Supabase (PostgreSQL + Edge Functions + Auth)
- **AI:** Claude API — Claude Opus 5.5 (`claude-opus-5-5`) for summaries, post generation, voice analysis; Claude Fable 5.1 (`claude-fable-5-1`) for multi-doc synthesis
- **Auth:** Sign in with Apple, Magic Link (OTP)
- **OAuth:** Twitter OAuth 2.0 (PKCE), LinkedIn OAuth 2.0
- **PDF:** pdf-lib (server-side generation)
- **Storage:** Keychain (tokens), UserDefaults (preferences)

## Architecture

### Folder Structure
```
iOS/
├── Commonplace/       # The app
│   ├── App/           # CommonplaceApp.swift, ContentView.swift (tabs, commonplace://quotes), Config.swift
│   ├── Core/
│   │   ├── Models/    # Document, User, Category, SavedQuote, GeneratedAsset (Codable structs)
│   │   ├── Services/  # Auth, Document, Supabase, SavedQuote, Category, WidgetQuoteSync, SharedAuthStore, Campaign
│   │   └── Networking/# APIClient
│   ├── Features/      # MVVM per feature
│   │   ├── Library/   # LibraryView + LibraryViewModel + Components/ (search box matches body text)
│   │   ├── Detail/    # DocumentDetailView + ViewModel, QuoteCard (cards, credits, share sheet), PDFViewerView
│   │   ├── Quotes/    # QuotesView + QuotesViewModel (bookmarked quotes tab)
│   │   ├── Profile/   # ProfileView (+ Weekly Summary, Manage Categories), SupportViews (FAQ, Privacy, Contact)
│   │   ├── Compose/   # ComposeView + ComposeViewModel (multi-doc synthesis)
│   │   ├── Campaigns/ # CampaignView + CampaignViewModel (social publishing)
│   │   └── Onboarding/# AuthView, OnboardingView
│   ├── DesignSystem/  # Colors, BrandColors (shared with the widget), Typography, Spacing, Components/
│   └── Utilities/     # Extensions, HapticManager
├── CommonplaceShareExtension/ # Share sheet: links and screenshots
├── SangrahWidget/     # Daily Quote widget (WidgetKit + AppIntent shuffle)
├── Shared/            # WidgetQuote.swift: compiled into the app and the widget
└── CommonplaceTests/  # XCTest unit tests (hosted in the app)
```

Targets: `Commonplace` (app), `CommonplaceShareExtension`, `SangrahWidget`, `CommonplaceTests`. The app, share extension and widget share the App Group `group.app.commonplace` (keychain session, widget quote pool).

### Key Patterns
- **MVVM:** Views bind to `@StateObject` ViewModels
- **Services:** Singletons via `static let shared`
- **Main Thread:** ViewModels and AuthService are `@MainActor`
- **Auth:** `AuthService` injected via `@EnvironmentObject`
- **Shared state:** `SavedQuoteService` and `CategoryService` are `@MainActor` singletons with optimistic changes that roll back on failure; they reset when the signed-in user changes
- **Cross-screen updates:** `NotificationCenter` `.documentDeleted` / `.documentUpdated` keep the Library list in step with the detail screen

### Data Flow
```
View → ViewModel → Service → SupabaseService → URLSession
                                    ↓
                          JSONDecoder (ISO8601 dates)
```

## Coding Conventions

### Naming
- **Files:** PascalCase matching struct/class name
- **Views:** `*View.swift` (e.g., `LibraryView.swift`)
- **ViewModels:** `*ViewModel.swift`
- **Components:** `CP*` prefix for design system (CPButton, CPCard)
- **Colors:** `cp*` prefix (cpTint, cpBackground, cpTextSecondary)
- **Spacing:** `CPSpacing.*` enum (xs, sm, md, lg, xl)

### Swift Patterns
- Use `async/await` for all network calls
- Use `Task { }` for async work in sync contexts
- Debounce search with `Task.sleep` + cancellation
- Custom `CodingKeys` for snake_case API ↔ camelCase Swift

### Error Handling
- Custom error enums: `AuthError`, `SupabaseError`, `APIError`
- Conform to `LocalizedError` for user-facing messages
- Store errors in ViewModel's `@Published var error: Error?`

## Domain Rules

### Document Processing Pipeline
```
pending → fetching → extracting → enriching → rendering → completed
                                                      ↘ failed
```

### Subscription Tiers (enforced in UI, not backend yet)
| Tier | Saves/Month | Posts/Month |
|------|-------------|-------------|
| free | 50 | 10 |
| pro/creator/team | unlimited | unlimited |

### Source Types
twitter, linkedin, linkedinArticle, article, substack, medium, youtube, podcast, pdf, reddit, hackernews, instagram, threads, email, screenshot, manual, bookOcr (`book_ocr`), unknown

### AI Enrichment Fields
- `aiSummaryShort`: 2-3 sentences
- `aiSummaryLong`: 2-3 paragraphs
- `aiKeyPoints`: Array of 3-5 strings
- `aiComplexityScore`: 1-10 integer
- `aiReadingLevel`: casual | intermediate | advanced | expert

### Social Publishing Models
- `SocialPlatform`: twitter (280 chars max), linkedin (3000 chars max)
- `SocialConnection`: OAuth tokens, platform credentials, connection status
- `VoiceProfile`: tone, vocabularyLevel (1-10), postStructure, hashtagUsage, engagementStyle, topTopics, samplePhrases, emojiUsage, postingPatterns
- `Campaign`: Document-linked publishing campaign (draft/scheduled/publishing/published/failed)
- `CampaignPost`: Individual platform posts with variations

### Content Synthesis
- `ThinkingDepth`: surface (1st order), secondOrder (patterns/connections), thirdOrder (implications/contrarian)
- `OutputFormat`: post, thread, newsletter, article, summary
- Voice matching uses analyzed voice profiles for style consistency

### Database Tables
- `social_connections`: OAuth credentials per user/platform (unique constraint on user_id + platform)
- `pdfs` storage bucket: Public bucket for generated PDFs (user-scoped upload, public read). `documents.pdf_url` is cleared when a title changes; PDFs are made on first open or share, not at save time
- `saved_quotes` (migration 007): bookmarked quotes, unique per (user, document, text)
- `screenshots` storage bucket (migration 008): private, `{user_id}/{batch}/{n}.jpg`, JPEG only, 6 MB
- `categories`: built-in rows have `user_id` null; readers add and delete their own (delete policy: migration 009)
- Deleting an account (`delete-account`) removes storage files, then the `users` row (cascades to every table), then the auth user

### Sangrah Data Model (migration 004)
The Sangrah PRD's Prisma schema is mapped onto Supabase SQL, not Prisma:
- **SavedItem → `documents`**: adds `ai_hook` (PRD hook, ≤150 chars at generation) and `metadata` JSONB (YouTube channel/chapters, OCR pages). PRD `executiveSummary` → `ai_summary_long`, `keyTakeaways` → `ai_key_points`
- **Tag → `tags` + `document_tags`**: per-user (not global). `slug` is generated from `name` (ASCII spaces/punctuation stripped, lowercased) and unique per user, so "Design Trends" and "DesignTrends" dedupe. Don't use `[:punct:]` in slug regexes — it strips Devanagari viramas
- **Collection → `collections` + `collection_documents`** (Swift: `DocumentCollection`, to avoid clashing with `Swift.Collection`). `is_public` exposes the collection and its item list, not document contents
- **GeneratedAsset → `generated_assets`**: `format`, `status` (queued/processing/completed/failed), `params`, `content` (JSON shape depends on format), `storage_paths` in the private `generated-assets` bucket under `{user_id}/`. Created/updated only by Edge Functions (service role); users can read and delete
- Shapes are kept in sync across `migrations/004_sangrah_data_model.sql`, `supabase/functions/_shared/generation.ts`, and `iOS/Commonplace/Core/Models/GeneratedAsset.swift` (its content enum is `GeneratedAssetContent`; `GeneratedContent` is taken by Compose)
- New Swift files must be added to `project.pbxproj` by hand (no synchronized folders)

## External Dependencies

### Supabase Config (`Config.swift`)
```swift
static let supabaseURL = "YOUR_SUPABASE_URL"
static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
```

### Edge Functions
- `process-url`: Extracts content, calls Claude for AI enrichment
- `synthesize-content`: Multi-document synthesis with thinking depths (surface/secondOrder/thirdOrder)
- `generate-posts`: Platform-specific post generation with voice matching (3 variations per platform)
- `analyze-style`: Analyzes user's social posts to build voice profile
- `oauth-connect`: OAuth flow handler for Twitter/LinkedIn (PKCE support)
- `generate-pdf`: Clean PDF generation with pdf-lib, uploads to Supabase Storage (`PDF_LAYOUT_VERSION` must match `DocumentService.pdfLayoutVersion`)
- `delete-account`: Deletes the caller's files, rows and auth user (Profile > Delete Account)

### Claude API
- Used in Edge Functions: `process-url`, `synthesize-content`, `generate-posts`, `analyze-style`
- Models and SDK pin live in `supabase/functions/_shared/claude.ts` (`CLAUDE_MODELS`, `generateText`) — change them there, not per function
  - `standard`: `claude-opus-5-5` (process-url, generate-posts, analyze-style)
  - `deepReasoning`: `claude-fable-5-1` (synthesize-content; effort scales with `ThinkingDepth`)
- Thinking is always on for these models: control depth with `effort`, don't send `thinking: disabled`/`budget_tokens`, `temperature`, or assistant prefill (all return 400)
- Read text blocks by `type`, not `content[0]` (responses can start with thinking blocks)
- Server-side refusal fallback is enabled (`fallbacks: 'default'`); `generateText` throws on `stop_reason: "refusal"`
- For JSON results use `generateJSON` (structured outputs via `output_config.format`); keep schemas to types/enums/required/`additionalProperties:false` and enforce lengths and counts in code
- Tags: `_shared/tags.ts` (`slugify` must match the SQL slug rule; `attachTags` upserts by slug and links `document_tags`)
- Env var: `ANTHROPIC_API_KEY` in Supabase secrets

## Common Mistakes to Avoid

### Duplicate Definitions
Components in `CPCard.swift` should NOT be duplicated:
- `CPEmptyState`, `CPLoadingView`, `SkeletonView` live in CPCard.swift
- `FlowLayout` lives in DesignSystem/Components/FlowLayout.swift
- **Never create separate files for these**

### Generic Functions
When a generic parameter isn't used in signature, remove it:
```swift
// ❌ Wrong - T not used
func update<T: Codable>(table: String, values: [String: Any])

// ✅ Correct
func update(table: String, values: [String: Any])
```

### Onboarding Binding Logic
`OnboardingView(isComplete: $showOnboarding)` — when complete, set `isComplete = false` to dismiss (binding is inverted for "show" semantics)

### Navigation in Profile
Profile's `NavigationStack` uses destination links (`NavigationLink { View() } label:`). A value link (`NavigationLink(value:)` + `navigationDestination`) inside a screen pushed by a destination link bounces straight back. Keep to one style per stack.

### New targets and files
Every new Swift file, target or scheme testable is added to `project.pbxproj` by hand (no synchronized folders). Files shared by two targets (e.g. `Shared/WidgetQuote.swift`, `DesignSystem/BrandColors.swift`) get one file reference and a build file per target, and must not depend on app-only types.

### Demo Mode Detection
Check for demo user before API calls:
```swift
if AuthService.shared.currentUser?.email == "demo@commonplace.app" {
    // Use local demo data
}
```

## Project-Specific Parallelisation

### Independent Modules (can work simultaneously)
| Agent | Scope | Files |
|-------|-------|-------|
| A | Library feature | Features/Library/*, DocumentService |
| B | Quotes feature + widget | Features/Quotes/*, SavedQuoteService, SangrahWidget/*, Shared/* |
| C | Profile/Settings | Features/Profile/* |
| D | Design System | DesignSystem/* |
| E | Backend | supabase/* |
| F | Compose feature | Features/Compose/* |
| G | Campaigns feature | Features/Campaigns/*, CampaignService |

### Dependencies (what blocks what)
- **AuthService** blocks everything (auth required for API calls)
- **SupabaseService** blocks DocumentService and CampaignService
- **Document model** blocks all views that display documents
- **CampaignService** blocks Compose and Campaigns features
- **DesignSystem** blocks all views (but changes are low-risk)

### Recommended Subagent Split
For new features:
1. **Architect Agent**: Plan data model + API changes
2. **Backend Agent**: Supabase migrations + Edge Functions
3. **iOS Agent**: Swift models + Services
4. **UI Agent**: Views + ViewModels
5. **QA Agent**: Review all changes, test compilation

For bug fixes:
1. **Investigator**: Find root cause across codebase
2. **Fixer**: Implement fix
3. **Reviewer**: Verify fix, check for regressions

## Testing
- iOS: `xcodebuild test -project iOS/Commonplace.xcodeproj -scheme Commonplace -destination 'platform=iOS Simulator,name=<iPhone>' CODE_SIGNING_ALLOWED=NO` runs `CommonplaceTests` (quote text and credits, widget daily pick and shuffle, category slugs, Weekly Summary maths, support links). Tests use the demo documents as fixtures
- Edge Functions: `deno test supabase/functions/_shared` and `deno check` on each `index.ts`
- CI (`.github/workflows/ci.yml`) builds the app, runs the iOS tests, type-checks and tests the Edge Functions on every push

## Release (TestFlight)
- Bump `CURRENT_PROJECT_VERSION` everywhere in `project.pbxproj` (app, share extension, widget, tests) and `CFBundleVersion` in `iOS/Commonplace/Info.plist` (edit the text; PlistBuddy re-sorts keys)
- `xcodebuild archive -scheme Commonplace -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates`, then `scripts/upload-build.sh <archive>` with `ASC_KEY_ID` / `ASC_ISSUER_ID`
- A new bundle id (new extension) has no App Store profile yet and the API key can't create one: export once with the Xcode account (`xcodebuild -exportArchive ... -exportOptionsPlist iOS/ExportOptions.plist -allowProvisioningUpdates`, no key flags), then upload the .ipa with `xcrun altool --upload-app`
- Production deploys (Edge Functions, migrations) need the owner's explicit go-ahead each time
