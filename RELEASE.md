# Releasing Chatterloop

Everything needed to get a build into Google Play and the App Store, and the
things in this repo that are already done versus still outstanding.

Read [Blockers](#blockers) first — two of them ship a build that installs fine
and then fails in the user's hands.

---

## Current state

| | Android | iOS |
|---|---|---|
| Bundle id | `com.chatterloop.app` | `com.chatterloop.app` |
| Version | `1.0.0+1` (pubspec.yaml) | same |
| Release signing | **configured** (upload keystore) | not configured |
| Push notifications | working (FCM) | **not configured** — no APNs key, no entitlement |
| Google Sign-In | see [Blockers](#blockers) | **not configured** — no iOS OAuth client |
| Endpoints | production (`realtime.chatterloop.app`, `user.chatterloop.app`) | same |

Public store-required pages are live on the webapp:

- Privacy policy — `https://chatterloop.app/privacy`
- Terms — `https://chatterloop.app/terms`
- Account deletion — `https://chatterloop.app/delete-account`
- Support — `https://chatterloop.app/support`

---

## Blockers

### 1. The release SHA-1 is not registered with Firebase — Google Sign-In will fail in production

This is the one that will not show up until real users hit it. Google Sign-In
authenticates the *calling app* by its signing certificate. `android/app/google-services.json`
currently contains **no Android OAuth client with a `certificate_hash`** — only a
web client (`client_type: 3`). Whatever has been working locally has been working
against the debug keystore, and a Play build is not signed with that.

Two fingerprints have to be registered, not one:

- the **upload key** in `android/key.properties` (what this repo now signs with), and
- the **Play App Signing key**, which is a *different* key Play re-signs with after
  upload. Its fingerprint appears in Play Console → *Test and release* → *Setup* →
  *App signing*, and only after the first upload.

Get every locally-configured fingerprint at once. Gradle reads `key.properties`
itself, so nothing prompts for a password:

```bash
cd android && ./gradlew signingReport
```

The release entry should show alias `upload` and
`SHA1: AF:76:FA:55:FD:D1:DB:CA:3E:71:72:D1:A0:96:B4:5E:B3:AF:A3:00`. A different
value means a different keystore is in play — check `key.properties` before
registering anything.

(`keytool -list -v -alias upload -keystore <path>.jks` does the same for the
upload key alone, and will prompt for the store password.)

### Which fingerprints, and when

A fingerprint identifies the **signing key**, not the phone you install on and not
the computer you build on — except that every computer generates its own debug key.
Firebase holds a *list*, so these accumulate; you add, never swap.

| Key | Fingerprint changes when | Register it? |
|---|---|---|
| Debug (`~/.android/debug.keystore`) | Per machine — each dev box/CI runner generates its own | Yes, once per machine that needs Google Sign-In to work in debug |
| Upload (`upload-keystore.jks`) | Never, as long as you keep the same `.jks` | Yes — once |
| Play App Signing | Never; Google generates one per app | Yes, after the first upload |

So: building `--release` on a second machine needs **no** change, provided you copy
the `.jks` and `key.properties` across — same key, same fingerprint. Building
`--debug` there does need that machine's own debug SHA-1 added.

Add both SHA-1 **and** SHA-256 for each, in the
[Firebase console](https://console.firebase.google.com) → Project settings → Your
apps → `com.chatterloop.app`, then **re-download `google-services.json`** into
`android/app/` and rebuild. Skipping the re-download is the usual reason this
appears to be done and still fails with `PlatformException(sign_in_failed, ... 10:)`.
The refreshed file contains every registered fingerprint, so one copy works for
everyone — it is checked in and not machine-specific.

Confirm it landed:

```bash
grep -A 3 certificate_hash android/app/google-services.json
```

Fingerprints appear there lowercase and without colons (`af76fa55fdd1dbca…`).

Verify on a real device with the release build before rolling out, not in debug —
debug uses a different key and will pass regardless. That still does not cover the
Play-signed case; use an internal testing track for that.

### 2. `SECRET_KEY` is recoverable from the binary

[lib/core/configs/keys.dart](lib/core/configs/keys.dart) reads a `--dart-define`,
and [api_client.dart](lib/core/requests/api_client.dart) uses it as a shared
JWT/encryption secret. Dart-defines are compiled in as constants and can be pulled
straight out of the AAB. Per `env.example.json` this is the same value as
`server/.env`'s `JWT_SECRET`, so extracting it means being able to mint tokens the
backend trusts.

This does not block submission — it blocks being safe once submitted. The fix is
server-side (stop treating a client-held secret as proof of anything), so it is a
decision to make deliberately rather than something to patch in the client.

### 3. iOS is not configured for release at all

See [iOS](#ios--app-store). Needs a Mac. Budget real time for Sign in with Apple.

---

## Android → Google Play

### Signing

Already wired. [android/app/build.gradle](android/app/build.gradle) signs release
builds with the upload keystore when `android/key.properties` is present, and
falls back to the debug key with a loud warning when it is not (so other
checkouts still build). Both `key.properties` and `*.jks` are gitignored.

Both branches are verified. With the keystore present the AAB is signed by the
upload key; with `key.properties` absent, Gradle configures successfully and
prints:

```
WARNING: android/key.properties not found - the release build will be signed with the DEBUG key and cannot be uploaded to Play.
```

> **Back up the `.jks` file and its passwords somewhere permanent and off this
> machine.** Losing the upload key means you cannot ship an update under the same
> listing. Enrolling in Play App Signing (offered at first upload — take it)
> makes this recoverable: Google holds the real signing key and you can request
> an upload-key reset.

### Build

```bash
flutter build appbundle --release --dart-define-from-file=env.json
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

An **AAB**, not an APK — Play requires bundles. The APK command in the README is
for sideloading and is still fine for that.

Do a clean build if anything about dependencies or signing changed:

```bash
flutter clean && flutter pub get && flutter build appbundle --release --dart-define-from-file=env.json
```

Verified on this repo: builds in ~166s, producing a **91.1 MB** AAB.

### Confirm it is signed with the upload key, not the debug key

Worth doing once, and again any time signing config changes:

```bash
jarsigner -verify -verbose:summary build/app/outputs/bundle/release/app-release.aab
```

Verified — it currently reports:

```
- Signed by "CN=John Paulo Ramil Guimalan, OU=Neon Systems, O=Neon Systems, L=Quezon City, ST=Metro Manila, C=PH"
  Signature algorithm: SHA256withRSA, 2048-bit key
jar verified.
```

An `Android Debug` CN instead means the fallback took effect and `key.properties`
was not found. The three warnings jarsigner prints alongside this — self-signed
certificate, no timestamp, certificate chain not chaining to a public root — are
all expected for an upload key and are not problems. The key is valid to 2052,
comfortably past Play's requirement that it outlast 2033.

### Test the release build on a real device before uploading

```bash
flutter build apk --release --dart-define-from-file=env.json
flutter install --release
```

Exercise specifically, in `--release` and not `--debug`:

- **Google Sign-In** (see Blocker 1)
- **calls and voice channels** — a vendored `patched/flutter_webrtc` and the
  unmaintained `mediasoup_client_flutter`
- **push notifications** while backgrounded and while force-quit
- **voice messages** (`record`), file picking, media upload

R8/code shrinking is *not* enabled (no `minifyEnabled` anywhere in `android/`), so
reflection-heavy WebRTC code is not being stripped. If you ever turn it on, retest
all of the above first — that is the code most likely to break under it.

### Play Console

Developer account is a one-time $25. A new **personal** account needs 12 testers
running a closed test for 14 days before production access; organisation accounts
do not.

Listing needs:

- App icon 512×512, feature graphic 1024×500, ≥2 phone screenshots
- Short and full description
- **Privacy policy URL** → `https://chatterloop.app/privacy`
- **Data deletion URL** → `https://chatterloop.app/delete-account`
- Content rating questionnaire, target audience declaration

**Data safety form.** Substantial for this app — declare each with purpose,
whether encrypted in transit, and whether deletable: name, email, photos, voice
recordings, video/audio call streams, diary content, location-adjacent map data
if enabled, device identifiers (FCM tokens), and message content.

**Account deletion.** Play requires both an in-app path and a web URL. In-app is
Settings → Data & Privacy → Delete my account
([data_privacy_view.dart](lib/views/settings/data_privacy_view.dart)); the web URL
is above.

---

## iOS → App Store

**Requires a Mac.** Apple Developer Program is $99/yr. There is no `ios/Podfile`
yet — it is generated on the first macOS build.

### Still to configure

1. **Google Sign-In.** [ios/Runner/GoogleService-Info.plist](ios/Runner/GoogleService-Info.plist)
   has `ANDROID_CLIENT_ID` but no `CLIENT_ID`/`REVERSED_CLIENT_ID`, i.e. no iOS
   OAuth client exists. Add an iOS app to the Firebase project (bundle
   `com.chatterloop.app`), re-download the plist, then add to
   [ios/Runner/Info.plist](ios/Runner/Info.plist):

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>com.googleusercontent.apps.YOUR-REVERSED-CLIENT-ID</string></array>
     </dict>
   </array>
   ```

   Keep `serverClientId` in [google_auth_service.dart](lib/core/auth/google_auth_service.dart)
   as the **web** client — the server verifies the token audience against it. The
   iOS client is only for the native flow.

2. **Push notifications.** No `.entitlements` file exists and
   [AppDelegate.swift](ios/Runner/AppDelegate.swift) is stock. In Xcode add the
   *Push Notifications* capability (creates `Runner.entitlements` with
   `aps-environment`) and *Background Modes → Remote notifications*. Then upload an
   **APNs auth key (.p8)** to Firebase → Project settings → Cloud Messaging.
   Without the .p8, iOS pushes silently never arrive.

3. **Sign in with Apple** (guideline 4.8). Offering Google sign-in on iOS
   generally obliges you to offer Apple sign-in too. There is no Apple auth in the
   codebase and it needs a server endpoint as well. This is the largest iOS work
   item — plan for it rather than discovering it at review.

4. **Export compliance.** Each upload asks about encryption. You can answer it once
   in `Info.plist` with `ITSAppUsesNonExemptEncryption`. Deciding which value
   applies is a compliance call — the app uses `crypto`/`cryptography` for JWT
   handling on top of HTTPS — so set it deliberately, not by copying a default.

### Build and upload

```bash
flutter build ipa --release --dart-define-from-file=env.json
```

Upload via Xcode Organizer or `xcrun altool`.

### Expect review friction on

- **User-generated content** (1.2) — needs a content filter, report, block, and a
  published contact. Report and block exist on the profile screen; contact is
  `https://chatterloop.app/support`. Say where they are in the review notes.
- **Privacy nutrition labels** — same content as the Play data safety form.
- **A demo account** in the review notes. Reviewers will not sign up.

---

## Suggested order

1. Register the release SHA-1s with Firebase and re-download `google-services.json` (Blocker 1)
2. Build the AAB, verify the signer, install the release build on a device and test Google Sign-In, calls and push
3. Play internal testing track — dogfood it
4. Data safety form → closed testing → production
5. iOS in parallel, starting with Sign in with Apple

Android is roughly a day of configuration plus testing. iOS is closer to a week
because of Sign in with Apple.
