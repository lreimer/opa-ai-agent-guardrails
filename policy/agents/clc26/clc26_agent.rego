package agents.clc26

import rego.v1

# ADK plugin input contract (see agents/clc26_agent/opa_plugin.py):
# {
#   "phase": "before_model" | "after_model" | "before_tool" | "after_tool",
#   "agent": "clc26_agent",
#   "model": "gemini-...",              # model phases only
#   "text": "...",                      # model phases: latest user prompt / model response text
#   "tool": "fetch_clc_page",           # tool phases only
#   "arguments": { ... },               # tool phases only
#   "result": { ... }                   # after_tool only
# }
trusted_agents := {"clc26_agent", "clc26_web_search_agent"}

allowed_tools := {"fetch_clc_page", "clc26_web_search_agent"}

allowed_hosts := {"clc-conference.eu", "www.clc-conference.eu"}

# Simple prompt injection markers checked on the latest user prompt.
injection_patterns := [
	`(?i)ignore\s+(all\s+)?(previous|prior|above)\s+instructions`,
	`(?i)disregard\s+(all\s+)?(previous|prior|above)\s+instructions`,
	`(?i)reveal\s+(your\s+)?(system\s+prompt|instructions)`,
	`(?i)you\s+are\s+now\s+in\s+developer\s+mode`,
]

# Secrets that must never leave the agent, neither via model output nor tool results.
secret_patterns := [
	`AIza[0-9A-Za-z_\-]{35}`,
	`gh[pousr]_[0-9A-Za-z]{36}`,
	`-----BEGIN [A-Z ]*PRIVATE KEY-----`,
]

phase := object.get(input, "phase", "")

text := object.get(input, "text", "")

tool_name := object.get(input, "tool", "")

arguments := object.get(input, "arguments", {})

default allow := false

allow if {
	phase == "before_model"
	trusted_agent
	not prompt_injection
}

allow if {
	phase == "after_model"
	trusted_agent
	not contains_secret(text)
}

allow if {
	phase == "before_tool"
	trusted_agent
	tool_name in allowed_tools
	safe_tool_arguments
}

allow if {
	phase == "after_tool"
	trusted_agent
	tool_name in allowed_tools
	not contains_secret(json.marshal(object.get(input, "result", {})))
}

trusted_agent if input.agent in trusted_agents

prompt_injection if {
	some pattern in injection_patterns
	regex.match(pattern, text)
}

contains_secret(value) if {
	some pattern in secret_patterns
	regex.match(pattern, value)
}

safe_tool_arguments if tool_name != "fetch_clc_page"

# Relative paths are resolved against https://clc-conference.eu/ by the tool.
safe_tool_arguments if {
	tool_name == "fetch_clc_page"
	path := trim_space(object.get(arguments, "path_or_url", "/"))
	not contains(path, ":")
	not startswith(path, "//")
}

safe_tool_arguments if {
	tool_name == "fetch_clc_page"
	path := trim_space(object.get(arguments, "path_or_url", ""))
	match := regex.find_all_string_submatch_n(`^https://([^/:?#@]+)(?:[/?#]|$)`, path, 1)[0]
	lower(match[1]) in allowed_hosts
}
