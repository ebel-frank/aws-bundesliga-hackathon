from __future__ import annotations

import json
from typing import Any

from .models import UserProfile


SYSTEM_PROMPT = (
    "You are the AI game master for Live Prediction Arena, a Kahoot-style "
    "multiplayer football prediction game. Return strict JSON only. Do not use "
    "markdown. Do not include explanations outside JSON. Questions must be fair, "
    "short, answerable by selecting one provided option, and resolvable later "
    "from match events, match statistics, or referee verdict data."
)


def build_prediction_prompt(
    events: list[dict[str, Any]],
    profiles: list[UserProfile],
    match_state: dict[str, Any],
    config: dict[str, Any],
) -> str:
    horizon = config.get("prediction_horizon", "next_event")
    prediction_type = config.get("prediction_type", "auto")
    payload = {
        "task": "Generate one multiple-choice prediction round with candidate answers.",
        "examples": [
            "Who will score the next goal?",
            "Which team will have the next shot on target?",
            "Who will win player of the match?",
            "Will the next substitution happen before minute 70?",
        ],
        "game_rules": {
            "style": "Kahoot-like multiple-choice prediction",
            "duration_seconds": int(config.get("duration_seconds", 20)),
            "option_count": int(config.get("option_count", 4)),
            "players_select_one_answer": True,
            "players_never_type_answers": True,
            "correct_answer_required_now": False,
            "prediction_type": prediction_type,
            "prediction_horizon": horizon,
            "candidate_answer_source": (
                "Use only teams, players, outcomes, or awards provided in events, "
                "match_state, or config.candidate_pool."
            ),
            "avoid": [
                "free-text answers",
                "spelling-dependent answers",
                "naming-convention ambiguity",
                "offside VAR checks",
                "questions impossible to resolve from future data",
            ],
        },
        "events": events,
        "match_state": match_state,
        "candidate_pool": config.get("candidate_pool", {}),
        "room_context": _room_context(profiles),
        "required_json_schema": _round_schema("PREDICTION"),
    }
    return json.dumps(payload, ensure_ascii=True)


def build_var_prediction_prompt(
    var_event: dict[str, Any],
    profiles: list[UserProfile],
    match_state: dict[str, Any],
    config: dict[str, Any],
) -> str:
    payload = {
        "task": "Generate one VAR verdict prediction round.",
        "game_rules": {
            "style": "Kahoot-like multiple-choice prediction during a VAR check",
            "duration_seconds": int(config.get("duration_seconds", 20)),
            "option_count": int(config.get("option_count", 3)),
            "players_select_one_answer": True,
            "players_never_type_answers": True,
            "correct_answer_required_now": False,
            "reward_after_referee_verdict": True,
            "exclude_offside_checks": True,
        },
        "var_event": var_event,
        "match_state": match_state,
        "candidate_pool": config.get("candidate_pool", {}),
        "room_context": _room_context(profiles),
        "required_json_schema": _round_schema("VAR_PREDICTION"),
    }
    return json.dumps(payload, ensure_ascii=True)


def _room_context(profiles: list[UserProfile]) -> dict[str, Any]:
    favorite_teams = sorted({p.favorite_team for p in profiles if p.favorite_team})
    return {
        "player_count": len(profiles),
        "favorite_teams": favorite_teams,
        "tone": "energetic, short, social, not childish",
    }


def _round_schema(round_kind: str) -> dict[str, Any]:
    return {
        "round_id": "string",
        "round_kind": round_kind,
        "question": "string under 140 characters",
        "options": [
            {"id": "A", "label": "short generated candidate answer"},
            {"id": "B", "label": "short generated candidate answer"},
        ],
        "correct_answer_id": None,
        "resolution_rule": "exactly how the backend resolves this later from event/stat/verdict data",
        "resolution_event_types": ["event/stat/verdict types that can resolve this prediction"],
        "expires_at_event": "optional event condition after which the prediction should be void or closed",
        "explanation": "one short sentence for the host/results screen",
        "difficulty": "easy | medium | hard",
        "tags": ["short lowercase strings"],
        "duration_seconds": "integer",
        "reward_policy": {
            "base_xp": 10,
            "speed_bonus_xp": 5,
            "streak_multiplier": "1.5x after 3 correct, 2x after 5 correct",
        },
    }
