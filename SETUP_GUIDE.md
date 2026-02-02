# Commonplace - Setup Guide

This guide will help you set up and run Commonplace on your iPhone.

## Prerequisites

1. **Mac with Xcode 15+** - Required for iOS development
2. **Apple Developer Account** (optional for simulator, required for device) - $99/year at [developer.apple.com](https://developer.apple.com)
3. **Supabase Account** (free) - [supabase.com](https://supabase.com)
4. **Claude API Key** (for AI features) - [console.anthropic.com](https://console.anthropic.com)

## Quick Start (Demo Mode)

If you just want to test the app without setting up the backend:

1. Open the project in Xcode
2. Select an iPhone simulator or your device
3. Build and run (⌘R)
4. On the auth screen, tap "Try Demo Mode"

Demo mode uses local sample data and doesn't require Supabase or Claude API.

---

## Full Setup

### Step 1: Set Up Supabase

1. Go to [supabase.com](https://supabase.com) and create a free account
2. Create a new project (name it "commonplace" or similar)
3. Wait for the project to be ready (takes ~2 minutes)
4. Go to **Project Settings > API** and copy:
   - Project URL (e.g., `https://xxxx.supabase.co`)
   - Anon/Public key (starts with `eyJ...`)
   - Service Role key (for backend, starts with `eyJ...`)

### Step 2: Run Database Migration

1. In Supabase, go to **SQL Editor**
2. Open the file `supabase/migrations/001_initial_schema.sql`
3. Copy the entire contents
4. Paste into the SQL Editor and click "Run"
5. You should see "Success" - this creates all the tables

### Step 3: Deploy Edge Function

1. Install Supabase CLI:
   ```bash
   npm install -g supabase
   ```

2. Login to Supabase:
   ```bash
   supabase login
   ```

3. Link your project:
   ```bash
   cd /path/to/Commonplace
   supabase link --project-ref YOUR_PROJECT_ID
   ```

4. Set your Claude API key as a secret:
   ```bash
   supabase secrets set CLAUDE_API_KEY=sk-ant-your-key-here
   ```

5. Deploy the function:
   ```bash
   supabase functions deploy process-url
   ```

### Step 4: Configure iOS App

1. Open `iOS/Commonplace.xcodeproj` in Xcode

2. Edit `iOS/Commonplace/App/Config.swift`:
   ```swift
   static let supabaseURL = "https://YOUR_PROJECT_ID.supabase.co"
   static let supabaseAnonKey = "eyJ...YOUR_ANON_KEY..."
   ```

3. For the Share Extension, also update:
   - `iOS/CommonplaceShareExtension/ShareView.swift` - same credentials

### Step 5: Set Up Signing (for device testing)

1. In Xcode, select the "Commonplace" project in the navigator
2. Select the "Commonplace" target
3. Go to "Signing & Capabilities" tab
4. Check "Automatically manage signing"
5. Select your Team (requires Apple Developer account)
6. Repeat for "CommonplaceShareExtension" target

### Step 6: Run the App

1. Connect your iPhone or select a simulator
2. Press ⌘R to build and run
3. The app should launch!

---

## Testing

### Simulator Testing
- Works fully without Apple Developer account
- Share Extension works: Safari > Share > Commonplace

### Device Testing
- Requires Apple Developer account ($99/year)
- Must add your device UDID to developer portal

---

## Features by Mode

### Demo Mode (No backend required)
- ✅ View sample documents
- ✅ Browse library
- ✅ Search (local only)
- ✅ View document details
- ❌ Save new URLs
- ❌ AI summaries

### Full Mode (Supabase + Claude)
- ✅ All demo features
- ✅ Save any URL via Share Extension
- ✅ AI-powered summaries
- ✅ Category detection
- ✅ Full-text search
- ✅ Cloud sync

---

## Troubleshooting

### "The request failed" error
- Check your Supabase URL and key in Config.swift
- Verify the Edge Function is deployed: `supabase functions list`

### Share Extension not showing
- Make sure both targets have the same Team selected
- Try restarting the device/simulator

### AI summaries not working
- Verify CLAUDE_API_KEY secret is set: `supabase secrets list`
- Check Edge Function logs: `supabase functions logs process-url`

### Build errors
- Clean build folder: ⌘⇧K
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`

---

## Project Structure

```
Commonplace/
├── iOS/                        # iOS App
│   ├── Commonplace/            # Main app
│   │   ├── App/                # App entry, config
│   │   ├── Core/               # Models, services
│   │   ├── Features/           # UI screens
│   │   ├── DesignSystem/       # Colors, fonts, components
│   │   └── Utilities/          # Extensions, helpers
│   └── CommonplaceShareExtension/  # Share extension
└── supabase/                   # Backend
    ├── functions/              # Edge functions
    └── migrations/             # Database schema
```

---

## Next Steps

Once you have the app running:

1. **Try Demo Mode** first to understand the UI
2. **Set up Supabase** for cloud storage
3. **Add Claude API** for AI features
4. **Save some URLs** using the Share Extension

For questions or issues, check the [Issues](https://github.com/your-repo/issues) page.

Happy reading! 📚
