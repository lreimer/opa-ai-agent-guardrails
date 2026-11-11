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
