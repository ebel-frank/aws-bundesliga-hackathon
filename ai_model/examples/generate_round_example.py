from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai_core import ArenaAI


class DemoBedrock:
    def generate_json(self, _system_prompt, _user_prompt):
        return {
            "round_id": "demo-prediction-1",
            "round_kind": "PREDICTION",
            "question": "Who will complete the next successful pass?",
            "options": [{"id": "A", "label": "DFL-OBJ-000029"}, {"id": "B", "label": "DFL-OBJ-000010"}],
            "correct_answer_id": None,
            "resolution_rule": "Resolve from the next Play event where Evaluation is successfullyCompleted.",
            "resolution_event_types": ["PLAY", "PASS"],
            "explanation": "Players predict the next successful passer.",
            "difficulty": "medium",
            "tags": ["prediction", "pass"],
            "duration_seconds": 20,
        }


event_xml = """
<Event EventId="18902400000006" X-Position="52.30" MatchId="DFL-MAT-111111" Y-Position="35.30">
  <KickOff TeamLeft="DFL-CLU-000002" TeamRight="DFL-CLU-000001" GameSection="firstHalf">
    <Play Recipient="DFL-OBJ-000025" Team="DFL-CLU-000002" Height="high" Distance="short" Player="DFL-OBJ-000029" Evaluation="successfullyCompleted">
      <Pass FreeKickLayup="false"/>
    </Play>
  </KickOff>
</Event>
"""

round_payload = ArenaAI(bedrock=DemoBedrock()).generate_prediction_round(
    event_xml=event_xml,
    user_profiles=[
        {"user_id": "u1", "display_name": "Amina", "favorite_team": "DFL-CLU-000002"},
        {"user_id": "u2", "display_name": "Noah", "favorite_team": "DFL-CLU-000001"},
    ],
    match_state={"home_team": "DFL-CLU-000002", "away_team": "DFL-CLU-000001"},
    config={"candidate_pool": {"players": ["DFL-OBJ-000029", "DFL-OBJ-000010", "DFL-OBJ-000025"]}},
)

print(json.dumps(round_payload, indent=2))
