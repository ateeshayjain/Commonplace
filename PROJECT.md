# 📝 CommonPlace

## Overview
iOS app for saving web content with AI-powered summaries. Users share URLs from any app → content gets extracted, summarized by Claude, and stored in a searchable library.

**Status:** 🟢 Active Development
**Platform:** iOS (SwiftUI), iOS 17+ target
**Code Location:** `~/WIP Apps/Commonplace/`
**Last Updated:** February 2026

---

## Quick Links

| Resource | Link |
|----------|------|
| Code Folder | ~/WIP Apps/Commonplace/ |
| Supabase | [Add Dashboard URL] |
| GitHub | [Add URL] |
| Asana | See project-tasks-asana.csv |

---

## Current Development Status

### ✅ Completed
- Full iOS app with Library, Search, Profile, Auth flows
- Supabase backend with RLS, Edge Functions
- Share Extension for URL capture
- **Phase 2 Complete:**
  - Compose (multi-doc synthesis)
  - Campaigns (social publishing)
  - Voice profiles
  - OAuth connections (Twitter/LinkedIn)
  - PDF export

### 🚧 In Progress
- Fix AI enrichment in `process-url` edge function
- Actual Supabase project deployment (currently using demo mode)

### 📋 Pending
- Sprint wrap-up
- GitHub PR for recent changes
- Unit tests

---

## Tech Stack

### iOS App
- **Language:** Swift 5.9+
- **Framework:** SwiftUI
- **Target:** iOS 17+
- **Auth:** Sign in with Apple, Magic Link (OTP)
- **Storage:** Keychain (tokens), UserDefaults (preferences)

### Backend
- **Platform:** Supabase
- **Database:** PostgreSQL + Row Level Security
- **Functions:** Supabase Edge Functions
- **Auth:** Supabase Auth

### AI
- **Provider:** Claude API (Anthropic)
- **Model:** claude-sonnet-4-20250514
- **Uses:** Summaries, synthesis, post generation, voice analysis

### OAuth
- Twitter OAuth 2.0 (PKCE)
- LinkedIn OAuth 2.0

### PDF Generation
- pdf-lib (server-side)
- Supabase Storage bucket

---

## Features

### Core Reader
- **URL Capture:** Share Extension for one-tap saves from any app
- **Content Extraction:** Jina Reader API for clean article extraction
- **AI Enrichment:**
  - Short summary (2-3 sentences)
  - Long summary (2-3 paragraphs)
  - Key points (3-5 bullet points)
  - Complexity score (1-10)
  - Reading level detection
- **16 Source Types:** Twitter, LinkedIn, Medium, Substack, YouTube, Reddit, HackerNews, etc.

### Library
- Document library with search
- Category filtering
- Reading history

### Compose (Multi-Doc Synthesis)
- Select multiple documents
- AI synthesis with thinking depths:
  - Surface (1st order insights)
  - Second Order (patterns/connections)
  - Third Order (implications/contrarian)
- Output formats: Post, Thread, Newsletter, Article, Summary

### Campaigns (Social Publishing)
- Create campaigns from documents
- Platform-specific post generation (Twitter 280 chars, LinkedIn 3000 chars)
- Voice profile matching for consistent tone
- 3 variations per platform
- Schedule and publish

### Voice Profiles
- Analyze user's social posts
- Extract: tone, vocabulary level, post structure, hashtag usage, engagement style, emoji usage
- Apply voice to AI-generated content

---

## Architecture

### Folder Structure
```
iOS/Commonplace/
├── App/           # CommonplaceApp.swift, ContentView.swift, Config.swift
├── Core/
│   ├── Models/    # Document, User, Category (Codable structs)
│   ├── Services/  # AuthService, DocumentService, SupabaseService, CampaignService
│   └── Networking/# APIClient
├── Features/      # MVVM per feature
│   ├── Library/   # LibraryView + LibraryViewModel
│   ├── Detail/    # DocumentDetailView + DocumentDetailViewModel
│   ├── Search/    # SearchView + SearchViewModel
│   ├── Profile/   # ProfileView
│   ├── Compose/   # ComposeView + ComposeViewModel
│   ├── Campaigns/ # CampaignView + CampaignViewModel
│   └── Onboarding/# AuthView, OnboardingView
├── DesignSystem/  # Colors, Typography, Spacing, Components/
└── Utilities/     # Extensions, HapticManager
```

### Design Patterns
- **MVVM:** Views bind to `@StateObject` ViewModels
- **Services:** Singletons via `static let shared`
- **Main Thread:** ViewModels and AuthService are `@MainActor`
- **Auth:** `AuthService` injected via `@EnvironmentObject`

### Edge Functions
- `process-url` - Content extraction + Claude AI enrichment
- `synthesize-content` - Multi-document synthesis
- `generate-posts` - Platform-specific post generation
- `analyze-style` - Voice profile analysis
- `oauth-connect` - OAuth flow handler
- `generate-pdf` - PDF generation

---

## Environment Variables

### iOS App (Config.swift)
```swift
static let supabaseURL = "YOUR_SUPABASE_URL"
static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
```

### Supabase Secrets
```bash
ANTHROPIC_API_KEY=sk-ant-...
JINA_API_KEY=...
TWITTER_CLIENT_ID=...
TWITTER_CLIENT_SECRET=...
LINKEDIN_CLIENT_ID=...
LINKEDIN_CLIENT_SECRET=...
```

---

## Credentials

### Supabase
- Project URL: `[Add here]`
- Anon Key: `[Add here]`
- Service Role Key: `[Store securely]`

### Claude API
- API Key: `[Store in Supabase secrets]`

### OAuth Apps
- Twitter App: `[Add developer portal link]`
- LinkedIn App: `[Add developer portal link]`

### Google OAuth (Legacy)
- Client ID: `218018331354-0skfufmloh0crdoun1up6ak96jpphpik.apps.googleusercontent.com`
- Webapp Client ID: `218018331354-0dqt99fidqhinsu3b8122g2t4n32padc.apps.googleusercontent.com`

---

## Setup & Development

```bash
# Open iOS project in Xcode
cd ~/WIP\ Apps/Commonplace/iOS
open Commonplace.xcodeproj

# Configure Supabase
# Edit iOS/Commonplace/App/Config.swift with your Supabase credentials

# Deploy Edge Functions
cd ~/WIP\ Apps/Commonplace/supabase
supabase functions deploy process-url
supabase functions deploy synthesize-content
supabase functions deploy generate-posts
supabase functions deploy analyze-style
supabase functions deploy generate-pdf
```

---

## Subscription Tiers

| Tier | Saves/Month | Posts/Month |
|------|-------------|-------------|
| Free | 50 | 10 |
| Pro | Unlimited | Unlimited |
| Creator | Unlimited | Unlimited |
| Team | Unlimited | Unlimited |

---

## Roadmap

### Current Sprint
- [ ] Fix AI enrichment in process-url
- [ ] Supabase production deployment
- [ ] GitHub repo setup and push

### Next
- [ ] App Store submission
- [ ] Analytics integration
- [ ] Offline mode
- [ ] iPad optimization

### Future
- [ ] Web app (React)
- [ ] Browser extensions
- [ ] Team features

---

## Notes

- **Demo Mode:** App currently runs in demo mode (demo@commonplace.app)
- **CLAUDE.md:** Full development context in `~/WIP Apps/Commonplace/CLAUDE.md`
- **Asana Tasks:** See `project-tasks-asana.csv` for task tracking
- Target users: Knowledge workers who save articles/threads and want AI insights
