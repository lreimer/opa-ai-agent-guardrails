# GitHub MCP Policy for Coding Agents

[github_mcp.rego](github_mcp.rego) guards the tool calls coding agents (Claude, GitHub Copilot) make to the GitHub
MCP server. It is evaluated as WASM by the Rust [check-policy](../../../src/bin/check_policy.rs) binary
(`make test-rust-hook`), and can also be used with the generic Python and Node.js hooks in [tools](../../../tools).

- Package: `coding.github_mcp`
- Query / WASM entrypoint: `data.coding.github_mcp.allow` / `coding/github_mcp/allow`

## Input

```json
{
  "agent": "Claude",
  "server": "github",
  "tool": "mcp_github_mcp_se_create_or_update_file",
  "arguments": { "owner": "example", "repo": "widgets", "branch": "feature/update-readme", "path": "README.md" },
  "user_approved": true
}
```

## Implemented Guardrails

| Guardrail | Rule |
|-----------|------|
| Deny by default | `allow` is `false` unless one of the rules below matches. |
| Trusted agents | Only `Claude`, `Copilot` and `GitHub Copilot` may call tools. |
| GitHub only | The call must target a GitHub MCP server (`github`, `mcp_github`, `github-mcp-server`) or a tool prefixed with `mcp_github_`. |
| Read tools allowed | Read-only tools (`get_*`, `list_*`, `search_*`, `issue_read`, `pull_request_read`, ...) are always allowed. |
| Writes need approval | Write tools (comments, branches, files, pull requests, reviews) require `user_approved == true`. |
| Protected branches | `create_or_update_file` and `push_files` may never write directly to `main` or `master` (`branch` or `ref`), even with approval. |
| Unknown tools denied | Tools that are neither on the read nor on the write list are denied, e.g. deleting repositories. |

## Test

```bash
make test-github-mcp       # read allowed, approved feature branch write allowed, approved write to main denied
make test-rust-hook        # same decisions via the WASM policy and the Rust binary
make eval-github-mcp-read  # or eval-github-mcp-write / eval-github-mcp-denied
```

Test inputs: [github_mcp_read_allowed.json](../../testdata/github_mcp_read_allowed.json),
[github_mcp_write_allowed.json](../../testdata/github_mcp_write_allowed.json),
[github_mcp_denied.json](../../testdata/github_mcp_denied.json).
