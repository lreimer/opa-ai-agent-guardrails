# Hook Registration (.claude/settings.json)

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
