from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


EVENT_TYPE_ALIASES = {
    "GOAL": "GOAL",
    "YELLOW_CARD": "YELLOW_CARD",
    "YELLOWCARD": "YELLOW_CARD",
    "RED_CARD": "RED_CARD",
    "REDCARD": "RED_CARD",
    "SUBSTITUTION": "SUBSTITUTION",
    "HALFTIME": "HALFTIME",
    "HALF_TIME": "HALFTIME",
    "KICKOFF": "KICK_OFF",
    "KICK_OFF": "KICK_OFF",
    "PLAY": "PLAY",
    "PASS": "PASS",
    "SHOT": "SHOT",
    "SHOT_ON_TARGET": "SHOT_ON_TARGET",
    "CORNER": "CORNER",
    "POSSESSION": "POSSESSION",
    "POSSESSION_CHANGE": "POSSESSION_CHANGE",
    "VAR": "VAR_CHECK",
    "VAR_CHECK": "VAR_CHECK",
    "VIDEO_ASSISTANT_REFEREE": "VAR_CHECK",
}


def normalize_event(raw: dict[str, Any]) -> dict[str, Any]:
    event_type = _first(raw, "event_type", "type", "eventType", "qualifier", "primary_action")
    normalized_type = EVENT_TYPE_ALIASES.get(str(event_type or "").upper(), str(event_type or "UNKNOWN").upper())
    event_time = _first(raw, "event_time", "EventTime", "timestamp")
    minute = _first(raw, "minute", "match_minute", "matchMinute", "time")

    return {
        "event_id": str(_first(raw, "event_id", "EventId", "id", "eventId") or f"{normalized_type}-{minute or event_time or 0}"),
        "match_id": _first(raw, "match_id", "MatchId", "matchId"),
        "event_type": normalized_type,
        "event_time": event_time,
        "minute": _optional_int(minute) or 0,
        "team": _first(raw, "team", "Team", "teamName", "club"),
        "player": _first(raw, "player", "Player", "playerName", "person"),
        "recipient": _first(raw, "recipient", "Recipient"),
        "related_player": _first(raw, "related_player", "assist", "subbed_for", "relatedPlayer"),
        "x_position": _optional_float(_first(raw, "x_position", "X-Position")),
        "y_position": _optional_float(_first(raw, "y_position", "Y-Position")),
        "evaluation": _first(raw, "evaluation", "Evaluation"),
        "play_origin": _first(raw, "play_origin", "PlayOrigin"),
        "distance": _first(raw, "distance", "Distance"),
        "height": _first(raw, "height", "Height"),
        "score_home": _optional_int(_first(raw, "score_home", "homeScore")),
        "score_away": _optional_int(_first(raw, "score_away", "awayScore")),
        "check_type": _first(raw, "check_type", "CheckType", "varCheckType"),
        "verdict": _first(raw, "verdict", "Verdict", "Decision"),
        "metadata": raw,
    }


def normalize_event_xml(xml_text: str) -> dict[str, Any]:
    """Normalize one DFL-style <Event> XML snippet into the AI API event shape."""

    node = ET.fromstring(xml_text.strip())
    if _strip_namespace(node.tag) != "Event":
        raise ValueError("XML payload must have Event as the root element")
    return normalize_event(_flatten_event_node(node))


def load_events_from_xml(path: str | Path) -> list[dict[str, Any]]:
    root = ET.parse(path).getroot()
    return [normalize_event(_flatten_event_node(node)) for node in root.iter() if _strip_namespace(node.tag) == "Event"]


def _flatten_event_node(event_node: ET.Element) -> dict[str, Any]:
    raw: dict[str, Any] = dict(event_node.attrib)
    action_path: list[str] = []

    for node in event_node.iter():
        if node is event_node:
            continue
        tag = _strip_namespace(node.tag)
        action_path.append(tag)
        for key, value in node.attrib.items():
            raw.setdefault(key, value)
            raw[f"{tag}.{key}"] = value
        if node.text and node.text.strip():
            raw[tag] = node.text.strip()

    raw["action_path"] = action_path
    raw["primary_action"] = _infer_primary_action(action_path)
    return raw


def _infer_primary_action(action_path: list[str]) -> str:
    priority = [
        "Goal",
        "RedCard",
        "YellowCard",
        "Substitution",
        "VAR",
        "Var",
        "VideoAssistantReferee",
        "KickOff",
        "Shot",
        "Corner",
        "Pass",
        "Play",
    ]
    for candidate in priority:
        if candidate in action_path:
            return candidate
    return action_path[0] if action_path else "UNKNOWN"


def _first(data: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if data.get(key) not in (None, ""):
            return data[key]
    return None


def _optional_int(value: Any) -> int | None:
    if value in (None, ""):
        return None
    return int(float(value))


def _optional_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def _strip_namespace(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]
