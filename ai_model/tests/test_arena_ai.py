import json
import unittest

from ai_core import ArenaAI, ScoreEngine


class FakeBedrock:
    def generate_json(self, _system_prompt, user_prompt):
        payload = json.loads(user_prompt)
        if payload["required_json_schema"]["round_kind"] == "VAR_PREDICTION":
            return {
                "round_id": "var-1",
                "round_kind": "VAR_PREDICTION",
                "question": "What will the referee decide?",
                "options": [{"id": "A", "label": "Goal stands"}, {"id": "B", "label": "Goal cancelled"}],
                "correct_answer_id": None,
                "resolution_rule": "Resolve when the referee announces the final VAR verdict.",
                "explanation": "The room predicts the decision before the verdict.",
                "difficulty": "easy",
                "tags": ["var"],
                "duration_seconds": 20,
            }
        return {
            "round_id": "prediction-1",
            "round_kind": "PREDICTION",
            "question": "Who will score the next goal?",
            "options": [{"id": "A", "label": "DFL-OBJ-000029"}, {"id": "B", "label": "DFL-OBJ-000010"}],
            "correct_answer_id": None,
            "resolution_rule": "Resolve from the next GOAL event's Player value.",
            "resolution_event_types": ["GOAL"],
            "explanation": "The room predicts the next scorer from the player pool.",
            "difficulty": "medium",
            "tags": ["goal", "prediction"],
            "duration_seconds": 20,
        }


class ArenaAITest(unittest.TestCase):
    def test_prediction_round_uses_bedrock_client_output_without_correct_answer(self):
        result = ArenaAI(bedrock=FakeBedrock()).generate_prediction_round(
            events=[
                {
                    "EventId": "e1",
                    "primary_action": "Pass",
                    "minute": 12,
                    "Team": "DFL-CLU-000002",
                    "Player": "DFL-OBJ-000029",
                }
            ],
            user_profiles=[{"user_id": "u1", "display_name": "Amina"}],
            config={"candidate_pool": {"players": ["DFL-OBJ-000029", "DFL-OBJ-000010"]}},
        )

        self.assertEqual(result["round_kind"], "PREDICTION")
        self.assertIsNone(result["correct_answer_id"])
        self.assertEqual(result["trigger_event_ids"], ["e1"])

    def test_trivia_alias_returns_prediction_round(self):
        result = ArenaAI(bedrock=FakeBedrock()).generate_trivia_round(
            events=[{"EventId": "e2", "primary_action": "Pass", "minute": 12}]
        )

        self.assertEqual(result["round_kind"], "PREDICTION")
        self.assertIsNone(result["correct_answer_id"])

    def test_var_round_skips_offside_checks(self):
        result = ArenaAI(bedrock=FakeBedrock()).generate_var_prediction_round(
            var_event={"EventId": "v1", "primary_action": "VAR", "CheckType": "offside"}
        )

        self.assertEqual(result["status"], "skipped")
        self.assertEqual(result["trigger_event_id"], "v1")

    def test_var_round_uses_bedrock_for_non_offside(self):
        result = ArenaAI(bedrock=FakeBedrock()).generate_var_prediction_round(
            var_event={"EventId": "v2", "primary_action": "VAR", "CheckType": "possible penalty"}
        )

        self.assertEqual(result["round_kind"], "VAR_PREDICTION")
        self.assertIsNone(result["correct_answer_id"])

    def test_scoring_applies_speed_streak_and_var_badge(self):
        result = ScoreEngine().score_round(
            {"round_id": "r1", "round_kind": "VAR_PREDICTION", "correct_answer_id": "A"},
            [{"user_id": "u1", "answer_id": "A", "round_started_at_ms": 1000, "submitted_at_ms": 3000}],
            previous_player_state={"u1": {"xp": 20, "streak": 2, "badges": []}},
        )

        answer = result["answers"][0]
        self.assertIs(answer["is_correct"], True)
        self.assertEqual(answer["round_xp"], 22)
        self.assertEqual(answer["total_xp"], 42)
        self.assertEqual(answer["earned_badges"], ["VAR Whisperer"])


if __name__ == "__main__":
    unittest.main()
