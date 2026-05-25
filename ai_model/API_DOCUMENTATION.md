# Live Prediction Arena AI API

Base URL depends on deployment:

- Local FastAPI: `http://localhost:8000`
- API Gateway/Lambda: your deployed API Gateway URL

All request and response bodies are JSON unless noted.

## Core Rule

All player-facing rounds are multiple-choice predictions.

- The AI/game engine generates the question and candidate answers.
- Players click one generated option ID, for example `A`, `B`, `C`, or `D`.
- Players never type free-text answers.
- `correct_answer_id` is `null` when a prediction round is created.
- The backend/game engine fills in the correct option later when the relevant match event, match statistic, award, or referee verdict is known.

Examples:

- “Who will score the next goal?” resolves from the next `GOAL` event.
- “Which team gets the next shot on target?” resolves from the next shot event.
- “Who will win player of the match?” resolves when the award/stat decision is available.
- “What will the referee decide?” resolves from the final VAR verdict.

## Environment

Required for generation endpoints:

```text
AWS_REGION=us-east-1
BEDROCK_MODEL_ID=amazon.nova-lite-v1:0
```

`BEDROCK_MODEL_ID` can be replaced with any approved Bedrock model ID in the hackathon account.

## Endpoints

- `GET /health`
- `POST /ai/prediction-rounds`
- `POST /ai/trivia-rounds` compatibility alias for `/ai/prediction-rounds`
- `POST /ai/var-rounds`
- `POST /ai/events/normalize`
- `POST /ai/score-rounds`
- `POST /ai` generic Lambda-style action endpoint

## Normalized Event

The AI service converts DFL-style XML into this shape:

```json
{
  "event_id": "18902400000006",
  "match_id": "DFL-MAT-111111",
  "event_type": "KICK_OFF",
  "event_time": "2025-01-01T16:30:17.210+02:00",
  "minute": 0,
  "team": "DFL-CLU-000002",
  "player": "DFL-OBJ-000029",
  "recipient": "DFL-OBJ-000025",
  "x_position": 52.3,
  "y_position": 35.3,
  "evaluation": "successfullyCompleted",
  "play_origin": "ownHalf",
  "distance": "short",
  "height": "high",
  "check_type": null,
  "verdict": null,
  "metadata": {}
}
```

The backend may send already-normalized event dictionaries or raw `event_xml`.

## GET /health

### Response 200

```json
{
  "status": "ok",
  "service": "live-prediction-arena-ai"
}
```

## POST /ai/events/normalize

Converts one DFL XML event or raw event dictionary into the normalized event shape.

### Request With XML

```json
{
  "event_xml": "<Event EventId=\"18902400000006\" X-Position=\"52.30\" MatchId=\"DFL-MAT-111111\" Y-Position=\"35.30\"><KickOff TeamLeft=\"DFL-CLU-000002\" TeamRight=\"DFL-CLU-000001\" GameSection=\"firstHalf\"><Play Recipient=\"DFL-OBJ-000025\" Team=\"DFL-CLU-000002\" Height=\"high\" Distance=\"short\" Player=\"DFL-OBJ-000029\" Evaluation=\"successfullyCompleted\"><Pass FreeKickLayup=\"false\"/></Play></KickOff></Event>"
}
```

### Response 200

```json
{
  "event_id": "18902400000006",
  "match_id": "DFL-MAT-111111",
  "event_type": "KICK_OFF",
  "event_time": null,
  "minute": 0,
  "team": "DFL-CLU-000002",
  "player": "DFL-OBJ-000029",
  "recipient": "DFL-OBJ-000025",
  "x_position": 52.3,
  "y_position": 35.3,
  "evaluation": "successfullyCompleted",
  "play_origin": null,
  "distance": "short",
  "height": "high",
  "score_home": null,
  "score_away": null,
  "check_type": null,
  "verdict": null,
  "metadata": {
    "EventId": "18902400000006",
    "MatchId": "DFL-MAT-111111",
    "action_path": ["KickOff", "Play", "Pass"]
  }
}
```

## POST /ai/prediction-rounds

Generates one Kahoot-style multiple-choice prediction round. The answer is not known yet.

Use this for short-horizon and long-horizon game prompts:

- next goal scorer
- next team to shoot
- next successful pass
- next card
- next substitution
- player of the match
- clean sheet at half-time
- any future event that can later be resolved from data

### Request: Next Goal Prediction

