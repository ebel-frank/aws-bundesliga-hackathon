# Live Prediction Arena

A real-time multiplayer prediction game for Bundesliga matches. Groups of fans compete in timed prediction rounds triggered automatically by live DFL match events.

**Live deployment:** https://main.d3j30xc9rbonry.amplifyapp.com

---

## Architecture

```
Flutter Web App (AWS Amplify)
        │
        ├── REST (Dio)  ──→  API Gateway HTTP  ──→  Lambda  ──→  DynamoDB
        │
        └── WebSocket  ──→  API Gateway WS   ──→  Lambda  ──→  DynamoDB
                                                         └──→  Bedrock (Nova Lite)
                                                         └──→  S3 (DFL event data)
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Flutter | 3.44+ | https://docs.flutter.dev/get-started/install |
| Dart | 3.10+ | bundled with Flutter |
| Node.js | 20+ | https://nodejs.org |
| AWS CLI | v2 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| AWS SAM CLI | latest | `pip install aws-sam-cli` |

---

## Account-Specific Values — Read This First

> ⚠️ The following values are hardcoded to the original deployment account. Every one of them **must be updated** when running on a different AWS account or with a different Amplify app.

### 1. `backend/samconfig.toml`

```toml
[default.deploy.parameters]
stack_name = "arena-app"      # ← rename if you want a different stack
region = "us-east-1"          # ← change to your target region
```

### 2. `backend/template.yaml` — SAM template parameters

```yaml
Parameters:
  DflDataBucketName:
    Default: hackathon-data-686384344354   # ← your S3 bucket containing the DFL XML data
  DflDataBucketRegion:
    Default: eu-central-1                  # ← region of that S3 bucket
  DflEventsKey:
    Default: "Challenge 3 – ..."           # ← S3 key to the Events_Anonym.xml file
  DflMatchInfoKey:
    Default: "Challenge 3 – ..."           # ← S3 key to the MatchInformations_Anonym.xml file
```

You can override these at deploy time without editing the file:
```bash
sam deploy \
  --parameter-overrides \
    DflDataBucketName=your-bucket-name \
    DflDataBucketRegion=eu-central-1 \
  --no-confirm-changeset \
  --profile YOUR_PROFILE \
  --region us-east-1
```

### 3. `lib/services/api_service.dart`

```dart
static const String baseUrl =
    'https://mxp17lrhe7.execute-api.us-east-1.amazonaws.com/prod';
// ↑ Replace with the RestApiUrl output from `sam deploy`
```

### 4. `lib/services/websocket_service.dart`

```dart
static const String wsUrl =
    'wss://6a4wu4973a.execute-api.us-east-1.amazonaws.com/prod';
// ↑ Replace with the WebSocketUrl output from `sam deploy`
```

### 5. `lib/services/auth_service.dart`

```dart
static const String userPoolId = 'us-east-1_abgV4lc4K';
// ↑ Replace with the CognitoUserPoolId output from `sam deploy`

static const String clientId = '52tl33c9nbkcjq2n7tf283te2r';
// ↑ Replace with the CognitoClientId output from `sam deploy`

static const String region = 'us-east-1';
// ↑ Match your deployment region
```

### 6. Amplify app ID and hosted URL

The Amplify app ID `d3j30xc9rbonry` and hosted URL `https://main.d3j30xc9rbonry.amplifyapp.com` are specific to the original account. When deploying to a new account, create a new Amplify app (see Frontend Deploy below) and substitute your app ID and URL throughout.

---

## 1. Clone & Configure

```bash
git clone https://github.com/ebel-frank/aws-bundesliga-hackathon.git
cd aws-bundesliga-hackathon
git checkout v2
```

---

## 2. Configure AWS Credentials

The project uses an AWS SSO profile. Configure yours:

```bash
# Option A — SSO (recommended for hackathon accounts)
aws configure sso --profile YOUR_PROFILE_NAME
aws sso login --profile YOUR_PROFILE_NAME

# Option B — static credentials
aws configure --profile YOUR_PROFILE_NAME
```

Verify access:
```bash
aws sts get-caller-identity --profile YOUR_PROFILE_NAME
```

---

## 3. Deploy the Backend (AWS SAM)

```bash
cd backend

# Install Lambda dependencies
cd functions && npm install && cd ..

# Build
sam build

# First-time deploy (interactive — sets stack name, region, etc.)
sam deploy --guided --profile YOUR_PROFILE_NAME

# Subsequent deploys (non-interactive)
sam deploy --no-confirm-changeset --profile YOUR_PROFILE_NAME --region us-east-1
```

After deploy, SAM prints the stack outputs. Copy these values into the Flutter services:

```
RestApiUrl       → lib/services/api_service.dart       → baseUrl
WebSocketUrl     → lib/services/websocket_service.dart → wsUrl
CognitoUserPoolId → lib/services/auth_service.dart     → userPoolId
CognitoClientId   → lib/services/auth_service.dart     → clientId
```

---

## 4. Seed Match Data

Populate DynamoDB with the Bundesliga match fixture:

```bash
cd backend
npm install          # installs @aws-sdk deps for the seed script
node seed.mjs
```

> Requires the `AWS_PROFILE` env var or default credentials. To use a named profile:
> ```bash
> AWS_PROFILE=YOUR_PROFILE_NAME node seed.mjs
> ```

---

## 5. Build the Flutter Web App

```bash
# From the repo root
flutter pub get
flutter build web --release
# Output is in build/web/
```

---

## 6. Deploy the Frontend to AWS Amplify

### First-time setup — create the Amplify app

