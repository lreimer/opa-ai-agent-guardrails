# Open Policy Agent AI Guardrails

Demo repository for AI agent guardrails using OPA.

## CLC26 Conference Agent (Google ADK)

The [agents/clc26_agent](agents/clc26_agent) directory contains a Python [Google ADK](https://adk.dev/) agent
that researches and answers questions about the [CLC26 conference](https://clc-conference.eu/)
(11-12 November 2026, Mannheim). It reads the official conference website (programme, talks, tickets, FAQ)
and falls back to Google Search for everything else.

```bash
cp agents/clc26_agent/.env.example agents/clc26_agent/.env   # add your Gemini API key or Vertex AI project
make adk-web                                                 # open http://localhost:8000 and select clc26_agent
```

Use `ADK_WEB_PORT=9000 make adk-web` to change the port and `CLC26_AGENT_MODEL` to override the Gemini model.

### OPA Guardrails Plugin

The agent is wrapped in an ADK `App` with the [OpaWasmGuardrailsPlugin](agents/clc26_agent/opa_plugin.py),
which evaluates the [clc26_agent.rego](policy/agents/clc26/clc26_agent.rego) policy, compiled to WASM, with
[opa-py-wasm](https://pypi.org/project/opa-py-wasm/) before and after every LLM and tool invocation
(including the wrapped web search agent). The policy blocks prompt injection attempts, secrets in model
responses or tool results, unknown tools and `fetch_clc_page` calls to hosts other than `clc-conference.eu`.
Denied calls are replaced with a policy message, and evaluation errors fail closed.

`make adk-web` compiles the policy to `build/clc26_agent.wasm` first (requires the `opa` CLI). Use
`OPA_POLICY_WASM` to load a different policy, and run `make test-clc26-agent` to test it.

## Maintainer

M.-Leander Reimer (@lreimer), <mario-leander.reimer@qaware.de>

## License

This software is provided under the MIT open source license, read the `LICENSE` file for details.
