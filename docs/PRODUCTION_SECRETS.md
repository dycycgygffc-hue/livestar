# Production Secrets

Never commit any of these values:

- backend/.env
- JWT_SECRET
- DATABASE_URL credentials
- LIVEKIT_API_KEY / LIVEKIT_API_SECRET
- Android keystore and passwords
- iOS certificates/profiles/API keys
- SMS provider credentials
- Payment provider secrets/webhook signing secrets

Use the CI secret store or a cloud secret manager. Rotate credentials if they are ever exposed in logs, source control, or chat.
