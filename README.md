# Taste Decoder

A native iOS app that helps you **articulate your taste**. Save things you like fast, then interrogate each save up a three-rung ladder:

1. **Feeling** — "this feels uncomfortable / cozy / electric"
2. **Reference** — "feels like a Michel Gondry movie", "giving 90s skate zine"
3. **Ingredients** — "harsh flash lighting", "toasted oak", "brushed drums"

Collections then distill what keeps showing up ("9 of 10 saves share harsh flash lighting") into a taste statement in the shape *feeling + ingredients*:

> I like visuals that feel uncomfortable — distortion, flash lighting, acidic color.

Every feeling, reference and ingredient opens a **Learn card** (the person, style or term behind it, with examples, related topics, and why it matters to *your* saves). Your confirmed tags grow into a searchable **Pantry**, and **Compare** puts two collections side by side to find the common ground.

The app ships with four worked examples (Uncomfy, Reds I Love, Rooms, 2am Songs) so it demonstrates itself on first open.

---

## Requirements

| | |
|---|---|
| Xcode | **16.0 or later** (built against the iOS 18 SDK; Xcode 26 works too) |
| iOS | **17.0+** deployment target. The chip → card zoom transition needs iOS 18; on iOS 17 it falls back to a standard push. |
| Device | iPhone (portrait) |
| Tools | [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project |
| Claude | Optional. A Claude API key unlocks AI tag suggestions, statement polishing and new Learn cards. Everything else (including the demo and all bundled Learn cards) works offline. |
| Backend | Optional. A [Supabase](https://supabase.com) project adds Google sign-in, cloud sync, Claude without a key on the phone, and Pinterest import. See [Backend setup](#backend-setup). |

## Build and run on your iPhone

```bash
# 1. Install XcodeGen (once)
brew install xcodegen

# 2. Personal settings: team, bundle id prefix, Claude key
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
open -e Config/Secrets.xcconfig     # fill in the values (see below)

# 3. Generate the Xcode project and open it
xcodegen generate
open TasteDecoder.xcodeproj
```

Then in Xcode:

1. Plug in your iPhone (or pair it over Wi‑Fi) and select it as the run destination.
2. Choose the **TasteDecoder** scheme and press **⌘R**.
3. First run on a device: on the iPhone, open *Settings ▸ General ▸ VPN & Device Management*, trust your developer certificate, and enable *Developer Mode* if asked (*Settings ▸ Privacy & Security ▸ Developer Mode*).

> Re-run `xcodegen generate` whenever you add, move or delete files. The `.xcodeproj` is generated and gitignored.

### `Config/Secrets.xcconfig`

| Setting | What to put |
|---|---|
| `TD_DEVELOPMENT_TEAM` | Your Apple Developer Team ID (Xcode ▸ Settings ▸ Accounts ▸ your team). Leave empty to pick it in Xcode's *Signing & Capabilities* tab instead — but that choice is lost the next time you run `xcodegen generate`. |
| `TD_BUNDLE_ID_PREFIX` | Something unique to you, e.g. `com.yourname`. Bundle ids become `com.yourname.TasteDecoder` and `com.yourname.TasteDecoder.Share`; the App Group becomes `group.com.yourname`. |
| `CLAUDE_API_KEY` | Your Claude API key (`sk-ant-…`). Optional — see below. |
| `CLAUDE_MODEL` | Optional. `claude-opus-5-5` (default, best), `claude-sonnet-5-5` (faster) or `claude-haiku-4-5` (fastest). Also switchable in the app. |

`Secrets.xcconfig` is gitignored, so your key and team id never get committed.

### Where to put the Claude API key

Either place works; the in-app one wins if both are set.

- **In the app (recommended):** *Save* tab ▸ gear icon ▸ *Claude* ▸ paste the key ▸ *Save key*. It's stored in the iPhone's Keychain.
- **At build time:** `CLAUDE_API_KEY = sk-ant-…` in `Config/Secrets.xcconfig`. It's injected into the app's Info.plist, so treat that build as personal.

Get a key at [platform.claude.com](https://platform.claude.com). The app calls the Messages API directly with structured outputs; images are downscaled to ≤1568 px before they're sent. With Claude Opus 5.5 or Sonnet 5.5 it opts into the server-side refusal fallback (`server-side-fallback-2026-07-01`) and retries without it if your account doesn't have that beta.

### Free Apple ID (personal team)?

Personal teams can't use App Groups, which the Share Extension needs to hand saves to the app. Uncomment these two lines in `Secrets.xcconfig`, then run `xcodegen generate` again:

```
TD_APP_ENTITLEMENTS =
TD_SHARE_ENTITLEMENTS =
```

Everything works except saving from the iOS share sheet; the extension will say so.

## Backend setup

Everything in this section is optional. Without it the app stays local-only, exactly as above. With it you get:

- **Sign in with Google** (Settings ▸ Account). Your collections, saves, tags, edited Learn cards and images sync to your account and come back when you sign in on another device or reinstall. The app stays local-first, so it works offline and syncs when it can.
- **Claude through the backend.** While you're signed in, AI calls go through a Supabase Edge Function that holds the Anthropic key, so no key ships on the phone. Each user gets a daily allowance (`CLAUDE_DAILY_LIMIT`, default 300 requests).
- **Pinterest import** (Collections ▸ ＋ ▸ Import from Pinterest). Connect Pinterest, pick boards, and Claude reads up to 20 pins per board. Each board becomes **one collection** with a Pinterest badge, plus a summary: what the board is about, its common elements (with "n of 20" counts), feelings, references and a taste statement. Distill, Compare, the Pantry and Learn all work with it. Importing a board again refreshes it in place.

The backend lives in [`supabase/`](supabase/): one SQL migration and six Edge Functions.

### 1. Supabase project

1. Create a project at [supabase.com](https://supabase.com) and install the [Supabase CLI](https://supabase.com/docs/guides/cli).
2. From the repo root:
   ```bash
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase db push                 # tables, row-level security, storage bucket
   supabase functions deploy        # claude, pinterest-start, -callback, -boards, -pins, -disconnect
   ```
3. Note your **project ref** (the `abcd1234` in `https://abcd1234.supabase.co`) and the **anon/publishable key** (*Project Settings ▸ API*).

### 2. Google sign-in

1. In [Google Cloud Console](https://console.cloud.google.com) ▸ *APIs & Services ▸ Credentials*, create two **OAuth client IDs**:
   - **iOS**, with your app's bundle id (`<TD_BUNDLE_ID_PREFIX>.TasteDecoder`). Note its **client ID** and **iOS URL scheme** (the reversed client id).
   - **Web application**. Note its client ID and secret.
2. In Supabase ▸ *Authentication ▸ Sign In / Providers ▸ Google*, enable Google, paste the **Web** client ID and secret, add the **iOS** client ID to the authorized client IDs (comma-separated after the Web one), and turn on **Skip nonce check** (native iOS sign-in doesn't send one).

### 3. Pinterest app

1. At [developers.pinterest.com](https://developers.pinterest.com/apps/) create an app and add this **redirect URI**:
   `https://<your-project-ref>.supabase.co/functions/v1/pinterest-callback`
2. Note the **App ID** and **App secret key**. New apps start on **Trial access**, which is enough for your own boards (1,000 requests a day). To let other people import, apply for Standard access.

### 4. Server secrets

```bash
supabase secrets set \
  ANTHROPIC_API_KEY=sk-ant-... \
  PINTEREST_APP_ID=... \
  PINTEREST_APP_SECRET=... \
  CLAUDE_DAILY_LIMIT=300          # optional
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to Edge Functions automatically.

### 5. App config

Add to `Config/Secrets.xcconfig`, then run `xcodegen generate` again:

```
SUPABASE_PROJECT_REF = abcd1234
SUPABASE_ANON_KEY = eyJ...
GOOGLE_IOS_CLIENT_ID = 1234567890-abc.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.1234567890-abc
```

Use the project ref, not the full URL, because xcconfig treats `//` as the start of a comment.

### How sync works

- Every row (collection, save, tag, edited Learn card) is mirrored to Postgres with row-level security, so each user can only see their own rows. Images go to a private Storage bucket under `<user id>/`.
- The app compares each row's content fingerprint with what it last synced. Changed rows are uploaded. Deleted rows become tombstones (`deleted_at`) so other devices remove them too. Server changes are applied unless the same row also has local edits that haven't synced yet, in which case your device's version wins.
- Sync runs at launch, when the app comes to the foreground or goes to the background, after an import, and from *Settings ▸ Account ▸ Sync now*.
- The demo collections have the same IDs on every device, so they merge instead of duplicating.
- Signing out keeps your data on the device. *Reset everything* while signed in clears it on every device.
- `collections.visibility` is already in the schema so collections can be shared with friends later.

## Share Extension

Saving while scrolling is the core habit, so there's a **Share Extension**: in Photos, Safari, Instagram or any app, tap *Share ▸ Taste Decoder* (you may need *More…* the first time to add it to your favorites). Pick an optional collection and note, tap *Save*, and keep scrolling. The save appears in the app's *Save* tab next time you open it, ready to decode.

How it works: the extension writes the image(s) and a small JSON file into the shared App Group container; the app imports them when it becomes active. The extension never opens the database.

## Using the app

| Tab | What it's for |
|---|---|
| **Save** | Capture fast: camera, photos (multi-select), link, note, or the paste button. Everything lands in *To decode*. Swipe right to decode, left to delete; long-press for more. |
| **Collections** | Your collections as visual cards. Open one for its taste statement and an edge-to-edge grid; tap **Distill** for the hero reveal (counts fill in, then the statement lands). Swipe a collection to compare or edit it. |
| **Pantry** | Every confirmed feeling, reference and ingredient with counts, searchable and filterable. Rename to merge duplicates; long-press to copy. |
| **Learn** | Your core ingredients, what to explore next, cards written for you, and the full library of people, styles and terms. Search to look anything up. |

**Decoding a save** asks "Why did you save this?", then walks *Feeling ▸ Reference ▸ Ingredients*. With a Claude key, suggestions appear as dashed chips. Tap one to keep it (or ✕ to reject it); nothing counts until you confirm it. Your pantry's most-used tags show up as one-tap picks so patterns form quickly. **Decode all** runs through a queue of saves back to back.

**Definition-of-done walkthrough:** create a collection → *Add ▸ Photos* → pick 10 → tap the *Decode N saves* banner → tag each at all three levels → open **Distill** to see 3–5 recurring ingredients with "N of 10" counts and the statement. Tap any ingredient for its Learn card. Use **Compare** (Collections toolbar) to see shared ingredients highlighted as common ground. *Reds I Love* vs *Rooms* is a good demo: warm, cozy and leather.

## Project layout

```
project.yml                  XcodeGen spec: app, Share Extension, unit tests
Config/                      xcconfigs, entitlements (Info.plists are generated here)
TasteDecoder/
  App/                       App entry, root tabs, settings model
  Core/                      Foundation-only logic: tag normalization, distillation,
                             statements, comparison, pantry, Learn card model
  Models/                    SwiftData models (collections, saves, tags, cached cards)
  Services/                  Claude client + prompts (incl. board summaries), capture, link previews, Keychain,
                             Learn library, backend (Supabase rows + storage), sync, Pinterest import
  Seed/                      The four worked examples + 69 bundled Learn cards (JSON)
  Design/                    Theme tokens, chips, flow layout, procedural art, item visuals
  Navigation/                Routes and shared navigation destinations
  Features/                  Save, Interrogate, Collections (incl. Distillation), Learn,
                             Pantry, Compare, Export, Import (Pinterest), Settings
  Resources/Assets.xcassets  Accent color (acid lime), app icon
Shared/                      Code shared with the Share Extension (App Group, images, inbox)
TasteDecoderShare/           Share Extension
Tests/TasteCoreTests/        Unit tests for the core logic
Package.swift                Lets the core logic be tested with `swift test` on any machine
supabase/                    Backend: SQL migration (tables, RLS, storage) and Edge Functions (Deno)
```

### Design notes

- **Dark-first.** Default appearance is Dark; *Settings ▸ Appearance ▸ Match System* allows light mode. Surfaces use semantic system colors; acid lime (`AccentColor`, with a darker variant for light mode) is reserved for interactive elements and confirmed ingredients.
- **Counting is local, prose is Claude.** Recurrence counts are computed on device (`TasteDecoder/Core/TasteCore.swift`). Claude only suggests tags (always pending your approval), polishes statements and writes Learn cards.
- **Motion.** Springs throughout. Suggestion chips glide into place when kept (`matchedGeometryEffect`), ingredient chips zoom into their Learn card on iOS 18 (`navigationTransition(.zoom)`), and distillation bars fill in sequence with rolling numbers before the statement lands with a haptic. Reduce Motion skips the stagger.

## Tests

```bash
swift test          # core logic: distillation, statements, compare, pantry, imported profiles (macOS or Linux)
cd supabase/functions && deno test _shared/   # Pinterest response mapping
```

In Xcode, the **TasteDecoder** scheme's test action runs the same tests (*⌘U*).

CI (`.github/workflows/ios-build.yml`) runs `swift test`, type-checks and tests the Edge Functions with Deno, and builds for the simulator with `xcodebuild` on a macOS runner for every push.

## Not in this MVP

Sharing with friends (the schema is ready for it), widgets and onboarding are out of scope for now. Spotify and Apple Music imports are possible next sources: Apple Music via MusicKit on the device, and Spotify only for a handful of users while its Development Mode limits stay in place.
