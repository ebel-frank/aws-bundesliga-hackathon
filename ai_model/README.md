# Live Prediction Arena AI Service

Bedrock-backed AI service for the Fan Squad Challenge 3 prototype.

This folder is the AI part your teammates can call from the game engine. It generates Kahoot-style multiple-choice prediction rounds, VAR prediction rounds, normalizes DFL-style event XML, and scores submitted answers.

There is no fallback content generator. Round generation calls Amazon Bedrock through the Converse API. If AWS credentials, region, or model access are not configured, the generation endpoints return an error.

## Main Endpoints

- `GET /health`
- `POST /ai/prediction-rounds`
- `POST /ai/trivia-rounds` as a compatibility alias for prediction rounds
- `POST /ai/var-rounds`
- `POST /ai/events/normalize`
- `POST /ai/score-rounds`
- `POST /ai` for Lambda-style action routing

Full request and response examples are in [API_DOCUMENTATION.md](API_DOCUMENTATION.md).

## Bedrock Setup

Set the model and region in the deployment environment:

```powershell
$env:AWS_REGION="us-east-1"
$env:BEDROCK_MODEL_ID="amazon.nova-lite-v1:0"
```

Use any model ID enabled in the hackathon AWS account. The code uses Bedrock Converse, so Claude-family and Nova-family chat models can be swapped by changing `BEDROCK_MODEL_ID`.

## Local Development

Install dependencies:

```powershell
cd ai_part
python -m pip install -r requirements.txt
```

Run the API:

```powershell
python -m uvicorn app:app --reload --port 8000
```

Run tests:

```powershell
python -m unittest discover -s tests
```

The tests mock the Bedrock client. They do not generate local fallback content for the production service.

## Lambda Integration

Handler path:

```text
ai_core.lambda_handler.handler
```

The Lambda handler accepts the same payloads as the HTTP API plus an `action` field:

- `generate_prediction_round`
- `generate_trivia_round` as a compatibility alias
- `generate_var_prediction_round`
- `normalize_event`
- `score_round`

## Integration Flow

1. Event replay service emits a DFL `<Event>` XML snippet.
2. Game backend calls `POST /ai/events/normalize`, or sends `event_xml` directly to a generation endpoint.
3. For normal match moments or longer-horizon prompts, call `POST /ai/prediction-rounds`.
4. For VAR checks, call `POST /ai/var-rounds`. Offside checks return `status: skipped`.
5. Backend broadcasts the generated round to all users in the room.
6. Players click one generated option ID. They never type free-text answers.
7. Backend calls `POST /ai/score-rounds` when the future event, match statistic, award decision, or referee verdict resolves the correct option.
