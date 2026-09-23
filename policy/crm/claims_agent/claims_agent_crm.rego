package crm.claims_agent

import rego.v1

# Allow only Claims Agent calls to the CRM tools needed to investigate and
# update customer claim records. Direct input uses agent/tool fields; Envoy
# ext_authz input supplies the same values as x-agent-name/x-mcp-tool headers.
allowed_tools := {
	"crm.get_customer",
	"crm.get_claim",
	"crm.list_customer_claims",
	"crm.search_claims",
	"crm.add_claim_note",
	"crm.update_claim_status",
}

http_request := object.get(object.get(object.get(input, "attributes", {}), "request", {}), "http", {})

request_headers := object.get(http_request, "headers", {})

agent_name := object.get(input, "agent", object.get(request_headers, "x-agent-name", ""))

tool_name := object.get(input, "tool", object.get(request_headers, "x-mcp-tool", ""))

default allow := false

allow if {
	agent_name == "Claims Agent"
	tool_name in allowed_tools
}
