package agents.qaware

import rego.v1

# Guardrails for the QAware agent (agents/qaware_agent). Same ADK plugin input contract as the
# CLC26 agent (see agents/qaware_agent/opa_plugin.py):
# {
#   "phase": "before_model" | "after_model" | "before_tool" | "after_tool",
#   "agent": "qaware_agent",
#   "model": "gemini-...",              # model phases only
#   "text": "...",                      # model phases: latest user prompt / model response text
#   "tool": "fetch_qaware_page",        # tool phases only
#   "arguments": { ... },               # tool phases only
#   "result": { ... }                   # after_tool only
# }
#
# Every guardrail contributes a human readable message to `deny_reasons`, and a call is only
# allowed if there is none. The plugin evaluates both entrypoints and shows the reasons to the user.

trusted_agents := {"qaware_agent", "qaware_web_search_agent"}

allowed_tools := {"fetch_qaware_page", "list_qaware_pages", "qaware_web_search_agent"}

allowed_hosts := {"qaware.de", "www.qaware.de"}

known_phases := {"before_model", "after_model", "before_tool", "after_tool"}

# The only email addresses the agent may hand out.
official_contacts := {"info@qaware.de", "jobs@qaware.de"}

phase := object.get(input, "phase", "")

text := object.get(input, "text", "")

tool_name := object.get(input, "tool", "")

arguments := object.get(input, "arguments", {})

# Everything the agent sees or produces in this phase, for checks that apply everywhere.
payload := json.marshal(object.remove(input, {"phase", "agent", "model"}))

default allow := false

allow if {
	phase in known_phases
	count(deny_reasons) == 0
}

# --- 1. Classic guardrails -------------------------------------------------------------------

deny_reasons contains "Unknown phase: the policy fails closed." if not phase in known_phases

deny_reasons contains msg if {
	not input.agent in trusted_agents
	msg := sprintf("Agent '%v' is not on the guest list.", [object.get(input, "agent", "")])
}

injection_patterns := [
	`(?i)ignore\s+(all\s+)?(previous|prior|above)\s+instructions`,
	`(?i)disregard\s+(all\s+)?(previous|prior|above)\s+instructions`,
	`(?i)ignoriere\s+(alle\s+)?(vorherigen|bisherigen|obigen)\s+(anweisungen|instruktionen)`,
	`(?i)reveal\s+(your\s+)?(system\s+prompt|instructions)`,
	`(?i)you\s+are\s+now\s+in\s+developer\s+mode`,
]

deny_reasons contains "Nice try! Prompt injection detected, the system prompt stays where it is." if {
	phase == "before_model"
	some pattern in injection_patterns
	regex.match(pattern, text)
}

secret_patterns := [
	`AIza[0-9A-Za-z_\-]{35}`,
	`gh[pousr]_[0-9A-Za-z]{36}`,
	`-----BEGIN [A-Z ]*PRIVATE KEY-----`,
]

deny_reasons contains "A secret was about to leak. Rotating keys live on stage is no fun." if {
	phase in {"after_model", "after_tool"}
	some pattern in secret_patterns
	regex.match(pattern, payload)
}

deny_reasons contains msg if {
	phase in {"before_tool", "after_tool"}
	not tool_name in allowed_tools
	msg := sprintf("Tool '%v' is not on the allow-list.", [tool_name])
}

deny_reasons contains msg if {
	phase == "before_tool"
	tool_name == "fetch_qaware_page"
	not safe_fetch_target
	msg := sprintf("fetch_qaware_page may only read qaware.de, not '%v'.", [object.get(arguments, "path_or_url", "")])
}

# Relative paths are resolved against https://www.qaware.de/ by the tool.
safe_fetch_target if {
	path := trim_space(object.get(arguments, "path_or_url", "/"))
	not contains(path, ":")
	not startswith(path, "//")
}

safe_fetch_target if {
	path := trim_space(object.get(arguments, "path_or_url", ""))
	match := regex.find_all_string_submatch_n(`^https://([^/:?#@]+)(?:[/?#]|$)`, path, 1)[0]
	lower(match[1]) in allowed_hosts
}

# --- 2. Fun, but real: guardrails for a recruiting and sales agent ---------------------------

