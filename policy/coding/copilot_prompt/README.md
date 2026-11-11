# Copilot Prompt Guard Policy

[copilot_prompt.rego](copilot_prompt.rego) checks every prompt submitted to GitHub Copilot for malicious content
before it reaches the model. It is evaluated as WASM by the Python Copilot hook in
[.github/hooks/opa-prompt-guard](../../../.github/hooks/opa-prompt-guard).

- Package: `coding.copilot_prompt`
- Query / WASM entrypoints: `data.coding.copilot_prompt.allow` / `coding/copilot_prompt/allow` and
  `coding/copilot_prompt/deny_reasons`

## Input

```json
{
  "prompt": "Add a unit test for the CRM policy."
}
```

## Implemented Guardrails

| Guardrail | Rule |
|-----------|------|
| Deny by default | `allow` is `false` if `prompt` is missing or not a string, or if any `deny_reasons` exist. |
| Prompt injection | Phrases such as "ignore all previous instructions", "reveal your system prompt" or "developer mode". |
| Hidden Unicode | Unicode tag characters, zero-width spaces and bidi overrides used for ASCII smuggling. |
| Secrets | AWS, Google, GitHub, Slack and OpenAI/Anthropic keys and private keys that would leak to the model. |
| Exfiltration | Reading credential files (`~/.ssh`, `.aws/credentials`, ...) or sending secrets to external endpoints. |
| Destructive commands | `rm -rf /`, `mkfs`, `dd` to devices, fork bombs, `curl \| sh`, `chmod -R 777 /`, force pushes to `main`. |
| Malware | Requests to write ransomware, keyloggers, credential stealers, rootkits or backdoors. |

## Copilot Hook

[hooks.json](../../../.github/hooks/opa-prompt-guard/hooks.json) runs
[check_prompt.py](../../../.github/hooks/opa-prompt-guard/check_prompt.py) with `uv` for two events:

- `userPromptTransformed`: a denied prompt is replaced with a block notice through `modifiedTransformedPrompt`, so the
  original text is never sent to the model.
- `userPromptSubmitted`: Copilot ignores command output for this event, so the hook exits with code `2` to show the
  deny reasons to the user.

Policy load or evaluation errors deny the prompt. Hook timeouts fail open in Copilot. Run `make extract-wasm` to build
`build/copilot_prompt.wasm` before you use the hook. Set `OPA_POLICY_WASM` to use a different module.

## Test

```bash
make test-copilot-prompt   # policy decisions with opa eval
make test-copilot-hook     # same fixtures through the Python hook and the WASM policy
```

Test inputs in [policy/testdata](../../testdata) are named `copilot_prompt_*allowed.json` or
`copilot_prompt_*denied.json`.
