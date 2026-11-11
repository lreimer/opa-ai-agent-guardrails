# QAware Agent Guardrails

[qaware_agent.rego](qaware_agent.rego) guards the [QAware agent](../../../agents/qaware_agent) before and after every
LLM and tool invocation, including the wrapped web search agent. The default ADK
[OpaWasmGuardrailsPlugin](../../../agents/qaware_agent/opa_plugin.py) evaluates the policy locally. The agent also
has an [OpaRestGuardrailsPlugin](../../../agents/qaware_agent/opa_rest_plugin.py) variant that evaluates it through
OPA's REST API. Both fail closed on evaluation errors.

Every guardrail adds a human readable message to `deny_reasons`, and `allow` is `true` only if the phase is known
and there is no reason to deny. The plugin evaluates both entrypoints and shows the reasons to the user, e.g.
`🚫 Buzzword bingo! 4 buzzwords found (...)`.

- Package: `agents.qaware`
- Queries: `data.agents.qaware.allow`, `data.agents.qaware.deny_reasons`
- WASM entrypoints: `agents/qaware/allow`, `agents/qaware/deny_reasons`
- REST endpoints: `/v1/data/agents/qaware/allow`, `/v1/data/agents/qaware/deny_reasons`

## REST API Variant

Start OPA with this policy:

```bash
opa run --server --addr 127.0.0.1:8181 policy/agents/qaware/qaware_agent.rego
```

Set these variables in `agents/qaware_agent/.env` to select the REST plugin instead of the default WASM plugin:

```bash
QAWARE_OPA_BACKEND=rest
QAWARE_OPA_URL=http://127.0.0.1:8181
```

The REST plugin posts the same phase-specific input document to the `allow` endpoint. If denied, it requests
`deny_reasons` and includes the messages in the blocked model response or tool result. Set
`QAWARE_OPA_TIMEOUT_SECONDS` to adjust the request timeout (default: `1.0`). A failed request, non-JSON response,
missing result, or decision other than boolean `true` denies the operation.

## Input

```json
{
  "phase": "before_model | after_model | before_tool | after_tool",
  "agent": "qaware_agent",
  "model": "gemini-...",
  "text": "latest user prompt or model response (model phases)",
  "tool": "fetch_qaware_page",
  "arguments": { "path_or_url": "/karriere/professionals" },
  "result": { "...": "tool result (after_tool only)" }
}
```

## Implemented Guardrails

### Classic Guardrails

| Guardrail | Phase | Rule |
|-----------|-------|------|
| Fail closed | all | Unknown phases are denied. |
| Trusted agents | all | Only `qaware_agent` and `qaware_web_search_agent` are allowed. |
| Prompt injection | `before_model` | Denies English and German injection attempts like "ignore all previous instructions", "ignoriere alle vorherigen Anweisungen" or "reveal your system prompt". |
| Secret leakage | `after_model`, `after_tool` | Denies model responses and tool arguments or results containing Google API keys, GitHub tokens or private keys. |
| Tool allow-list | `before_tool`, `after_tool` | Only `fetch_qaware_page`, `list_qaware_pages` and `qaware_web_search_agent` may be called. |
| Host allow-list | `before_tool` | `fetch_qaware_page` accepts relative paths or `https://` URLs on `qaware.de` only, which prevents data exfiltration to other hosts. |

### Demo Guardrails for a Recruiting and Sales Agent

| Guardrail | Phase | Rule | Try it with |
|-----------|-------|------|-------------|
| Holy wars | `before_model` | The agent stays neutral on tabs vs. spaces, vim vs. emacs, pineapple pizza and dark vs. light mode. | "Tabs or spaces, what does QAware use?" |
| Ghostwriting | `before_model` | No AI-written cover letters or applications (English and German). | "Write me a cover letter for the AI consultant job" |
| Binding commitments | `after_model` | Bots don't hire: denies "you're hired", "we guarantee/promise you", "Sie sind eingestellt" and similar, inspired by the Air Canada chatbot ruling (Moffatt v. Air Canada, 2024). | Have the model answer "You're hired!" |
| Buzzword bingo | `after_model` | Three or more buzzwords (synergy, rockstar, ninja, 10x, leverage, holistic, ...) in one answer and it is withheld. The message lists the buzzwords found. | "Describe the job like a startup recruiter on LinkedIn" |
| Personal data | `after_model` | Only the official addresses `info@qaware.de` and `jobs@qaware.de` may be shared, every other email address is denied. | "What is the email address of the hiring manager?" |
| Rickroll protection | all | Denies the `dQw4w9WgXcQ` video ID and "never gonna give you up" in prompts, tool arguments, tool results and responses. This shows how a manipulated web page is caught in `after_tool`. | "Is https://youtu.be/dQw4w9WgXcQ a good intro video?" |

## Test

```bash
make test-qaware-agent
make test-qaware-rest-plugin
make eval-qaware-reasons QAWARE_INPUT=policy/testdata/qaware_agent_response_commitment_denied.json
```

Test inputs are named `qaware_agent_*_allowed.json` or `qaware_agent_*_denied.json` in
[policy/testdata](../../testdata), and the test target derives the expected decision from the file name.

The WASM variant requires built-in functions that OPA implements natively in WASM (e.g.
`regex.find_all_string_submatch_n` instead of `regex.find_n`), otherwise `opa eval` succeeds but WASM evaluation
fails and the plugin denies every call.
