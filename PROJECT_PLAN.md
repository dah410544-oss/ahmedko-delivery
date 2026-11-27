
# AHMEDKO DELIVERY
## Complete Logistics Management System

### Project Vision
Build a professional logistics platform
for Ahmedko Delivery.

### Main Interfaces
1. Customer Application
2. Driver Application
3. Office Admin Dashboard

### Core Features
- Customer orders
- Driver management
- Order tracking
- Restaurant and store management
- Financial management
- Distance-based delivery fees
- Driver earnings by vehicle type

### Design
- Arabic RTL
- Navy Blue
- Yellow
- White
- Responsive mobile-first interface

### Technology Plan
- Capacitor 8 + Android (current implementation; WebView-based app shell)
- Responsive Arabic RTL web application (customer, driver, restaurant and admin pages)
- Supabase (database, authentication and protected RPC workflows)
- GitHub Actions + GitHub Pages (web deployment)
- Android APK/AAB build workflow (requires the existing signing keystore secrets)
- Firebase Cloud Messaging planned for native Android push (Firebase project and google-services.json still required)
- Supabase Edge Functions planned for secure notification dispatch

### Repository
dah410544-oss/ahmedko-delivery

### Development
Build step by step.
Test every feature before release.

### Delivery and commission policy
- Current office commission setting remains 16% in business_settings.
- Future commission changes must be made through an admin-only settings control and must never be hard-coded into customer or driver UI.
- Preserve the current commission until the owner explicitly authorizes a change.

### Wallet rollout
- Customer wallet account and ILS ledger.
- Top-up request methods: PalPay, Jawwal Pay and Bank of Palestine.
- Manual transfer matching and admin approval before crediting any balance.
- Never store card PINs, OTPs, passwords or wallet credentials.
- Payment destination details must be verified by the owner before being shown to customers.
- Later phase: integrate provider-approved payment APIs only after merchant onboarding and credentials are available.

### Release roadmap
1. Fix and verify restaurant/product search on live data.
2. Apply and test wallet SQL migration in Supabase after a backup.
3. Configure phone OTP provider and verify login.
4. Test wallet top-up request, admin approval, rejection, ledger and balance integrity.
5. Regression-test customer orders, restaurant menus, driver workflow, tracking and office finance.
6. Prepare signed Android APK/AAB using the existing persistent signing key.
7. Create and validate an iOS project/build on macOS, then TestFlight testing.
8. Complete store privacy disclosures, screenshots, listing text, support contact and review credentials before submission.

### Store account fees (verify at enrollment)
- Google Play full-distribution developer registration: one-time USD 25.
- Apple Developer Program: USD 99 per year.
- New personal Google Play developer accounts created after 2023-11-13 may need a closed test with 12 opted-in testers for 14 continuous days before production access.
