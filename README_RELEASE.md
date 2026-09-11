# LiveStar Release Candidate v2.7

This package is prepared as a source release candidate. The current environment does not include Flutter/Android SDK/Xcode, so no APK/IPA was built here.

## First machine with Flutter

```bash
./tool/bootstrap_platforms.sh
./tool/preflight_release.sh
```

Then configure signing and build:

```bash
flutter build appbundle --release --dart-define=API_URL=https://api.YOUR-DOMAIN.example
flutter build ipa --release --dart-define=API_URL=https://api.YOUR-DOMAIN.example
```

See `RELEASE_BUILD.md`, `docs/STORE_METADATA_TEMPLATE.md`, and `docs/PRODUCTION_SECRETS.md`.
