from __future__ import annotations

from typing import Any

from .bedrock_client import BedrockJSONClient
from .event_normalizer import normalize_event, normalize_event_xml
from .models import UserProfile
from .prompts import SYSTEM_PROMPT, build_prediction_prompt, build_var_prediction_prompt


class ArenaAI:
    """Bedrock-backed AI facade used by the game engine."""

    def __init__(self, bedrock: BedrockJSONClient | None = None) -> None:
        self.bedrock = bedrock or BedrockJSONClient()

    def generate_prediction_round(
        self,
        events: list[dict[str, Any]] | None = None,
        event_xml: str | None = None,
        user_profiles: list[dict[str, Any]] | None = None,
        match_state: dict[str, Any] | None = None,
        config: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        normalized_events = _events_from_payload(events, event_xml)
        profiles = [UserProfile.from_dict(profile) for profile in (user_profiles or [])]
        generated = self.bedrock.generate_json(
            SYSTEM_PROMPT,
            build_prediction_prompt(normalized_events, profiles, match_state or {}, config or {}),
        )
        generated.setdefault("round_kind", "PREDICTION")
        generated.setdefault("duration_seconds", int((config or {}).get("duration_seconds", 20)))
        generated.setdefault("trigger_event_ids", [event["event_id"] for event in normalized_events])
        generated["correct_answer_id"] = None
        return _validate_round(generated)

    def generate_trivia_round(
        self,
        events: list[dict[str, Any]] | None = None,
        event_xml: str | None = None,
        user_profiles: list[dict[str, Any]] | None = None,
        match_state: dict[str, Any] | None = None,
        config: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Backward-compatible alias for the prediction-round endpoint."""

        return self.generate_prediction_round(events, event_xml, user_profiles, match_state, config)

    def generate_var_prediction_round(
        self,
        var_event: dict[str, Any] | None = None,
        event_xml: str | None = None,
        user_profiles: list[dict[str, Any]] | None = None,
        match_state: dict[str, Any] | None = None,
        config: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        normalized_event = _single_event_from_payload(var_event, event_xml)
        check_type = str(normalized_event.get("check_type") or normalized_event.get("metadata", {}).get("CheckType") or "").lower()
        if "offside" in check_type:
            return {
                "status": "skipped",
                "reason": "Offside VAR checks are skipped because broadcast lines can reveal the answer.",
                "trigger_event_id": normalized_event.get("event_id"),
            }

        profiles = [UserProfile.from_dict(profile) for profile in (user_profiles or [])]
        generated = self.bedrock.generate_json(
            SYSTEM_PROMPT,
            build_var_prediction_prompt(normalized_event, profiles, match_state or {}, config or {}),
        )
        generated.setdefault("round_kind", "VAR_PREDICTION")
        generated.setdefault("duration_seconds", int((config or {}).get("duration_seconds", 20)))
        generated.setdefault("trigger_event_ids", [normalized_event["event_id"]])
        generated["correct_answer_id"] = None
        return _validate_round(generated)

    def normalize_event(self, event: dict[str, Any] | None = None, event_xml: str | None = None) -> dict[str, Any]:
        return _single_event_from_payload(event, event_xml)


def _events_from_payload(events: list[dict[str, Any]] | None, event_xml: str | None) -> list[dict[str, Any]]:
    if event_xml:
        return [normalize_event_xml(event_xml)]
    if not events:
        raise ValueError("events or event_xml is required")
    return [normalize_event(event) for event in events]


def _single_event_from_payload(event: dict[str, Any] | None, event_xml: str | None) -> dict[str, Any]:
    if event_xml:
        return normalize_event_xml(event_xml)
    if not event:
        raise ValueError("event or event_xml is required")
    return normalize_event(event)


def _validate_round(round_payload: dict[str, Any]) -> dict[str, Any]:
    required = ["round_kind", "question", "options", "resolution_rule", "duration_seconds"]
    missing = [key for key in required if key not in round_payload]
    if missing:
        raise ValueError(f"Generated round missing required keys: {', '.join(missing)}")
    if not isinstance(round_payload["options"], list) or len(round_payload["options"]) < 2:
        raise ValueError("Generated round must include at least two options")
    if round_payload.get("correct_answer_id") is not None:
        raise ValueError("Generated prediction rounds must not include correct_answer_id before resolution")
    return round_payload
