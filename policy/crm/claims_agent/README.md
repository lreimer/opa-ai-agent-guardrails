# CRM Policy for the Claims Agent

[claims_agent_crm.rego](claims_agent_crm.rego) restricts which CRM tools an insurance claims agent may call. It works
both with direct input and with Envoy `ext_authz` requests (see [envoy](../../../envoy)).

- Package: `crm.claims_agent`
- Query / WASM entrypoint: `data.crm.claims_agent.allow` / `crm/claims_agent/allow`

## Input

Direct input:

```json
{ "agent": "Claims Agent", "tool": "crm.get_claim" }
```

Envoy `ext_authz` input, with agent and tool passed as `x-agent-name` and `x-mcp-tool` headers:

```json
{
  "attributes": {
    "request": {
      "http": {
        "method": "POST",
        "path": "/mcp/call",
        "headers": { "x-agent-name": "Claims Agent", "x-mcp-tool": "crm.get_claim" }
      }
    }
  }
}
```

## Implemented Guardrails

| Guardrail | Rule |
|-----------|------|
| Deny by default | `allow` is `false` unless the rule below matches. |
| Single trusted agent | Only the agent named `Claims Agent` may call CRM tools. |
| Least privilege tool allow-list | Only `crm.get_customer`, `crm.get_claim`, `crm.list_customer_claims`, `crm.search_claims`, `crm.add_claim_note` and `crm.update_claim_status` are allowed. Everything else, e.g. deleting customers or exporting data, is denied. |
| Same decision for both entry paths | Direct `agent`/`tool` fields take precedence, otherwise the Envoy headers are used. |

## Test

```bash
make test-crm      # direct allowed, direct denied and Envoy allowed
make eval-allowed  # or eval-denied
```

Test inputs: [claims_agent_crm_allowed.json](../../testdata/claims_agent_crm_allowed.json),
[claims_agent_crm_denied.json](../../testdata/claims_agent_crm_denied.json),
[claims_agent_crm_envoy_allowed.json](../../testdata/claims_agent_crm_envoy_allowed.json).
