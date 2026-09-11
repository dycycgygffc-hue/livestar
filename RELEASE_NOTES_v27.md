# LiveStar v2.7.0 Release Hardening

- Release version: 2.7.0+27
- Added `/ready` readiness endpoint.
- Added OTP verification input validation and per-IP verification throttling.
- Added centralized JSON error handling without leaking stack traces.
- Added GitHub Actions Android AAB build using repository secrets.
- Added production environment validation script.
- Backend health version synchronized with app release.

## Still required before store submission
- Real SMS provider and verified sender.
- Real payment gateway merchant accounts/webhooks/signature verification.
- Production LiveKit deployment, TLS, TURN/network configuration and monitoring.
- Android/iOS signing credentials and store accounts.
- Privacy policy, terms, moderation/reporting process, age/content compliance.