```json
{
  "event_xml": "<Event EventId=\"18902400000006\" X-Position=\"52.30\" MatchId=\"DFL-MAT-111111\" Y-Position=\"35.30\"><KickOff TeamLeft=\"DFL-CLU-000002\" TeamRight=\"DFL-CLU-000001\" GameSection=\"firstHalf\"><Play Recipient=\"DFL-OBJ-000025\" Team=\"DFL-CLU-000002\" Height=\"high\" Distance=\"short\" Player=\"DFL-OBJ-000029\" Evaluation=\"successfullyCompleted\"><Pass FreeKickLayup=\"false\"/></Play></KickOff></Event>",
  "user_profiles": [
    {"user_id": "u1", "display_name": "Amina", "favorite_team": "DFL-CLU-000002"},
    {"user_id": "u2", "display_name": "Noah", "favorite_team": "DFL-CLU-000001"}
  ],
  "match_state": {
    "home_team": "DFL-CLU-000002",
    "away_team": "DFL-CLU-000001",
    "score_home": 0,
    "score_away": 0,
    "game_section": "firstHalf"
  },
  "config": {
    "duration_seconds": 20,
    "option_count": 4,
    "prediction_type": "next_goal_scorer",
    "prediction_horizon": "next_goal",
    "candidate_pool": {
      "players": [
        {"id": "DFL-OBJ-000029", "name": "Player 29", "team": "DFL-CLU-000002"},
        {"id": "DFL-OBJ-000010", "name": "Player 10", "team": "DFL-CLU-000001"},
        {"id": "DFL-OBJ-000025", "name": "Player 25", "team": "DFL-CLU-000002"}
      ],
      "include_no_goal_option": true
    }
  }
}
```

### Response 200

```json
{
  "round_id": "DFL-MAT-111111-18902400000006-prediction-1",
  "round_kind": "PREDICTION",
  "trigger_event_ids": ["18902400000006"],
  "question": "Who will score the next goal?",
  "options": [
    {"id": "A", "label": "Player 29"},
    {"id": "B", "label": "Player 10"},
    {"id": "C", "label": "Player 25"},
    {"id": "D", "label": "No goal before half-time"}
  ],
  "correct_answer_id": null,
  "resolution_rule": "Resolve from the next GOAL event. Match GOAL.Player against the selected option label or candidate id.",
  "resolution_event_types": ["GOAL", "HALFTIME"],
  "expires_at_event": "HALFTIME if no goal occurs before then",
  "explanation": "Players predict the next scorer from the live player pool.",
  "difficulty": "medium",
  "tags": ["prediction", "goal"],
  "duration_seconds": 20,
  "reward_policy": {
    "base_xp": 10,
    "speed_bonus_xp": 5,
    "streak_multiplier": "1.5x after 3 correct, 2x after 5 correct"
  }
}
```

### Request: Player Of The Match Prediction

```json
{
  "events": [
    {
      "EventId": "18902400000040",
      "MatchId": "DFL-MAT-111111",
      "primary_action": "HalfTime",
      "minute": 45
    }
  ],
  "match_state": {
    "score_home": 1,
    "score_away": 1,
    "game_section": "halfTime"
  },
  "config": {
    "duration_seconds": 20,
    "option_count": 4,
    "prediction_type": "player_of_the_match",
    "prediction_horizon": "end_of_match",
    "candidate_pool": {
      "players": [
        {"id": "DFL-OBJ-000029", "name": "Player 29", "team": "DFL-CLU-000002"},
        {"id": "DFL-OBJ-000010", "name": "Player 10", "team": "DFL-CLU-000001"},
        {"id": "DFL-OBJ-000025", "name": "Player 25", "team": "DFL-CLU-000002"},
        {"id": "DFL-OBJ-000001", "name": "Player 1", "team": "DFL-CLU-000001"}
      ]
    }
  }
}
```

### Response 200

```json
{
  "round_id": "DFL-MAT-111111-potm-prediction",
  "round_kind": "PREDICTION",
  "trigger_event_ids": ["18902400000040"],
  "question": "Who will be player of the match?",
  "options": [
    {"id": "A", "label": "Player 29"},
    {"id": "B", "label": "Player 10"},
    {"id": "C", "label": "Player 25"},
    {"id": "D", "label": "Player 1"}
  ],
  "correct_answer_id": null,
  "resolution_rule": "Resolve when the final player-of-the-match award or selected KPI winner is available.",
  "resolution_event_types": ["PLAYER_OF_THE_MATCH", "FULL_TIME"],
  "expires_at_event": "FULL_TIME",
  "explanation": "Players make a long-horizon match prediction.",
  "difficulty": "hard",
  "tags": ["prediction", "award"],
  "duration_seconds": 20
}
```

