# Claims Agent with Envoy and OPA

`envoy.yaml` sends every HTTP request through Envoy's `ext_authz` filter. The
filter calls the OPA-Envoy gRPC plugin on port 9191 and evaluates
`data.crm.claims_agent.allow`.

The request must provide these headers:

- `x-agent-name: Claims Agent`
- `x-mcp-tool: <CRM tool name>`

The example policy permits only the CRM tools listed in
`policy/crm/claims_agent/claims_agent_crm.rego`.

## Kubernetes

Deploy the self-contained example and forward the Envoy service locally:

```sh
kubectl apply -f envoy/kubernetes.yaml
kubectl rollout status deployment/claims-agent-crm
kubectl port-forward service/claims-agent-crm 10000:80
```

An allowed MCP tool reaches the demo CRM backend:

```sh
curl -i http://127.0.0.1:10000/mcp/call \
  -H 'x-agent-name: Claims Agent' \
  -H 'x-mcp-tool: crm.get_claim'
```

An unlisted tool is rejected with HTTP 403:

```sh
curl -i http://127.0.0.1:10000/mcp/call \
  -H 'x-agent-name: Claims Agent' \
  -H 'x-mcp-tool: crm.delete_customer'
```

Do not trust agent identity headers received directly from untrusted clients in
production. Strip them at the edge and populate identity from an authenticated
workload identity or trusted gateway metadata.

## WASM boundary

OPA-Envoy evaluates Rego with OPA's native evaluator; it does not execute the
standalone `policy.wasm` artifact emitted by `opa build --target wasm`. The
Kubernetes sidecar therefore mounts the same Rego source that produces the
Claims Agent WASM policy.

Validate the compiled WASM bundle separately with the repository's Rust runner:

```sh
make compile-wasm
cargo run --quiet --bin check-policy -- \
  build/wasm/claims_agent_crm.tar.gz \
  crm/claims_agent/allow \
  < policy/testdata/claims_agent_crm_envoy_allowed.json
```