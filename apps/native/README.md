# MINE-ME Native App

Flutter application source for Android and desktop (Windows, macOS and Linux).

## Current implementation

- Supabase member sign-in with the Supabase session persisted in platform secure storage.
- Member profile, referral code, enrolled devices and internal XMR reward balance.
- One central HashVault wallet for the whole platform. Members and devices do not have individual pool wallets; member balances are internal ledger credits.
- Device-bound short-lived server-signed gateway sessions. The app never receives the service-role key, gateway signing secret, or any wallet private key.
- Native RandomX C API bridge, built from upstream RandomX v1.2.1. Desktop requests the full dataset mode; Android uses light mode by default to avoid reserving about 2.1 GiB of RAM.
- Native worker runs in a dedicated Dart isolate and submits candidate shares only through the authenticated MINE-ME gateway.
- Android mining sessions require a visible foreground notification, wake lock and explicit user action. No auto-start on boot.
- Per-device start, pause and stop controls; pause/stop are committed by the gateway to the device record.

Mining remains subject to the server-side `mining_enabled` flag, emergency pause, member consent, account status, device authorization and the 200-device platform cap. The development branch does not activate production mining or deploy migrations.

The reward ledger only credits confirmed central-wallet payouts. Distribution is calculated from accepted-share difficulty recorded by the trusted gateway in an explicitly reconciled contribution window. Client-reported hashrate is diagnostic only and never creates earnings.

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
flutter build apk --release --target-platform android-arm64 --dart-define=MINE_ME_SUPABASE_URL=https://mqyqpflamkplhlphrngn.supabase.co --dart-define=MINE_ME_SUPABASE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
flutter build windows --release
flutter build linux --release
flutter build macos --release
```

Builds require their platform toolchains and are not produced by this source-only commit.


## Installers produced by CI

The native build workflow publishes these installable packages after all tests pass:

- Android: arm64 APK for direct sideloading.
- Windows: x64 Setup executable generated with Inno Setup.
- Linux: amd64 Debian package (`.deb`).
- macOS: disk image (`.dmg`) containing the application bundle.

CI artifacts are retained for 30 days. Windows and macOS packages are currently unsigned; macOS is not notarized, so the operating system may show an installation warning. Android installation is direct APK sideloading and is not distributed through Google Play.

## Central wallet rule

There is exactly one platform-owned HashVault Monero wallet address. Every member and device contributes through the same pool proxy and the same receiving address. Member XMR amounts are internal accounting credits from verified accepted-share contribution windows and confirmed central-wallet payouts. No member-specific HashVault wallet is created, and no wallet private key is embedded in the application.
