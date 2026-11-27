# AHMEDKO — payment provider activation runbook

This is a preparation scaffold, not a live payment integration. No provider has approved the merchant account or supplied production API credentials yet.

## Providers tracked independently
- Jawwal Pay: disabled until written merchant approval, checkout/API documentation, webhook/signature specification, settlement terms, and test credentials are received.
- PalPay: disabled until the same items are received.
- Bank of Palestine: disabled until Automatic Payment Services approval and technical integration details are received.

## Architecture prepared
1. Customer starts checkout from the app. The browser must call an authenticated server endpoint; it must never create a paid transaction or set wallet balance.
2. Server creates a pending `payment_attempts` row with a unique idempotency key and amount/currency fixed by the server.
3. Server asks the approved provider to create a hosted checkout session and returns only the provider's checkout URL.
4. Provider sends a server-to-server webhook. The server verifies the signature using the provider's documented algorithm and secret stored in Supabase Vault / server environment. Never trust the browser redirect as proof of payment.
5. Server records a deduplicated webhook event and calls `wallet_confirm_gateway_topup` only after signature, merchant, transaction, amount, currency, and status checks pass.
6. The SQL function locks the attempt, checks the expected amount/currency and pending state, and credits a wallet top-up once. Replayed callbacks cannot credit twice.
7. Order payments need a separate settlement routine that checks the actual Ahmedko order total and updates the existing order status atomically. Do not infer or invent the orders schema.

## Before applying the migration
- Back up the Supabase database.
- Review current RLS, `is_admin()`, existing wallet schema, and grants.
- Confirm Supabase project environment and test on a staging project first.
- Apply `supabase/payment_gateway_readiness.sql` only after review.
- Keep all provider flags false until approval and end-to-end sandbox tests pass.

## Provider activation checklist
For each provider separately obtain:
- Written approval for Ahmedko's legal/merchant status and settlement bank account.
- Merchant ID / terminal ID and sandbox credentials.
- Hosted checkout or API specification.
- Webhook URL registration and signature verification specification.
- Supported currencies, refund/void flow, settlement timing, fees, and dispute process.
- Test cards/accounts and successful, failed, cancelled, expired, duplicate-webhook scenarios.

## Current limitations
- No provider API is connected.
- No webhook endpoint is deployed.
- No production secrets are configured.
- No payment is automatically confirmed.
- Existing manual top-up review remains a separate workflow and must not be represented as automatic checkout.
