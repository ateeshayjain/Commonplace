# Branding and Design Guidelines

Status: **v0, October 2026.** Product name: **Sangrah** (see §4). The app uses Apple's native iOS design language with no custom brand yet. This document records what is in the code today, the rules that keep it consistent, and the decisions still open. A visual preview of these screens and tokens lives on the [UI Preview canvas](https://claude.ai/artifact/DbFSThgxohbSVEuxSmCGuk) (private; share from its menu).

## 1. Design principles

1. **Native first.** The app should feel like it shipped with iOS: system font, system colours, standard navigation, standard controls. Users already know how it works.
2. **Content is the interface.** Saved articles, summaries and tags are the visual weight; chrome stays quiet (white/grey surfaces, one accent).
3. **One accent, used sparingly.** The accent colour marks actions and selection only (buttons, links, selected chips, tab highlight). Never as a background wash or decoration.
4. **Dark mode for free.** Every colour comes from a semantic token that adapts automatically. No hard-coded hex values in screens.
5. **Platform colours belong to platforms.** Substack orange, Reddit orange-red, LinkedIn blue and X black identify a source and are used only for source badges, never for app UI.

## 2. Tokens as coded

Source files: `iOS/Commonplace/DesignSystem/Colors.swift`, `Typography.swift`, `Spacing.swift`.

### Colour

| Token | Value | Use |
|---|---|---|
| `cpTint` / `cpAccent` | `Color.blue` (#007AFF light / #0A84FF dark) | Buttons, links, selected chips, tab highlight, progress |
| `cpBackground` | `systemBackground` | Screen background |
| `cpBackgroundSecondary` | `secondarySystemBackground` (#F2F2F7) | Cards, summary box, search field |
| `cpText` | `label` | Primary text |
| `cpTextSecondary` | `secondaryLabel` | Summaries, metadata, section headers |
| `cpTextTertiary` | `tertiaryLabel` | Chevrons, read-time, faint metadata |
| `cpSeparator` | `separator` | Dividers |
| `cpSuccess` / `cpWarning` / `cpError` | system green / orange / red | Status only |

Category colours (Apple system palette, one per system category): Technology #007AFF, Business #34C759, Health #FF3B30, Science #AF52DE, Culture #FF9500, Politics #5856D6, Design #FF2D55, Personal Dev #00C7BE.

Source badge colours: Twitter/X #1DA1F2 (icon shown black), LinkedIn #0A66C2, YouTube #FF0000, Instagram #E4405F, Medium #000000, Substack #FF6719, Reddit #FF4500.

### Typography

System font (SF Pro) at Apple's standard scale. No custom typeface.

| Token | Size / weight | Use |
|---|---|---|
| `cpLargeTitle` | 34 bold | Screen titles (Library, Search, Profile) |
| `cpTitle1` | 28 bold | Document title on Detail |
| `cpTitle2` | 22 bold | Sheet titles |
| `cpTitle3` | 20 semibold | Hook pull-quote (italic), empty-state titles |
| `cpHeadline` | 17 semibold | Author names, primary buttons |
| `cpBody` | 17 regular | Summaries, key points, list titles (medium weight) |
| `cpCallout` | 16 regular | Row summaries |
| `cpSubhead` | 15 regular | Handles, timestamps, chips |
| `cpFootnote` | 13 regular | Row footers |
| `cpCaption1` | 12 regular | Tag chips, metadata |
| `sectionHeaderStyle()` | 13 semibold, uppercase, 0.5 tracking, secondary colour | "AI Summary", "Tags", "Key Points" |

### Spacing and shape

- Scale: 4, 8, 12, 16, 20, 24, 32, 48 pt (`CPSpacing.xxs` … `xxxl`).
- Screen gutter 20 pt, card padding 16 pt, list row vertical 12 pt, section spacing 24 pt.
- Corner radius: 8 (small), 12 (cards, buttons), 16 (chips, pills).
- Elevated cards: 8 pt blur, 2 pt y-offset, black at 8% (`CPElevatedCard`).
- Touch targets at least 44 × 44 pt.

### Components

`CPButton`, `CPIconButton`, `CPCard`, `CPElevatedCard`, `CPSearchBar`, `CPSearchChip`, `CPTagChip`, `CPEmptyState`, `CPLoadingView`, `SkeletonView`, `FlowLayout`. Build new UI from these before adding new components; new ones take the `CP` prefix and live in `DesignSystem/Components/`.

### Iconography

SF Symbols only (`Image(systemName:)`). Source types use their platform glyph or an emoji in `SourceType.icon`; this is the one place emoji is allowed, and it should be replaced with proper source logos when the icon set is designed (see §4).

## 3. Rules for contributors

- Use tokens, never literals: `.cpTint` not `.blue`, `.cpTextSecondary` not `.gray`, `CPSpacing.md` not `16`.
- Use the type tokens, never `.font(.system(size:))` in a screen. If a size is missing, add a token.
- Semantic colours only in screens; the hex values in `Colors.swift` are for categories and source badges and nothing else.
- Section headers use `sectionHeaderStyle()`; links use `linkTextStyle()`.
- Test every screen in dark mode and with Dynamic Type at the largest accessibility size before merging.
- Text contrast: at least 4.5:1 for body and captions, 3:1 for large text. Secondary grey on white passes; never put secondary text on the secondary background.
- Copy: sentence case for everything except section headers (uppercase via the style). Say "Saved", not "Bookmarked"; "Summary", not "TL;DR"; "Tags", not "Topics" once the migration from `ai_topics` is done.

## 4. Open decisions

| Decision | Current state | Where it changes |
|---|---|---|
| **App icon** | None. `Resources/Assets.xcassets/AppIcon.appiconset/` has no image; the home screen shows a blank placeholder | Drop a 1024 × 1024 PNG into that asset set |
| **Accent colour** | Apple system blue | `Colors.swift` → `cpTint` and `cpAccent`; `Assets.xcassets/AccentColor.colorset` (same value, used by system controls) |
| **Name** | **Decided 27 Oct 2026: "Sangrah"** (संग्रह, "collection"). Chosen over "Bookmark" (generic, untrademarkable, crowded) and "Commonplace" (three small apps already use it in this category). Display name and sign-in title are "Sangrah"; "bookmark" and "commonplace book" stay as App Store subtitle/keywords. Code identifiers (bundle id `app.commonplace.ios`, App Group `group.app.commonplace`, URL scheme `commonplace://`, repo name) are unchanged until App Store submission | `Info.plist`, `AuthView.swift` done; ids in `project.pbxproj` and the Share Extension later |
| **Mark** | None; sign-in screen uses the SF Symbol `books.vertical.fill`. Direction agreed: a bookmark glyph with an owned twist (stacked marks for "collection", or a Devanagari-style notch) | `AuthView.swift`, app icon asset |
| **Hindi in the mark** | Not present | Part of the icon/wordmark brief |
| **Custom typeface** | None (recommended: keep SF Pro) | `Typography.swift` if ever changed; must support Devanagari |
| **Source logos** | Emoji in `SourceType.icon` | Replace with an asset per source |

When these are decided, update §2, replace the preview canvas boards, and record the date here.

## 5. Brief template for a brand pass

To commission icon and accent options, answer these:

1. Three adjectives for how Sangrah should feel.
2. Two apps or brands whose look you admire, and one you want to avoid.
3. Should the Devanagari word संग्रह appear in the mark, the wordmark, or neither?
4. Light-mode accent preference: cool (blue/teal), warm (orange/clay), or neutral (ink/graphite)?
5. Any colour that must not be used.
