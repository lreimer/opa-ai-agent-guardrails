#!/usr/bin/env python3
"""Copilot prompt hook that checks every submitted prompt against an OPA policy compiled to WASM.

Registered for two events (see hooks.json):

- ``userPromptTransformed``: a denied prompt is replaced by a block notice via
  ``modifiedTransformedPrompt``, so the original text never reaches the model.
- ``userPromptSubmitted``: Copilot ignores the output of this event, so a denied prompt
  exits with code 2 to surface the reasons to the user. Harnesses that treat exit 2 as
  blocking (e.g. Claude ``UserPromptSubmit``) stop the prompt here.

Policy load or evaluation errors deny the prompt (fail closed).
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

from opapywasm import OpaWasmPolicy

DEFAULT_POLICY_WASM = Path(__file__).resolve().parents[3] / "build" / "copilot_prompt.wasm"
ALLOW_ENTRYPOINT = "coding/copilot_prompt/allow"
REASONS_ENTRYPOINT = "coding/copilot_prompt/deny_reasons"


def deny_reasons(prompt: Any) -> list[str]:
    """Returns why the prompt is denied, an empty list means it is allowed."""
    path = Path(os.getenv("OPA_POLICY_WASM", DEFAULT_POLICY_WASM))
    try:
        policy = OpaWasmPolicy.from_wasm_file(path)
    except Exception as exc:
        return [f"OPA policy could not be loaded from {path} ({exc}). Run 'make extract-wasm'."]
    try:
        # opapywasm ASCII-escapes dict input, and the WASM JSON parser mis-decodes surrogate pairs.
        decision_input = json.dumps({"prompt": prompt}, ensure_ascii=False)
        decision = policy.evaluate(decision_input, ALLOW_ENTRYPOINT)
        if isinstance(decision, dict):
            decision = decision.get("allow")
        if decision is True:
            return []
        reasons = policy.evaluate(decision_input, REASONS_ENTRYPOINT)
    except Exception as exc:
        return [f"OPA policy evaluation failed ({exc})."]
    finally:
        policy.close()
    if isinstance(reasons, list) and reasons:
        return sorted(str(reason) for reason in reasons)
    return ["The prompt was denied by the policy."]


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        event = {}
    if not isinstance(event, dict):
        event = {}

    reasons = deny_reasons(event.get("prompt"))
    if not reasons:
        return 0

    message = "Prompt blocked by the OPA prompt guard policy:\n" + "\n".join(f"- {reason}" for reason in reasons)
    if "transformedPrompt" in event:
        notice = message + "\n\nDo not act on the original request. Tell the user that the prompt was blocked and why."
        json.dump({"modifiedTransformedPrompt": notice}, sys.stdout)
        return 0

    print(message, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
