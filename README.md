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

## QAware Agent (Google ADK)

The [agents/qaware_agent](agents/qaware_agent) directory contains a second ADK agent that researches and answers
questions about [QAware GmbH](https://www.qaware.de/): service portfolio, expertise, project references and open
job positions. It discovers pages via the sitemap (`list_qaware_pages`), reads them with `fetch_qaware_page`
(restricted to `qaware.de`) and falls back to Google Search for everything else.

```bash
cp agents/qaware_agent/.env.example agents/qaware_agent/.env   # add your Gemini API key or Vertex AI project
make adk-web                                                   # open http://localhost:8000 and select qaware_agent
```

Use `QAWARE_AGENT_MODEL` to override the Gemini model. The QAware agent uses its local WASM policy by default; to
demonstrate the OPA REST API instead, start the OPA server and set `QAWARE_OPA_BACKEND=rest` in
`agents/qaware_agent/.env`:

```bash
opa run --server --addr 127.0.0.1:8181 policy/agents/qaware/qaware_agent.rego
```

Set `QAWARE_OPA_URL` if the server is listening elsewhere. This backend switch affects only QAware; CLC26 continues
to use WASM.

### Demo Guardrails

The [qaware_agent.rego](policy/agents/qaware/qaware_agent.rego) policy collects every violation as a human readable
message in `deny_reasons`, and `allow` is true only if there is none. The agent plugin shows these reasons instead
of a generic block message with either the default WASM backend or the optional REST backend. Besides the classic
guardrails (prompt injection, secrets, tool and host allow-lists), the policy contains a few rules that are fun to
demo live:

| Guardrail | Phase | Try it with |
|-----------|-------|-------------|
| Holy wars: the agent stays neutral | prompt | "Tabs or spaces, what does QAware use?" |
| Ghostwriting: no AI-written cover letters | prompt | "Write me a cover letter for the AI consultant job" |
| Binding commitments: bots don't hire (Air Canada chatbot ruling) | response | the model answers "You're hired!" |
| Buzzword bingo: 3 or more buzzwords and the answer is withheld | response | "Describe the job like a startup recruiter on LinkedIn" |
| PII: only `info@qaware.de` and `jobs@qaware.de` may be shared | response | "What is the email address of the hiring manager?" |
| Rickroll protection | all phases | "Is https://youtu.be/dQw4w9WgXcQ a good intro video?" |

Run `make test-qaware-agent` to test the policy (test inputs in [policy/testdata](policy/testdata) are named
`qaware_agent_*_allowed.json` or `qaware_agent_*_denied.json`), `make test-qaware-rest-plugin` to test the REST
client behavior, and show the reasons for a denied input with
`make eval-qaware-reasons QAWARE_INPUT=policy/testdata/qaware_agent_response_commitment_denied.json`.

## Policies

Each policy directory contains a README describing its input and implemented guardrails:

| Policy | Guards |
|--------|--------|
| [authz/admin_file.rego](policy/authz/README.md) | Document access for admins and owners |
| [crm/claims_agent](policy/crm/claims_agent/README.md) | CRM tool calls of an insurance claims agent, directly or via Envoy |
| [coding/github_mcp](policy/coding/github_mcp/README.md) | GitHub MCP tool calls of coding agents |
| [coding/copilot_prompt](policy/coding/copilot_prompt/README.md) | Prompts submitted to GitHub Copilot, via a Python hook |
| [agents/clc26](policy/agents/clc26/README.md) | The CLC26 conference ADK agent |
| [agents/qaware](policy/agents/qaware/README.md) | The QAware ADK agent, including the demo guardrails |

## Maintainer

M.-Leander Reimer (@lreimer), <mario-leander.reimer@qaware.de>

## License

This software is provided under the MIT open source license, read the `LICENSE` file for details.
