# Getting Loop onto an iPhone with TestFlight

This guide assumes you have never shipped an iOS app. You need a paid Apple Developer Program membership (US$99/year) and the GitHub CLI (`gh`) logged in. No Mac is required: GitHub builds and uploads the app for you.

Replace `<prefix>` below with the identifier prefix you choose in step 1.

## 1. Choose a prefix

Pick a reverse-DNS prefix that is unique to you, for example `com.<yourname>.loop`. It must be lowercase letters, digits, dots and hyphens. The identifiers derived from it are:

- App Group: `group.<prefix>`
- App: `<prefix>.app`
- Widget extension: `<prefix>.app.widgets`

Example with prefix `com.jane.loop`: `group.com.jane.loop`, `com.jane.loop.app`, `com.jane.loop.app.widgets`.

## 2. Register the App Group

1. Go to https://developer.apple.com/account and sign in.
2. Certificates, IDs & Profiles -> Identifiers -> click the blue **+**.
3. Choose **App Groups** -> Continue.
4. Description: `Loop`. Identifier: `group.<prefix>`. Continue -> Register.

## 3. Register the two App IDs

Automatic signing can create these itself, but doing it explicitly avoids first-run failures. Do this twice, once per ID.

1. Certificates, IDs & Profiles -> Identifiers -> **+** -> **App IDs** -> Continue -> **App** -> Continue.
2. Description `Loop` and Bundle ID type **Explicit**, with `<prefix>.app`. (Second time: description `Loop Widgets`, Bundle ID `<prefix>.app.widgets`.)
3. In Capabilities tick **App Groups**. Click **Configure** (shown next to it) and select `group.<prefix>`. Save.
4. Continue -> Register.

Push Notifications is NOT needed. Loop only uses local notifications.

## 3b. Register at least one device

Automatic signing on a team with zero registered devices can fail with "Your team has no devices from which to generate a provisioning profile". Register one device (name plus UDID is enough) before the first run:

1. Find the iPhone's UDID. Easiest: connect it to a Mac, open Finder, select the iPhone in the sidebar, and click the grey text under its name (storage/battery line) until it shows the **UDID**, then right-click -> Copy. On Windows, open iTunes or the Apple Devices app, select the phone, and click the serial number line until it shows UDID. Alternatively, use Apple Configurator on a Mac (select the device -> Get Info).
2. developer.apple.com -> Certificates, IDs & Profiles -> **Devices** -> **+**.
3. Platform iOS, any Device Name (e.g. My iPhone), paste the UDID. Continue -> Register.

TestFlight testers do not need to be registered devices; this only satisfies the signing tool.
## 4. Create the App Store Connect app record

1. Go to https://appstoreconnect.apple.com -> **Apps** (My Apps) -> **+** -> **New App**.
2. Platforms: **iOS**. Name: anything, e.g. `Loop (personal)` (must be unique across the App Store, so add something of your own if it is taken). Primary language: English.
3. Bundle ID: choose `<prefix>.app` from the dropdown (it only appears after step 3). SKU: anything, e.g. `loop-personal`. User Access: Full Access.
4. Create.

## 5. Create an App Store Connect API key

1. App Store Connect -> **Users and Access** -> **Integrations** tab -> **App Store Connect API** -> Team Keys.
2. Click **+** (Generate API Key). Name `GitHub CI`. Access: **App Manager**. Generate.
3. Note the **Issuer ID** (top of the page) and the **Key ID** (in the table row).
4. Click **Download API Key**. You get `AuthKey_XXXXXXXXXX.p8`. **It can only be downloaded once.** Keep it safe, and never commit it.

Find your **Team ID** at https://developer.apple.com/account -> Membership details -> Team ID (10 characters).

## 6. Store the secrets and variables in GitHub

Run these from any terminal where `gh` is logged in. Each `gh secret set` without `--body` prompts you to paste the value.

```
gh secret set ASC_KEY_ID -R ROODAY/uhabits
gh secret set ASC_ISSUER_ID -R ROODAY/uhabits
gh secret set APPLE_TEAM_ID -R ROODAY/uhabits
```

The key file is stored base64-encoded.

Linux / Git Bash:

```
base64 -w0 AuthKey_XXXX.p8 | gh secret set ASC_KEY_P8 -R ROODAY/uhabits
```