```bash
# Create a new manual-deploy Amplify app
aws amplify create-app \
  --name arena-app \
  --platform WEB \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1

# Note the appId from the response, then create a branch
aws amplify create-branch \
  --app-id YOUR_APP_ID \
  --branch-name main \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1
```

### Deploy (first time and every subsequent update)

```bash
# 1. Zip the build output
cd build/web && zip -r -q /tmp/arena-web-deploy.zip . && cd -

# 2. Create a deployment and capture the upload URL + job ID
DEPLOY=$(aws amplify create-deployment \
  --app-id YOUR_APP_ID \
  --branch-name main \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1 \
  --output json)

JOB_ID=$(echo $DEPLOY | python3 -c "import sys,json; print(json.load(sys.stdin)['jobId'])")
UPLOAD_URL=$(echo $DEPLOY | python3 -c "import sys,json; print(json.load(sys.stdin)['zipUploadUrl'])")

# 3. Upload the zip
curl -T /tmp/arena-web-deploy.zip "$UPLOAD_URL"

# 4. Start the deployment
aws amplify start-deployment \
  --app-id YOUR_APP_ID \
  --branch-name main \
  --job-id $JOB_ID \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1

# 5. Check status (repeat until SUCCEED or FAILED)
aws amplify get-job \
  --app-id YOUR_APP_ID \
  --branch-name main \
  --job-id $JOB_ID \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1 \
  --query "job.summary.status" \
  --output text

# 6. Clean up
rm -f /tmp/arena-web-deploy.zip
```

Your app will be live at:
```
https://main.YOUR_APP_ID.amplifyapp.com
```

---

## 7. Replay a Match (Trigger Live Events)

Once users are in a room and the host has started the match, events stream automatically via the WebSocket `game_started` action. To replay a match manually from the CLI:

```bash
cd backend
node trigger-dfl-events.mjs \
  "YOUR_DFL_DATA_BUCKET" \
  "Challenge 3 – A Real Time Social Match Experience/data/Match-Events/Events_Anonym.xml" \
  DFL-MAT-000001 \
  --match-info "Challenge 3 – A Real Time Social Match Experience/data/Match-Events/MatchInformations_Anonym.xml" \
  --room YOUR_ROOM_CODE \
  --delay 3000
```

> **Account-specific:** replace `YOUR_DFL_DATA_BUCKET` with the S3 bucket name in your account that holds the DFL data files (defaults to `hackathon-data-686384344354` in the original deployment).

To reset a match and replay from the beginning:

```bash
aws lambda invoke \
  --function-name arena-app-QuestionTriggerFunction-XXXX \
  --cli-binary-format raw-in-base64-out \
  --payload '{"reset":true,"matchId":"DFL-MAT-000001"}' \
  /dev/null \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1
```

> Replace `arena-app-QuestionTriggerFunction-XXXX` with the actual function name from the SAM stack outputs (`QuestionTriggerFunctionName`).

---

## Full Redeploy Checklist (after a code change)

```bash
# Pull latest
git pull --ff-only origin v2

# Build both in parallel (run in separate terminals or with &)
flutter build web --release &
(cd backend/functions && npm install --silent && cd .. && sam build)
wait

# Deploy backend (only needed if backend files changed)
cd backend && sam deploy --no-confirm-changeset --profile YOUR_PROFILE_NAME --region us-east-1

# Deploy frontend (always)
cd build/web && zip -r -q /tmp/arena-web-deploy.zip . && cd -
# ... (follow steps 2–6 in section 6 above)
```

---

## DynamoDB Tables

| Table | Key | Description |
|---|---|---|
| `lpa-matches` | `matchId` (PK) | Match fixtures |
| `lpa-rooms` | `roomCode` (PK) | Squad rooms |
| `lpa-rounds` | `matchId` (PK) + `roundNumber` (SK) | Prediction rounds |
| `lpa-connections` | `connectionId` (PK) | Active WebSocket connections |
| `lpa-match-state` | `matchId` (PK) | Rolling event buffer + match flags |
| `lpa-questions` | `matchId` (PK) + `questionId` (SK) | Generated questions + picks + scores |

---

## REST API Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/matches` | List matches (optional `?status=upcoming`) |
| GET | `/matches/{matchId}/rooms` | List rooms for a match |
| POST | `/rooms` | Create a room |
| POST | `/rooms/join/{roomCode}` | Join a room |
| GET | `/rounds/{matchId}` | Get rounds for a match |

## WebSocket Actions

| Action | Direction | Description |
|---|---|---|
| `player_joined` | broadcast | A player joined the room |
| `game_started` | broadcast | Host started the match stream |
| `pick_locked` | broadcast | A player locked in their answer |
| `prediction_question` | server → client | New question pushed to all players |
| `questions_resolved` | server → client | Round results + leaderboard update |
| `ping` / `pong` | client ↔ server | Heartbeat (keeps connection alive) |

---

## Troubleshooting

**SSO token expired**
```bash
aws sso login --profile YOUR_PROFILE_NAME
```

**SAM deploy says "No changes to deploy"**
Backend is already up to date. Only the Flutter frontend needs redeploying.

**Amplify deploy stuck in PENDING**
A previous abandoned deployment may be blocking. Cancel it first:
```bash
aws amplify stop-job \
  --app-id YOUR_APP_ID \
  --branch-name main \
  --job-id STUCK_JOB_ID \
  --profile YOUR_PROFILE_NAME \
  --region us-east-1
```

**Flutter build fails with "pub get" errors**
```bash
flutter pub get
flutter clean
flutter build web --release
```

**Questions not generating during a match**
Check that Bedrock model access is enabled in your account for `amazon.nova-lite-v1:0` in `us-east-1`. Enable it at: AWS Console → Bedrock → Model Access.
