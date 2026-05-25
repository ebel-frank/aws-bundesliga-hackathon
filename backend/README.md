# Live Prediction Arena — AWS Backend

## Architecture

```
Flutter App
    ├── REST API (Dio) ──→ API Gateway HTTP ──→ Lambda ──→ DynamoDB
    └── WebSocket ──────→ API Gateway WS ───→ Lambda ──→ DynamoDB + Broadcast
```

## Prerequisites

- AWS CLI configured (`aws configure`)
- SAM CLI installed (`pip install aws-sam-cli`)
- Node.js 20+

## Deploy

```bash
cd backend

# Install Lambda dependencies
cd functions && npm install && cd ..

# Build and deploy
sam build
sam deploy --guided
```

On first deploy, SAM will ask for:
- Stack name: `lpa-backend`
- Region: `us-east-1`
- Confirm changes: Yes
- Allow SAM CLI IAM role creation: Yes

## Seed Data

After deployment, seed the DynamoDB tables with sample matches and rounds:

```bash
cd backend
node seed.mjs
```

## Get Your API URLs

After deployment, SAM outputs:
- `RestApiUrl` — use this in `lib/services/api_service.dart`
- `WebSocketUrl` — use this in `lib/services/websocket_service.dart`

Update the `baseUrl` and `wsUrl` constants in those files.

## DynamoDB Tables

| Table | Key | Description |
|-------|-----|-------------|
| lpa-matches | matchId (PK) | Football matches |
| lpa-rooms | roomCode (PK) | Game rooms/squads |
| lpa-rounds | matchId (PK) + roundNumber (SK) | Prediction questions |
| lpa-connections | connectionId (PK) | WebSocket connections |

## API Endpoints

### REST

| Method | Path | Description |
|--------|------|-------------|
| GET | /matches | List all matches (optional ?status=upcoming) |
| GET | /rooms/{matchId} | List rooms for a match |
| POST | /rooms | Create a room |
| POST | /rooms/{roomCode}/join | Join a room |
| GET | /rounds/{matchId} | Get prediction rounds for a match |

### WebSocket

| Action | Direction | Description |
|--------|-----------|-------------|
| player_joined | broadcast | A player joined the room |
| game_started | broadcast | Host started the game |
| pick_locked | broadcast | A player locked in their answer |

## Local Testing

```bash
sam local start-api
```

This starts a local API at `http://localhost:3000`.
