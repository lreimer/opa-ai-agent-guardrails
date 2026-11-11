# Document Authorization Policy

[admin_file.rego](admin_file.rego) is a minimal attribute-based access control example that decides whether a
user may access a document.

- Package: `authz`
- Query / WASM entrypoint: `data.authz.allow` / `authz/allow`

## Input

```json
{
  "user": { "id": "user-100", "role": "claims_adjuster" },
  "document": { "owner_id": "user-100" }
}
```

## Implemented Guardrails

| Guardrail | Rule |
|-----------|------|
| Deny by default | `allow` is `false` unless one of the rules below matches. |
| Admin access | Users with the role `admin` may access every document. |
| Owner access | Users may access documents they own (`user.id == document.owner_id`). |

## Test

```bash
make test-authz         # admin and owner are allowed, everybody else is denied
make eval-authz-admin   # or eval-authz-owner / eval-authz-denied
```

Test inputs: [admin_file_admin.json](../testdata/admin_file_admin.json),
[admin_file_owner.json](../testdata/admin_file_owner.json),
[admin_file_denied.json](../testdata/admin_file_denied.json).

## OPA Server REST API

Start OPA with this policy loaded:

```bash
opa run --server --addr 127.0.0.1:8181 policy/authz/admin_file.rego
```

In another terminal, POST the existing fixtures to the data API. The REST request wraps the policy input in an
`input` field; `jq` adds that wrapper without changing the fixtures used by `opa eval`.

```bash
for fixture in policy/testdata/admin_file_admin.json \
               policy/testdata/admin_file_owner.json \
               policy/testdata/admin_file_denied.json; do
  printf '%s: ' "$fixture"
  jq -c '{input: .}' "$fixture" |
    curl --silent --show-error --fail-with-body \
      -H 'Content-Type: application/json' \
      --data-binary @- \
      http://127.0.0.1:8181/v1/data/authz/allow
  printf '\n'
done
```

The responses contain `{"result":true}` for the admin and owner fixtures and `{"result":false}` for the denied
fixture. The REST API returns the same policy decision as `opa eval`, but the caller now depends on the OPA server
being reachable.
