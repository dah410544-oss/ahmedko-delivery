# AHMEDKO Native Android foundation

This is a separate native Android (Kotlin + Jetpack Compose) application foundation.
It intentionally does not replace the current production website or Capacitor app.

## Current milestone
- Native Android entry activity and Compose navigation.
- Native starter screens for Home, Orders, Wallet, and Account.
- Wallet is explicitly marked unavailable; no demo balance, payment, or deduction is implemented.
- No Supabase credentials or secrets are stored in this project.

## Not yet production-ready
Authentication/OTP, live restaurant catalog, cart checkout, order creation, driver/store/admin roles,
ledger-backed wallet, payment reconciliation, push notifications, and end-to-end tests remain to be
implemented and verified before distribution.

## Build
Run from this directory with Gradle 8.11.1 and JDK 21:
`gradle :app:assembleDebug`

The Android application ID remains `com.ahmedko.delivery`. Do not distribute a release build
until its signing identity has been verified against the existing installed application.
