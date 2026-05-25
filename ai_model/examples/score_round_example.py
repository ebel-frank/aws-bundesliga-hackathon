from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai_core import ScoreEngine


round_payload = {
    "round_id": "m1-42-goal-NEXT_GOAL",
    "round_type": "NEXT_GOAL",
    "correct_answer_id": "A",
}

answers = [
    {"user_id": "u1", "answer_id": "A", "round_started_at_ms": 100000, "submitted_at_ms": 103200},
    {"user_id": "u2", "answer_id": "B", "round_started_at_ms": 100000, "submitted_at_ms": 108400},
]

previous_state = {
    "u1": {"xp": 20, "streak": 2, "badges": []},
    "u2": {"xp": 15, "streak": 1, "badges": []},
}

result = ScoreEngine().score_round(round_payload, answers, previous_player_state=previous_state)
print(json.dumps(result, indent=2))
