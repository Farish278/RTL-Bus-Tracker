# Android release signing

Starting with 1.1.1 (build 3), release APKs use one persistent RSA release key. The public certificate SHA-256 fingerprint is recorded in `android/release-certificate.sha256`. The workflow checks every APK against that fingerprint before attaching it to a release.

## Existing installations

The 1.0.0 and 1.1.0 GitHub builds used separate temporary debug keys. Their private keys were not preserved, so the new release key cannot update those installations. Users must uninstall once and install 1.1.1, losing local app preferences, alerts, and cache. Keep using the permanent key for all subsequent releases so users can update without uninstalling.

## GitHub Actions

The repository has four Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: the base64-encoded permanent keystore.
- `ANDROID_KEYSTORE_PASSWORD`: the keystore password.
- `ANDROID_KEY_ALIAS`: the signing alias.
- `ANDROID_KEY_PASSWORD`: the private-key password.

The release workflow restores `android/release-keystore.jks` and `android/key.properties`, builds the APK, verifies its signature and public certificate fingerprint, and uploads it. It removes the restored signing files even if a step fails. Missing secrets or a mismatched certificate fail the workflow.

Do not regenerate the key for each release or replace these secrets with a new key. A different key would break the update path again. Increase the app version and build number for each published update.

## Local builds and backup

The permanent keystore is saved locally as `android/release-keystore.jks`. Its alias and passwords are saved in `android/key.properties`. Both files are ignored by Git. Preserve a secure backup of both files outside the checkout: GitHub Actions secrets cannot be downloaded again through the CLI.

For an authorized developer with a copy of the same keystore, the properties file has this structure (replace the placeholders):

```properties
storeFile=release-keystore.jks
storePassword=YOUR_KEYSTORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`storeFile` is resolved relative to `android/`. Build with `flutter build apk --release`. Release builds fail if signing configuration is missing; they do not fall back to a temporary debug key. Debug builds continue to use the standard local debug identity.

The keystore and passwords must never be committed, added to release assets, or written into logs. The fingerprint file is public certificate information and is safe to commit.