## POST /ai/trivia-rounds

Compatibility alias for `/ai/prediction-rounds`.

Use `/ai/prediction-rounds` for new integration work. This alias exists only in case the frontend already started with the older trivia route name.

## POST /ai/var-rounds

Generates a VAR prediction round while the referee is checking an incident.

Offside checks are intentionally skipped because broadcast lines may reveal the answer.

### Request

```json
{
  "var_event": {
    "EventId": "var-001",
    "MatchId": "DFL-MAT-111111",
    "primary_action": "VAR",
    "CheckType": "possible penalty",
    "Team": "DFL-CLU-000002",
    "Player": "DFL-OBJ-000029",
    "minute": 64
  },
  "match_state": {
    "score_home": 1,
    "score_away": 1,
    "game_section": "secondHalf"
  },
  "config": {
    "duration_seconds": 20,
    "option_count": 3
  }
}
```

### Response 200

```json
{
  "round_id": "DFL-MAT-111111-var-001-var",
  "round_kind": "VAR_PREDICTION",
  "trigger_event_ids": ["var-001"],
  "question": "What will the referee decide after this VAR check?",
  "options": [
    {"id": "A", "label": "Penalty awarded"},
    {"id": "B", "label": "No penalty"},
    {"id": "C", "label": "Attacking foul"}
  ],
  "correct_answer_id": null,
  "resolution_rule": "Backend sets correct_answer_id after the referee verdict is available.",
  "resolution_event_types": ["VAR_VERDICT"],
  "expires_at_event": "VAR_VERDICT",
  "explanation": "Players predict the decision before the referee announces it.",
  "difficulty": "easy",
  "tags": ["var", "penalty"],
  "duration_seconds": 20,
  "reward_policy": {
    "base_xp": 10,
    "speed_bonus_xp": 5,
    "streak_multiplier": "1.5x after 3 correct, 2x after 5 correct"
  }
}
```

### Offside Skip Response 200

```json
{
  "status": "skipped",
  "reason": "Offside VAR checks are skipped because broadcast lines can reveal the answer.",
  "trigger_event_id": "var-002"
}
```

## POST /ai/score-rounds

Scores player submissions after the prediction is resolved.

The backend passes the correct option ID after it maps the future event, stat, award, or VAR verdict to one of the generated options.

### Request

```json
{
  "round": {
    "round_id": "DFL-MAT-111111-18902400000006-prediction-1",
    "round_kind": "PREDICTION",
    "correct_answer_id": "A"
  },
  "answers": [
    {
      "user_id": "u1",
      "answer_id": "A",
      "round_started_at_ms": 1760000000000,
      "submitted_at_ms": 1760000003400
    },
    {
      "user_id": "u2",
      "answer_id": "B",
      "round_started_at_ms": 1760000000000,
      "submitted_at_ms": 1760000007200
    }
  ],
  "previous_player_state": {
    "u1": {"xp": 20, "streak": 2, "badges": []},
    "u2": {"xp": 15, "streak": 1, "badges": []}
  }
}
```

### Response 200

```json
{
  "round_id": "DFL-MAT-111111-18902400000006-prediction-1",
  "correct_answer_id": "A",
  "answers": [
    {
      "user_id": "u1",
      "answer_id": "A",
      "is_correct": true,
      "response_ms": 3400,
      "base_xp": 10,
      "speed_bonus": 5,
      "streak_multiplier": 1.5,
      "round_xp": 22,
      "total_xp": 42,
      "streak": 3,
      "earned_badges": ["Match Oracle"]
    }
  ],
  "player_state": {
    "u1": {"xp": 42, "streak": 3, "badges": ["Match Oracle"]}
  },
  "leaderboard": [
    {"user_id": "u1", "xp": 42, "streak": 3, "badges": ["Match Oracle"], "rank": 1}
  ]
}
```

## POST /ai

Generic Lambda-style endpoint. Add an `action` field and use the same payload.

### Example

```json
{
  "action": "generate_prediction_round",
  "event_xml": "<Event>...</Event>",
  "match_state": {},
  "config": {"duration_seconds": 20}
}
```

Supported actions:

- `generate_prediction_round`
- `generate_trivia_round` compatibility alias
- `generate_var_prediction_round`
- `normalize_event`
- `score_round`

## Error Response

Generation endpoints depend on Bedrock. If Bedrock is not configured or returns invalid JSON, the service returns:

```json
{
  "error": "AWS_REGION or AWS_DEFAULT_REGION must be set for Amazon Bedrock",
  "error_type": "RuntimeError"
}
```

HTTP status: `500`.
