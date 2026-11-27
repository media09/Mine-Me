# MINE-ME Native App

Flutter application source for Android and desktop (Windows, macOS and Linux).

## Current milestone

This initial native shell provides Supabase email/password sign-in, secure Supabase session persistence through the Supabase Flutter SDK, member profile display, device enrollment and referral-code display. It intentionally does **not** start RandomX or connect to the pool. Native mining must remain disabled until the native engine, gateway protocol, Android foreground service, desktop lifecycle controls and end-to-end accounting tests are complete.

## Build prerequisites

- Flutter stable with Android, Windows, macOS and/or Linux toolchains enabled.
- Android SDK/NDK for Android builds.
- Desktop native build toolchain for the selected host OS.

## Run

```sh
cd apps/native
flutter pub get
flutter run --dart-define=MINE_ME_SUPABASE_URL=https://mqyqpflamkplhlphrngn.supabase.co --dart-define=MINE_ME_SUPABASE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Use the same public publishable key as the web client. Never put a service-role key, gateway signing secret, wallet private key or pool credential in this app.

## Installable builds

```sh
flutter build apk --release --dart-define=MINE_ME_SUPABASE_URL=https://mqyqpflamkplhlphrngn.supabase.co --dart-define=MINE_ME_SUPABASE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
flutter build windows --release
flutter build linux --release
flutter build macos --release
```

Builds require their platform toolchains and are not produced by this source-only commit.
