from __future__ import annotations

import json
import os
from typing import Any


class BedrockJSONClient:
    """JSON-only adapter for Amazon Bedrock chat models.

    Uses the Bedrock Converse API so the service can switch between approved
    hackathon models, for example Claude or Nova, by changing BEDROCK_MODEL_ID.
    """

    def __init__(
        self,
        model_id: str | None = None,
        region_name: str | None = None,
        max_tokens: int = 900,
        temperature: float = 0.35,
    ) -> None:
        self.model_id = model_id or os.getenv("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0")
        self.region_name = region_name or os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
        self.max_tokens = max_tokens
        self.temperature = temperature

    def generate_json(self, system_prompt: str, user_prompt: str) -> dict[str, Any]:
        if not self.region_name:
            raise RuntimeError("AWS_REGION or AWS_DEFAULT_REGION must be set for Amazon Bedrock")

        import boto3

        client = boto3.client("bedrock-runtime", region_name=self.region_name)
        response = client.converse(
            modelId=self.model_id,
            system=[{"text": system_prompt}],
            messages=[{"role": "user", "content": [{"text": user_prompt}]}],
            inferenceConfig={
                "maxTokens": self.max_tokens,
                "temperature": self.temperature,
            },
        )
        text = _message_text(response)
        return _extract_json_object(text)


def _message_text(response: dict[str, Any]) -> str:
    content = response.get("output", {}).get("message", {}).get("content", [])
    return "".join(block.get("text", "") for block in content)


def _extract_json_object(text: str) -> dict[str, Any]:
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise ValueError("Bedrock response did not contain a JSON object")
    return json.loads(text[start : end + 1])
