# Copilot instructions

## Repository overview

This repository demonstrates Open Policy Agent (OPA) guardrails across several runtimes:

- `policy/` contains the Rego policies and `policy/testdata/` contains JSON inputs used to exercise them. Each policy's README documents its input shape and decisions.
- `agents/` contains two Google ADK Python agents. CLC26 uses an `OpaWasmGuardrailsPlugin`; QAware uses the same WASM approach by default and can select an `OpaRestGuardrailsPlugin` with `QAWARE_OPA_BACKEND=rest`. Policy evaluation failures deny the operation.
- `build/wasm/` contains OPA bundles compiled from Rego. The WASM plugins load extracted `.wasm` files from `build/`; the QAware REST plugin queries an OPA server. The Rust `check-policy` binary evaluates the GitHub MCP policy bundle, while `tools/` contains generic Node.js and Python hook examples.
- `envoy/` demonstrates using the claims-agent policy with Envoy `ext_authz`.

When changing a policy, keep its README, test fixtures, and any consuming plugin or hook consistent. Policy decisions are enforced at runtime through WASM, the OPA REST API, or directly by `opa eval`.

## Build and test

Prerequisites are the OPA CLI (`opa`), `uv` for Python dependencies, and Rust/Cargo for the Rust hook. `make` is used to orchestrate repository commands.

```bash
make test                 # all Rego policy tests
make test-crm             # CRM policy, including Envoy-shaped input
make test-authz
make test-github-mcp
make test-clc26-agent
make test-qaware-agent
make test-qaware-rest-plugin
make test-copilot-prompt
make test-copilot-hook     # run the Copilot prompt hook against the WASM policy
make test-rust-hook        # build and exercise the GitHub MCP WASM policy via Rust
make compile-wasm          # compile all Rego policies to bundles
make extract-wasm          # compile and extract WASM modules for the ADK agents
make rust-build            # build the check-policy binary
make python-sync           # install/sync Python dependencies
make adk-web               # run the ADK web UI (default port 8000)
```

Run one fixture directly by supplying its policy, input JSON, and query:

```bash
opa eval --format raw \
  --data policy/agents/clc26/clc26_agent.rego \
  --input policy/testdata/clc26_agent_tool_denied.json \
  data.agents.clc26.allow
```

Use the corresponding package query and fixture for another policy. For QAware denial explanations, use `make eval-qaware-reasons QAWARE_INPUT=<fixture.json>`. There is no repository-wide lint target in the Makefile.

## Policy and integration conventions

- The Rego package determines the query path and WASM entrypoint: for example, `package agents.clc26` exposes `data.agents.clc26.allow` and `agents/clc26/allow`. Keep the package, Makefile query, plugin entrypoint, and documentation aligned.
- Policy inputs for ADK agents use `phase` values `before_model`, `after_model`, `before_tool`, or `after_tool`, with phase-specific fields such as `text`, `tool`, `arguments`, and `result`. Update both the policy and the plugin's input construction when changing this contract.
- Policies should deny by default, including unknown phases/tools. ADK plugins also fail closed on policy evaluation errors.
- Put policy examples in `policy/testdata/`. The QAware test target derives expected decisions from `_allowed.json` and `_denied.json` filenames; the other policy targets enumerate their fixtures in the Makefile.
- Keep Rego built-ins compatible with OPA's WASM target. A policy can pass `opa eval` yet fail when compiled or evaluated as WASM; validate changes through the relevant WASM-consuming path when changing WASM behavior.
- QAware exposes an additional `deny_reasons` entrypoint. When changing its denial behavior, preserve the relationship between `allow`, `deny_reasons`, and the plugin's user-facing explanation.
- Agent-specific model overrides are `CLC26_AGENT_MODEL` and `QAWARE_AGENT_MODEL`; the ADK web port can be set with `ADK_WEB_PORT`. The plugins also accept `OPA_POLICY_WASM` to select a policy module.
- QAware's REST backend uses `QAWARE_OPA_URL` (default `http://127.0.0.1:8181`) and `QAWARE_OPA_TIMEOUT_SECONDS` (default `1.0`); the OPA server must load `policy/agents/qaware/qaware_agent.rego`.
