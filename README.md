# Selene — AI Palm, Tarot & Horoscope (Flutter + Firebase + Gemini)

Specs live in `../docs`. This folder is the app (`lib/`), Cloud Functions (`functions/`), and Firebase config.

## What's implemented
- **Onboarding → Sign in (email or guest) → Profile setup** (name, DOB → zodiac, focus areas, reader, language, AI/age consent)
- **Home** (hero, Ask me anything, 6 feature tiles, Premium banner, Today's Cosmic Vibes with daily card / moon phase / horoscope)
- **AI Palm Reading**: camera/gallery, left/right hand, tips, compression + EXIF strip, upload, Gemini photo validation, full reading, Analyzing + AI Working screens, results (Overview with neon line overlay, Line Analysis, Personality), Love / Career / Life Path screens, Save & Share card
- **Tarot**: question + topics + spread picker + AI toggle, card draw (server-side CSPRNG), result with per-position meanings, synthesis, advice, affirmation, follow-ups → chat
- **Tarot Spreads** (9 built-in, premium gating) + **Create Your Own Spread**
- **Card Meanings**: 78 Rider–Waite–Smith cards (offline JSON), search, filters, AI Insight, tabs, collection, detail page
- **Horoscope**: sign picker, Today/Week/Month/Year (week+ premium), affirmation, love/career/health/lucky, moon phase, moon calendar
- **AI Readers**: 6 personas, chat with `draw_cards` function calling, history, crisis-safety reply
- **My Readings**, **Profile/Settings** (photo retention, delete photos, delete account), **Paywall**

## Run locally (emulators + real Gemini)
1. Put the Gemini key in `functions/.secret.local` (`GEMINI_API_KEY=...`) — git-ignored.
2. `start_emulators.bat` (builds functions, starts Auth/Firestore/Storage/Functions; UI at http://127.0.0.1:4000).
3. Start an Android emulator, then: `flutter run --dart-define=USE_EMULATOR=true`
4. Backend checks: `cd functions && npm test` (unit) and `node functions/scripts/e2e.mjs` (end-to-end, real Gemini).

In emulator builds the paywall's button grants Premium (`devSetPremium`, emulator-only) so gated features can be tested.

## Production backend (live)
Project `selene-ai-34251` (Blaze), everything in `asia-south1` (Mumbai):
- Firestore `(default)`, Storage bucket `selene-ai-34251.firebasestorage.app`, security rules deployed
- Auth: Email/Password + Anonymous
- 12 Cloud Functions (2nd gen). Gemini runs **only** inside Functions; the key is in Secret Manager (`GEMINI_API_KEY`), never in the app
- App Check **enforced** on Functions, Firestore, Storage and Auth. Android uses Play Integrity (debug SHA-1/256 registered); one debug token is registered for the Android emulator
- Smoke test: `APPCHECK_DEBUG_TOKEN=<token> node functions/scripts/prod-smoke.mjs`

Redeploy: `set FUNCTIONS_DISCOVERY_TIMEOUT=180 && firebase deploy --only functions,firestore,storage`
(The long timeout is needed on this PC; source loading is slow.)

Before release:
- Link the app in **Play Console** → App integrity → Play Integrity, and add the **release/upload key SHA-256** to the Firebase Android app. Otherwise real installs fail App Check.
- iOS: add the APNs/App Attest config in App Check before testing on iPhone.
- Set a **budget alert** in Google Cloud Billing (Gemini, Functions and Storage are pay-as-you-go).
- To test on another device/emulator, run a debug build, copy the `App Check debug token` line from logcat, and add it in Firebase console → App Check → Apps → Manage debug tokens.

## Not yet built
- Store purchases (RevenueCat + store products); the paywall shows "coming soon" in production
- Google / Apple sign-in (needs SHA-1 + OAuth config; Apple sign-in is mandatory on iOS if Google is offered)
- Push notifications (FCM), card text-to-speech, Hindi UI strings (the AI already answers in Hindi when selected)
- Custom camera overlay (uses the system camera + tips sheet instead)