# Holy wars: the agent stays neutral, there are no winners anyway.
holy_war_patterns := [
	`(?i)\btabs?\b.*\bspaces?\b|\bspaces?\b.*\btabs?\b`,
	`(?i)\bvim?\b.*\bemacs\b|\bemacs\b.*\bvim?\b`,
	`(?i)\bpineapple\b.*\bpizza\b|\bpizza\b.*\bpineapple\b|\bananas\b.*\bpizza\b|\bpizza\b.*\bananas\b`,
	`(?i)\bdark\s*mode\b.*\blight\s*mode\b|\blight\s*mode\b.*\bdark\s*mode\b`,
]

deny_reasons contains "Holy war detected. This agent is Switzerland: no opinion on tabs vs. spaces, vim vs. emacs or pineapple pizza." if {
	phase == "before_model"
	some pattern in holy_war_patterns
	regex.match(pattern, text)
}

# Ghostwriting: QAware wants to read the applicant's own words.
ghostwriting_patterns := [
	`(?i)\b(write|draft|generate|create|compose)\b.{0,40}\b(cover\s+letter|motivation(al)?\s+letter|job\s+application|application\s+letter)`,
	`(?i)\b(schreib|verfass|formulier|erstell)\w*\b.{0,40}\b(anschreiben|bewerbung|motivationsschreiben)`,
]

deny_reasons contains "Ghostwriting denied: QAware wants to read YOUR cover letter, not mine. Send it to jobs@qaware.de." if {
	phase == "before_model"
	some pattern in ghostwriting_patterns
	regex.match(pattern, text)
}

# Binding commitments: remember the Air Canada chatbot that invented a refund policy (Moffatt v.
# Air Canada, 2024). An agent must never hire anyone or promise salaries.
commitment_patterns := [
	`(?i)\byou('re|\s+are)\s+hired\b`,
	`(?i)\bwe\s+(hereby\s+)?(offer|guarantee|promise)\s+you\b`,
	`(?i)\bguaranteed\s+(a\s+)?(job|position|offer|interview|salary)\b`,
	`(?i)\b(du\s+bist|sie\s+sind)\s+(hiermit\s+)?eingestellt\b`,
	`(?i)\bwir\s+(garantieren|versprechen)\s+(dir|ihnen)\b`,
]

deny_reasons contains "The agent tried to make a binding commitment. Bots don't hire, humans do (remember the Air Canada chatbot ruling)." if {
	phase == "after_model"
	some pattern in commitment_patterns
	regex.match(pattern, text)
}

# Buzzword bingo: three or more buzzwords in one answer and the agent has to try again.
buzzwords := {
	"synergy", "synergies", "synergien", "rockstar", "ninja", "10x", "disruptive", "disruptiv",
	"paradigm shift", "game changer", "game-changer", "leverage", "low-hanging fruit",
	"move the needle", "best-of-breed", "holistic", "ganzheitlich", "blockchain", "web3",
}

found_buzzwords contains word if {
	some word in buzzwords
	regex.match(sprintf(`(?i)(^|[^a-z0-9])%s([^a-z0-9]|$)`, [word]), text)
}

deny_reasons contains msg if {
	phase == "after_model"
	count(found_buzzwords) >= 3
	msg := sprintf("Buzzword bingo! %v buzzwords found (%v). Please answer like a human.", [
		count(found_buzzwords),
		concat(", ", sort(found_buzzwords)),
	])
}

# PII: only the official contact addresses may be shared, no personal email addresses.
leaked_emails contains email if {
	some match in regex.find_all_string_submatch_n(`[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}`, text, -1)
	email := lower(match[0])
	not email in official_contacts
}

deny_reasons contains msg if {
	phase == "after_model"
	count(leaked_emails) > 0
	msg := sprintf("Personal data detected (%v). Please use info@qaware.de or jobs@qaware.de.", [
		concat(", ", sort(leaked_emails)),
	])
}

# Rickroll protection: applies to prompts, tool arguments, tool results and responses alike.
rickroll_patterns := [`dQw4w9WgXcQ`, `(?i)never\s+gonna\s+give\s+you\s+up`]

deny_reasons contains "Rickroll detected. OPA is never gonna give you up, but it will let this request down." if {
	some pattern in rickroll_patterns
	regex.match(pattern, payload)
}
