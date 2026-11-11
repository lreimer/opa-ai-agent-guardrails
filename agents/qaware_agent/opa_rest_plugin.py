"""Google ADK plugin that enforces the QAware OPA policy through the REST API."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx
from google.adk.agents.callback_context import CallbackContext
from google.adk.models.llm_request import LlmRequest
from google.adk.models.llm_response import LlmResponse
from google.adk.plugins.base_plugin import BasePlugin
from google.adk.tools.base_tool import BaseTool
from google.adk.tools.tool_context import ToolContext
from google.genai import types

logger = logging.getLogger(__name__)

DEFAULT_OPA_URL = "http://127.0.0.1:8181"
ALLOW_QUERY = "/v1/data/agents/qaware/allow"
DENY_REASONS_QUERY = "/v1/data/agents/qaware/deny_reasons"


class OpaRestGuardrailsPlugin(BasePlugin):
    """Evaluates the QAware policy over HTTP before and after each model and tool call.

    The policy input follows the same phase-specific contract as the WASM plugin.
    Any OPA request error, malformed response, or decision other than ``true``
    blocks the call (fail closed).
    """

    def __init__(
        self,
        opa_url: str | None = None,
        timeout: float | None = None,
        name: str = "opa_rest_guardrails",
    ) -> None:
        super().__init__(name=name)
        self._opa_url = (opa_url or os.getenv("QAWARE_OPA_URL", DEFAULT_OPA_URL)).rstrip("/")
        request_timeout = (
            timeout if timeout is not None else float(os.getenv("QAWARE_OPA_TIMEOUT_SECONDS", "1.0"))
        )
        self._client = httpx.AsyncClient(timeout=request_timeout)

    async def before_model_callback(
        self, *, callback_context: CallbackContext, llm_request: LlmRequest
    ) -> LlmResponse | None:
        decision_input = {
            "phase": "before_model",
            "agent": callback_context.agent_name,
            "model": llm_request.model,
            "text": _latest_user_text(llm_request.contents),
        }
        if await self._allowed(decision_input):
            return None
        return _blocked_llm_response(
            await self._message("The request was blocked by the OPA guardrail policy.", decision_input)
        )

    async def after_model_callback(
        self, *, callback_context: CallbackContext, llm_response: LlmResponse
    ) -> LlmResponse | None:
        decision_input = {
            "phase": "after_model",
            "agent": callback_context.agent_name,
            "model": llm_response.model_version,
            "text": _content_text(llm_response.content),
        }
        if await self._allowed(decision_input):
            return None
        return _blocked_llm_response(
            await self._message("The model response was withheld by the OPA guardrail policy.", decision_input)
        )

    async def before_tool_callback(
        self, *, tool: BaseTool, tool_args: dict[str, Any], tool_context: ToolContext
    ) -> dict | None:
        decision_input = {
            "phase": "before_tool",
            "agent": tool_context.agent_name,
            "tool": tool.name,
            "arguments": _to_json(tool_args),
        }
        if await self._allowed(decision_input):
            return None
        message = await self._message(
            f"Call to tool '{tool.name}' was blocked by the OPA guardrail policy.", decision_input
        )
        return _blocked_tool_result(message)

    async def after_tool_callback(
        self, *, tool: BaseTool, tool_args: dict[str, Any], tool_context: ToolContext, result: dict
    ) -> dict | None:
        decision_input = {
            "phase": "after_tool",
            "agent": tool_context.agent_name,
            "tool": tool.name,
            "arguments": _to_json(tool_args),
            "result": _to_json(result),
        }
        if await self._allowed(decision_input):
            return None
        message = await self._message(
            f"Result of tool '{tool.name}' was withheld by the OPA guardrail policy.", decision_input
        )
        return _blocked_tool_result(message)

    async def close(self) -> None:
        await self._client.aclose()

    async def _allowed(self, decision_input: dict[str, Any]) -> bool:
        result = await self._evaluate(ALLOW_QUERY, decision_input)
        allowed = result is True
        if not allowed:
            logger.warning("OPA REST policy denied %s", decision_input["phase"])
        return allowed

    async def _message(self, default: str, decision_input: dict[str, Any]) -> str:
        reasons = await self._deny_reasons(decision_input)
        if not reasons:
            return default
        return default + "\n" + "\n".join(f"🚫 {reason}" for reason in reasons)

    async def _deny_reasons(self, decision_input: dict[str, Any]) -> list[str]:
        result = await self._evaluate(DENY_REASONS_QUERY, decision_input)
        if not isinstance(result, list):
            if result is not None:
                logger.error("OPA deny reasons response was not a list")
            return []
        return sorted(str(reason) for reason in result)

    async def _evaluate(self, query: str, decision_input: dict[str, Any]) -> Any:
        try:
            response = await self._client.post(
                f"{self._opa_url}{query}",
                json={"input": decision_input},
            )
            response.raise_for_status()
            body = response.json()
        except (httpx.HTTPError, ValueError):
            logger.exception("OPA REST evaluation failed for %s", decision_input["phase"])
            return None
        if not isinstance(body, dict) or "result" not in body:
            logger.error("OPA REST response for %s did not contain a result", decision_input["phase"])
            return None
        return body["result"]


def _content_text(content: types.Content | None) -> str:
    if not content or not content.parts:
        return ""
    return "\n".join(part.text for part in content.parts if part.text)


def _latest_user_text(contents: list[types.Content]) -> str:
    for content in reversed(contents):
        if content.role == "user" and (text := _content_text(content)):
            return text
    return ""


def _to_json(value: Any) -> Any:
    return json.loads(json.dumps(value, default=str))


def _blocked_llm_response(message: str) -> LlmResponse:
    return LlmResponse(content=types.Content(role="model", parts=[types.Part(text=message)]))


def _blocked_tool_result(message: str) -> dict:
    return {"status": "error", "error_message": message}
