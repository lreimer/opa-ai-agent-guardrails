# CLC26 Agent Guardrails

[clc26_agent.rego](clc26_agent.rego) guards the [CLC26 conference agent](../../../agents/clc26_agent). The policy is
compiled to WASM and evaluated by the ADK [OpaWasmGuardrailsPlugin](../../../agents/clc26_agent/opa_plugin.py)
before and after every LLM and tool invocation, including the wrapped web search agent. Denied calls are replaced
with a policy message, and evaluation errors fail closed.

- Package: `agents.clc26`
- Query / WASM entrypoint: `data.agents.clc26.allow` / `agents/clc26/allow`

## Input

```json
{
  "phase": "before_model | after_model | before_tool | after_tool",
  "agent": "clc26_agent",
  "model": "gemini-...",
  "text": "latest user prompt or model response (model phases)",
  "tool": "fetch_clc_page",
  "arguments": { "path_or_url": "/programm.php" },
  "result": { "...": "tool result (after_tool only)" }
}
```

## Implemented Guardrails

| Guardrail | Phase | Rule |
|-----------|-------|------|
| Deny by default | all | `allow` is `false` for unknown phases and unless a rule below matches. |
| Trusted agents | all | Only `clc26_agent` and `clc26_web_search_agent` are allowed. |
| Prompt injection | `before_model` | Denies prompts like "ignore all previous instructions", "reveal your system prompt" or "you are now in developer mode". |
| Secret leakage | `after_model`, `after_tool` | Denies model responses and tool results containing Google API keys, GitHub tokens or private keys. |
| Tool allow-list | `before_tool`, `after_tool` | Only `fetch_clc_page` and `clc26_web_search_agent` may be called. |
| Host allow-list | `before_tool` | `fetch_clc_page` accepts relative paths or `https://` URLs on `clc-conference.eu` only, which prevents data exfiltration to other hosts. |

## Test

```bash
make test-clc26-agent
opa eval --format pretty --data policy/agents/clc26/clc26_agent.rego \
  --input policy/testdata/clc26_agent_tool_denied.json data.agents.clc26.allow
```

Test inputs: `clc26_agent_*.json` in [policy/testdata](../../testdata).
