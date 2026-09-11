# LiveStar Backend v0.8

Node.js + Express + PostgreSQL API for the LiveStar prototype.

## v0.8 additions
- Live room creation/listing (`/rooms`)
- Gift catalog (`/gifts`)
- Atomic gift sending from a user to a host inside a live room (`/rooms/:roomId/gifts`)
- Gift and transfer events recorded in PostgreSQL
- Server-side coin validation and transaction records

## Run
1. Copy `.env.example` to `.env` and set `JWT_SECRET`.
2. `docker compose up -d`
3. `npm install`
4. Apply `src/schema.sql` to PostgreSQL.
5. `npm start`

WebRTC/media streaming is intentionally not implemented by these REST endpoints; production live video/audio should use a dedicated WebRTC/SFU provider or infrastructure.


## Coin packages update
The package system now supports packages from **30,000 coins up to 1,000,000,000 coins**.
The established conversion remains 7,500 coins per USD, with the billion-coin tier represented as a high-value package.
The production backend must validate price, package ID, payment confirmation, and coin grant atomically.
