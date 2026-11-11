package coding.copilot_prompt

import rego.v1

# Checks prompts submitted to GitHub Copilot before they are sent to the model. Evaluated as WASM by
# the Copilot hook in .github/hooks/opa-prompt-guard, which builds this input:
# { "prompt": "..." }
#
# Every guardrail contributes a message to `deny_reasons`, a prompt is only allowed if there is none.

prompt := object.get(input, "prompt", "")

default allow := false

allow if {
	is_string(input.prompt)
	count(deny_reasons) == 0
}

deny_reasons contains "The prompt is missing or not a string, the policy fails closed." if not is_string(input.prompt)

injection_patterns := [
	`(?i)\b(ignore|disregard|forget|override)\s+(all\s+|any\s+)?(of\s+)?(the\s+|your\s+)?(previous|prior|above|earlier|system)\s+(instructions|prompts?|rules)`,
	`(?i)\b(reveal|print|show|output|repeat|leak)\s+(me\s+)?(your|the)\s+(system\s+prompt|hidden\s+instructions|initial\s+instructions)`,
	`(?i)\byou\s+are\s+now\s+(in\s+)?(developer|dan|god|jailbreak|unrestricted)\s+mode`,
	`(?i)\bdo\s+anything\s+now\b`,
	`(?i)\bignoriere\s+(alle\s+)?(vorherigen|bisherigen|obigen)\s+(anweisungen|instruktionen|regeln)`,
]

deny_reasons contains "Prompt injection or jailbreak attempt detected." if {
	some pattern in injection_patterns
	regex.match(pattern, prompt)
}

# Invisible Unicode tag characters, zero-width spaces and bidi overrides can smuggle hidden instructions.
hidden_unicode_pattern := `[\x{E0000}-\x{E007F}\x{200B}\x{2060}\x{FEFF}\x{202A}-\x{202E}\x{2066}-\x{2069}]`

deny_reasons contains "Hidden or invisible Unicode characters detected (ASCII smuggling)." if {
	regex.match(hidden_unicode_pattern, prompt)
}

secret_patterns := [
	`AKIA[0-9A-Z]{16}`,
	`AIza[0-9A-Za-z_\-]{35}`,
	`gh[pousr]_[0-9A-Za-z]{36}`,
	`github_pat_[0-9A-Za-z_]{82}`,
	`xox[baprs]-[0-9A-Za-z\-]{10,}`,
	`\bsk-(proj-|ant-)?[A-Za-z0-9_\-]{20,}`,
	`-----BEGIN [A-Z ]*PRIVATE KEY-----`,
]

deny_reasons contains "The prompt contains a secret or credential that must not be sent to the model." if {
	some pattern in secret_patterns
	regex.match(pattern, prompt)
}

exfiltration_patterns := [
	`(?i)\b(cat|print|show|read|dump|upload|send|copy|exfiltrate|post)\b.{0,60}(~/\.ssh|\bid_(rsa|ecdsa|ed25519)\b|\.aws/credentials|\.netrc|\.npmrc|\.pypirc|\.docker/config\.json|\.kube/config|\.git-credentials)`,
	`(?i)\b(send|upload|post|exfiltrate|leak|forward)\b.{0,60}\b(secrets?|credentials|api[ _-]?keys?|tokens?|passwords?|env(ironment)?\s+variables|\.env)\b.{0,60}\b(to|via|into)\b.{0,40}(https?://|webhook|pastebin|discord|telegram|ngrok|external|remote)`,
	`(?i)\b(secrets?|credentials|api[ _-]?keys?|tokens?|passwords?|env(ironment)?\s+variables|\.env)\b.{0,60}\b(send|upload|post|exfiltrate|leak|forward)\b.{0,40}(https?://|webhook|pastebin|discord|telegram|ngrok)`,
]

deny_reasons contains "Request to read or exfiltrate credentials or secrets detected." if {
	some pattern in exfiltration_patterns
	regex.match(pattern, prompt)
}

destructive_patterns := [
	`\brm\s+-[a-zA-Z]*(rf|fr)[a-zA-Z]*\s+(--no-preserve-root\s+)?(/\*?|~/?|\$HOME/?)(\s|$|["'])`,
	`\bmkfs(\.[a-z0-9]+)?\s+/dev/`,
	`\bdd\s+if=.{0,60}\bof=/dev/(sd|nvme|disk|hd)`,
	`:\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:`,
	`\b(curl|wget)\b[^|\n]{0,200}\|\s*(sudo\s+)?(ba|z)?sh\b`,
	`\bchmod\s+-R\s+777\s+/(\s|$)`,
	`\bgit\s+push\b.{0,40}(--force\b|\s-f\b).{0,40}\b(main|master)\b`,
]

deny_reasons contains "Destructive or unsafe shell command detected." if {
	some pattern in destructive_patterns
	regex.match(pattern, prompt)
}

malware_pattern := `(?i)\b(write|create|build|generate|develop|code|implement)\b.{0,40}\b(ransomware|keylogger|credential\s+stealer|info\s?stealer|botnet|rootkit|cryptojacker|backdoor)\b`

deny_reasons contains "Request to create malware detected." if {
	regex.match(malware_pattern, prompt)
}
