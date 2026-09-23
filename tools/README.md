# Tools and Hooks

In Claude Code registrieren (.claude/settings.json)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python check_policy.py"
          }
        ]
      }
    ]
  }
}
```

## Welche Variante wählen?
- Node.js SDK (@open-policy-agent/opa-wasm): Standardwahl, wenn Sie ohnehin in einer JS/TS-Umgebung arbeiten.
- Python (opa-py-wasm / wasmtime): Bietet sich an, wenn Ihr KI-Agent oder Ihre Skripte in Python geschrieben sind.
- Rust Binary (wasmtime): Perfekt für CI/CD-Pipelines oder CLI-Umgebungen, da das fertige Binary keine externen Runtimes benötigt und Kaltstartzeiten im einstelligen Millisekundenbereich erreicht.