macOS (its base64 has no -w0):

```
base64 -i AuthKey_XXXX.p8 | tr -d '\n' | gh secret set ASC_KEY_P8 -R ROODAY/uhabits
```

PowerShell:

```
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8")) | gh secret set ASC_KEY_P8 -R ROODAY/uhabits
```

Then the two (non-secret) variables, using your own prefix:

```
gh variable set LOOP_BUNDLE_PREFIX --body com.x.loop -R ROODAY/uhabits
gh variable set LOOP_APP_GROUP --body group.com.x.loop -R ROODAY/uhabits
```

Check with `gh secret list -R ROODAY/uhabits` and `gh variable list -R ROODAY/uhabits`.

## 7. Add the tester

Internal testers must first be **users of your App Store Connect team**. This is the most common stumbling block.

1. App Store Connect -> **Users and Access** -> **Users** -> **+**.
2. Enter your tester's name and the email of their Apple ID. Role: **Marketing** or **Customer Support** (these have no real power). Under apps, you can restrict access to Loop. Invite.
3. Your tester accepts the invitation email (it must be opened with that Apple ID).
4. App Store Connect -> your app -> **TestFlight** -> **Internal Testing** -> **+** next to "Internal Testing" -> create a group (e.g. `Family`), enable automatic distribution of builds if offered, and add your tester from the list. (You can add yourself too.)

## 8. Run the build

The workflow runs when you push a tag starting with `ios-v` (this works from any branch). Use a new tag each time:

```
git tag ios-v1
git push origin ios-v1
gh run watch -R ROODAY/uhabits
```

For later builds use `ios-v2`, `ios-v3`, and so on. After this branch is merged to `dev`, you can also run `gh workflow run testflight.yml -R ROODAY/uhabits`.

The build takes about 15-25 minutes on GitHub (the Kotlin framework is the slow part). After the upload succeeds, App Store Connect "processes" the build for roughly 5-15 minutes before it appears in TestFlight, and the testers get a notification.

TestFlight builds expire after 90 days. Push a new tag to refresh.

## 9. On the tester's phone

1. Install **TestFlight** from the App Store and open the invitation (email, or the TestFlight app itself) with their Apple ID. Accept it.
2. Install **Loop** from TestFlight, open it once, and tap **Allow** for notifications.
3. Add the widget: long-press an empty spot on the Home Screen -> **+** (top left) -> search **Loop** -> **Habit check-off** -> Add Widget.
4. Long-press the widget -> **Edit Widget** -> choose a habit.
5. Tap the widget's checkmark to check the habit off.

## 10. Troubleshooting

- **"No signing certificate" / "No profiles for ... were found"**: automatic signing needs the API key to have the **App Manager** role (lower roles cannot create certificates). The first run creates the distribution certificate and profiles. Check that `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and the base64 `ASC_KEY_P8` are right. Apple limits the number of distribution certificates; if you hit the limit, revoke an unused one at developer.apple.com -> Certificates.
- **Missing or invalid icon** (`Missing required icon file`, or an alpha-channel error): the repo ships a 1024x1024 opaque icon at `ios/App/Assets.xcassets/AppIcon.appiconset`. If you replace it, keep it 1024x1024 with no transparency.
- **Bundle ID mismatch** (`No app record found` / `bundle identifier ... does not match`): the `LOOP_BUNDLE_PREFIX` variable must equal the prefix used for the App Store Connect app record's bundle ID (`<prefix>.app`), and the App Group must be `group.<prefix>`. Fix the variable and re-run with a new tag.
- **"Your team has no devices from which to generate a provisioning profile"**: register at least one device (step 3b), then re-run with a new tag.
- **App Group errors**: both App IDs (`.app` and `.app.widgets`) need the App Groups capability configured with `group.<prefix>` (step 3).
- **"The bundle version must be higher than the previously uploaded version"**: the build number is the GitHub run number, so it always grows. This only happens if you re-uploaded the same run. Push a new tag (a fresh run).
- **Empty secret/variable error** at the start of the run: the first step names whichever is missing; set it per step 6.
- **Build never appears in TestFlight**: wait 15 minutes, then check App Store Connect -> your app -> TestFlight for a processing error email.
