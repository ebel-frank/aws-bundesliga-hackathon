from __future__ import annotations

from collections import defaultdict
from typing import Any

from .models import PlayerAnswer


class ScoreEngine:
    """Applies Live Prediction Arena XP, speed, streak, and badge rules."""

    def score_round(
        self,
        round_payload: dict[str, Any],
        answers: list[dict[str, Any]],
        correct_answer_id: str | None = None,
        previous_player_state: dict[str, dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        previous = previous_player_state or {}
        correct_id = str(correct_answer_id or round_payload.get("correct_answer_id") or "")
        if not correct_id:
            raise ValueError("correct_answer_id is required once the round is resolved")

        scored_answers = []
        new_state: dict[str, dict[str, Any]] = defaultdict(dict)

        for raw_answer in answers:
            answer = PlayerAnswer.from_dict(raw_answer)
            prior = previous.get(answer.user_id, {})
            prior_xp = int(prior.get("xp") or 0)
            prior_streak = int(prior.get("streak") or answer.current_streak or 0)
            prior_badges = list(prior.get("badges") or [])

            is_correct = answer.answer_id == correct_id
            response_ms = max(0, answer.submitted_at_ms - answer.round_started_at_ms)
            speed_bonus = 5 if is_correct and response_ms <= 5000 else 0
            new_streak_value = prior_streak + 1 if is_correct else 0
            multiplier = _streak_multiplier(new_streak_value)
            base_xp = 10 if is_correct else 0
            round_xp = int(round((base_xp + speed_bonus) * multiplier))
            earned_badges = _earned_badges(round_payload, is_correct, prior_badges)

            state_badges = prior_badges + [badge for badge in earned_badges if badge not in prior_badges]
            new_state[answer.user_id] = {
                "xp": prior_xp + round_xp,
                "streak": new_streak_value,
                "badges": state_badges,
            }
            scored_answers.append(
                {
                    "user_id": answer.user_id,
                    "answer_id": answer.answer_id,
                    "is_correct": is_correct,
                    "response_ms": response_ms,
                    "base_xp": base_xp,
                    "speed_bonus": speed_bonus,
                    "streak_multiplier": multiplier,
                    "round_xp": round_xp,
                    "total_xp": prior_xp + round_xp,
                    "streak": new_streak_value,
                    "earned_badges": earned_badges,
                }
            )

        leaderboard = sorted(
            [
                {
                    "user_id": user_id,
                    "xp": state["xp"],
                    "streak": state["streak"],
                    "badges": state["badges"],
                }
                for user_id, state in new_state.items()
            ],
            key=lambda item: (-item["xp"], item["user_id"]),
        )
        for rank, row in enumerate(leaderboard, start=1):
            row["rank"] = rank

        return {
            "round_id": round_payload.get("round_id"),
            "correct_answer_id": correct_id,
            "answers": scored_answers,
            "player_state": dict(new_state),
            "leaderboard": leaderboard,
        }


def _streak_multiplier(streak: int) -> float:
    if streak >= 5:
        return 2.0
    if streak >= 3:
        return 1.5
    return 1.0


def _earned_badges(round_payload: dict[str, Any], is_correct: bool, prior_badges: list[str]) -> list[str]:
    if not is_correct:
        return []
    round_type = str(round_payload.get("round_type") or round_payload.get("round_kind") or "").upper()
    badge_by_type = {
        "PREDICTION": "Match Oracle",
        "NEXT_GOAL": "Oracle",
        "NEXT_CARD": "Red Mist",
        "HALF_TIME": "Iron Wall",
        "VAR_PREDICTION": "VAR Whisperer",
    }
    badge = badge_by_type.get(round_type)
    if badge and badge not in prior_badges:
        return [badge]
    return []
