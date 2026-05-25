# AI Question Pipeline Design

## Overview

The AI Question Pipeline generates live prediction questions during a match by detecting specific trigger events from the DFL event feed, waiting a defined delay, then calling Bedrock to generate a contextual question that gets broadcast to players via WebSocket.

## Architecture

```
Stream Lambda (emits events) 
    → Question Trigger Lambda (buffers events, detects triggers, waits delay)
        → Bedrock (generates question)
            → WebSocket (broadcasts to players)
```

## Trigger Events & Delays

| Trigger Event | Delay (seconds) | Rationale |
|---|---|---|
| Goal | 30-45 | Let players celebrate |
| Card (Yellow/Red) | 10-15 | Quick moment, curiosity peaks fast |
| Substitution | 5-10 | Natural pause already happening |
| Corner kick awarded | 0 | Players are waiting for it to be taken |
| Halftime whistle | 15-20 | Settling in |
| Shot on target (saved) | 10-15 | Tension just released |
| Free kick in dangerous area | 0 | Natural pause, setup happening |

## Rules

- ONLY these specific events trigger questions — nothing else
- Each trigger has a FIXED delay (no heuristics, no "wait for calm")
- After the delay, call Bedrock with full match context
- Question is predictive: "What happens NEXT?"
- Expected ~15-25 questions per match
- No minimum spacing enforced (triggers are naturally spaced)

## Event Detection Logic

From the DFL KPI data, triggers are detected by:

```javascript
// Goal
event.eventType === 'Goal'

// Card
event.eventType === 'Card'

// Substitution
event.eventType === 'Substitution'

// Corner
event.subType === 'Corner' || play.IsCorner === 'true'

// Halftime
event.gameSection changes from 'firstHalf' to 'secondHalf'

// Shot on target (saved - no goal)
event.subType === 'Shot' && event.evaluation === 'savedByGoalkeeper'

// Free kick in dangerous area (x > 70% of pitch)
play.IsFreeKick === 'true' && event.xPosition > 73.5  // (105m * 0.7)
```

## Bedrock Input Format

### System Prompt
```
You are a live football prediction quiz generator for the Bundesliga.
Generate engaging multiple-choice questions based on real-time match events.
Questions must be PREDICTIVE (what happens NEXT), not about what already happened.
Questions should be answerable within 15 seconds.
Return valid JSON only.
```

### User Message (sample - after a Goal)
```json
{
  "match": {
    "competition": "Bundesliga",
    "homeTeam": "FC Bayern",
    "awayTeam": "Hamburger SV",
    "score": "1-0",
    "minute": "23'",
    "stadium": "Allianz Arena"
  },
  "trigger": {
    "type": "Goal",
    "team": "FC Bayern",
    "player": "S. Sechs",
    "minute": "22'"
  },
  "recentEvents": [
    { "minute": "20'", "type": "Pass", "player": "S. Fünf", "team": "FC Bayern", "evaluation": "successful" },
    { "minute": "21'", "type": "Shot", "player": "S. Sechs", "team": "FC Bayern", "evaluation": "saved" },
    { "minute": "21'", "type": "Corner", "team": "FC Bayern" },
    { "minute": "22'", "type": "Goal", "player": "S. Sechs", "team": "FC Bayern", "assist": "S. Acht" }
  ],
  "matchStats": {
    "possession": { "home": 62, "away": 38 },
    "shots": { "home": 5, "away": 1 },
    "corners": { "home": 3, "away": 0 },
    "cards": { "home": 0, "away": 1 }
  },
  "instruction": "Generate a prediction question about what happens next in this match. The goal was just scored 35 seconds ago."
}
```

### Expected Bedrock Response
```json
{
  "question": "FC Bayern just scored! Will there be another goal in the next 10 minutes?",
  "options": ["Yes, Bayern scores again", "Yes, Hamburg scores", "No more goals in 10 min", "A card is given first"],
  "correctAnswer": null,
  "category": "match_prediction",
  "difficulty": "medium",
  "timeLimit": 15
}
```

Note: `correctAnswer` is null at generation time — it gets resolved later when the actual events unfold.

## Data Flow

1. **Stream Lambda** emits DFL events one-by-one via WebSocket
2. **Question Trigger Lambda** receives each event:
   - Buffers last 20 events for context
   - Checks if event matches a trigger condition
   - If trigger detected: schedules question generation after delay
   - After delay: builds Bedrock prompt with context, calls Bedrock
   - Broadcasts generated question to room via WebSocket
3. **Client** receives question, shows prediction UI, collects answers
4. **Resolution**: When the predicted event occurs (or doesn't), resolve correct answer

## Future Considerations

- **Notifications (SNS/SES)**: If player's device is off, send push notification when question is generated
- **Answer resolution**: Separate Lambda watches for events that resolve pending questions
- **Difficulty scaling**: Track player performance, adjust question difficulty
- **KPI context**: Include xP, xG, pressure data in prompts for smarter questions
