from __future__ import annotations

import json
from typing import Any

from .arena_ai import ArenaAI
from .scoring import ScoreEngine


def handler(event: dict[str, Any], _context: Any = None) -> dict[str, Any]:
    """AWS Lambda entry point for the AI endpoints."""

    try:
        payload = _body(event)
        action = payload.get("action", "generate_prediction_round")

        if action in {"generate_prediction_round", "generate_trivia_round"}:
            result = ArenaAI().generate_prediction_round(
                events=payload.get("events"),
                event_xml=payload.get("event_xml"),
                user_profiles=payload.get("user_profiles"),
                match_state=payload.get("match_state"),
                config=payload.get("config"),
            )
        elif action == "generate_var_prediction_round":
            result = ArenaAI().generate_var_prediction_round(
                var_event=payload.get("var_event") or payload.get("event"),
                event_xml=payload.get("event_xml"),
                user_profiles=payload.get("user_profiles"),
                match_state=payload.get("match_state"),
                config=payload.get("config"),
            )
        elif action == "normalize_event":
            result = ArenaAI().normalize_event(
                event=payload.get("event"),
                event_xml=payload.get("event_xml"),
            )
        elif action == "score_round":
            result = ScoreEngine().score_round(
                payload["round"],
                payload.get("answers", []),
                payload.get("correct_answer_id"),
                payload.get("previous_player_state"),
            )
        else:
            return _response(400, {"error": f"Unsupported action: {action}"})
    except Exception as exc:
        return _response(500, {"error": str(exc), "error_type": exc.__class__.__name__})

    return _response(200, result)


def _body(event: dict[str, Any]) -> dict[str, Any]:
    body = event.get("body", event)
    if isinstance(body, str):
        return json.loads(body or "{}")
    return body


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body),
    }
