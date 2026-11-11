"""Google ADK plugin that enforces an OPA policy compiled to WASM around every LLM and tool call."""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from google.adk.agents.callback_context import CallbackContext
from google.adk.models.llm_request import LlmRequest
from google.adk.models.llm_response import LlmResponse
from google.adk.plugins.base_plugin import BasePlugin
from google.adk.tools.base_tool import BaseTool
from google.adk.tools.tool_context import ToolContext
from google.genai import types
from opapywasm import OpaWasmPolicy

logger = logging.getLogger(__name__)

DEFAULT_POLICY_WASM = Path(__file__).resolve().parents[2] / "build" / "clc26_agent.wasm"
DEFAULT_ENTRYPOINT = "agents/clc26/allow"


class OpaWasmGuardrailsPlugin(BasePlugin):
    """Evaluates an OPA WASM policy before and after each model and tool invocation.

    The policy receives an input document with a ``phase`` (``before_model``,
    ``after_model``, ``before_tool`` or ``after_tool``), the ``agent`` name and
    phase-specific fields (``model``/``text`` or ``tool``/``arguments``/``result``).
    It must return ``true`` (or ``{"allow": true}``) to permit the call. Any
    other decision, or an evaluation error, blocks the call (fail closed).
    """

    def __init__(
        self,
        policy_path: str | Path | None = None,
        entrypoint: str | None = DEFAULT_ENTRYPOINT,
        name: str = "opa_wasm_guardrails",
    ) -> None:
        super().__init__(name=name)
        path = Path(policy_path or os.getenv("OPA_POLICY_WASM", DEFAULT_POLICY_WASM))
        if not path.is_file():
            raise FileNotFoundError(f"OPA WASM policy not found at {path}. Run 'make extract-wasm' first.")
        self._policy = OpaWasmPolicy.from_wasm_file(path)
        self._entrypoint = entrypoint

    async def before_model_callback(
        self, *, callback_context: CallbackContext, llm_request: LlmRequest
    ) -> LlmResponse | None:
        decision_input = {
            "phase": "before_model",
            "agent": callback_context.agent_name,
            "model": llm_request.model,
            "text": _latest_user_text(llm_request.contents),
        }
        if self._allowed(decision_input):
            return None
        return _blocked_llm_response("The request was blocked by the OPA guardrail policy.")

    async def after_model_callback(
        self, *, callback_context: CallbackContext, llm_response: LlmResponse
    ) -> LlmResponse | None:
        decision_input = {
            "phase": "after_model",
            "agent": callback_context.agent_name,
            "model": llm_response.model_version,
            "text": _content_text(llm_response.content),
        }
        if self._allowed(decision_input):
            return None
        return _blocked_llm_response("The model response was withheld by the OPA guardrail policy.")

    async def before_tool_callback(
        self, *, tool: BaseTool, tool_args: dict[str, Any], tool_context: ToolContext
    ) -> dict | None:
        decision_input = {
            "phase": "before_tool",
            "agent": tool_context.agent_name,
            "tool": tool.name,
            "arguments": _to_json(tool_args),
        }
        if self._allowed(decision_input):
            return None
        return _blocked_tool_result(f"Call to tool '{tool.name}' was blocked by the OPA guardrail policy.")

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
        if self._allowed(decision_input):
            return None
        return _blocked_tool_result(f"Result of tool '{tool.name}' was withheld by the OPA guardrail policy.")

    async def close(self) -> None:
        self._policy.close()

    def _allowed(self, decision_input: dict[str, Any]) -> bool:
        try:
            decision = self._policy.evaluate(decision_input, self._entrypoint)
        except Exception:
            logger.exception("OPA policy evaluation failed for %s, denying", decision_input["phase"])
            return False
        if isinstance(decision, dict):
            decision = decision.get("allow")
        allowed = decision is True
        if not allowed:
            logger.warning("OPA policy denied %s", json.dumps(decision_input, default=str)[:1000])
        return allowed


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
