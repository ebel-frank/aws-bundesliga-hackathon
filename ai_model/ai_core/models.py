from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(slots=True)
class MatchEvent:
    event_id: str
    event_type: str
    minute: int
    team: str | None = None
    player: str | None = None
    related_player: str | None = None
    score_home: int | None = None
    score_away: int | None = None
    possession_home: float | None = None
    possession_away: float | None = None
    shots_home: int | None = None
    shots_away: int | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "MatchEvent":
        event_type = str(data.get("event_type") or data.get("type") or "").upper()
        if not event_type:
            raise ValueError("event_type is required")

        return cls(
            event_id=str(data.get("event_id") or data.get("id") or f"{event_type}-{data.get('minute', 0)}"),
            event_type=event_type,
            minute=int(data.get("minute") or data.get("match_minute") or 0),
            team=data.get("team"),
            player=data.get("player"),
            related_player=data.get("related_player") or data.get("assist") or data.get("subbed_for"),
            score_home=_optional_int(data.get("score_home")),
            score_away=_optional_int(data.get("score_away")),
            possession_home=_optional_float(data.get("possession_home")),
            possession_away=_optional_float(data.get("possession_away")),
            shots_home=_optional_int(data.get("shots_home")),
            shots_away=_optional_int(data.get("shots_away")),
            metadata=dict(data.get("metadata") or {}),
        )

    def to_context(self) -> dict[str, Any]:
        return {
            "event_id": self.event_id,
            "event_type": self.event_type,
            "minute": self.minute,
            "team": self.team,
            "player": self.player,
            "related_player": self.related_player,
            "score_home": self.score_home,
            "score_away": self.score_away,
            "possession_home": self.possession_home,
            "possession_away": self.possession_away,
            "shots_home": self.shots_home,
            "shots_away": self.shots_away,
            "metadata": self.metadata,
        }


@dataclass(slots=True)
class UserProfile:
    user_id: str
    display_name: str
    favorite_team: str | None = None
    preferred_tone: str = "energetic"
    skill_level: str = "casual"
    language: str = "en"

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "UserProfile":
        return cls(
            user_id=str(data.get("user_id") or data.get("id") or "anonymous"),
            display_name=str(data.get("display_name") or data.get("name") or "Fan"),
            favorite_team=data.get("favorite_team"),
            preferred_tone=str(data.get("preferred_tone") or "energetic"),
            skill_level=str(data.get("skill_level") or "casual"),
            language=str(data.get("language") or "en"),
        )


@dataclass(slots=True)
class PlayerAnswer:
    user_id: str
    answer_id: str
    submitted_at_ms: int
    round_started_at_ms: int = 0
    current_streak: int = 0

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "PlayerAnswer":
        return cls(
            user_id=str(data["user_id"]),
            answer_id=str(data["answer_id"]),
            submitted_at_ms=int(data.get("submitted_at_ms") or 0),
            round_started_at_ms=int(data.get("round_started_at_ms") or 0),
            current_streak=int(data.get("current_streak") or 0),
        )


def _optional_int(value: Any) -> int | None:
    if value in (None, ""):
        return None
    return int(value)


def _optional_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    return float(value)
