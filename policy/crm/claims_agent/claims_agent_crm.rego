package crm.claims_agent

import rego.v1

# Allow only Claims Agent calls to the CRM tools needed to investigate and
# update customer claim records. Expected input: {"agent": string, "tool": string}.
allowed_tools := {
	"crm.get_customer",
	"crm.get_claim",
	"crm.list_customer_claims",
	"crm.search_claims",
	"crm.add_claim_note",
	"crm.update_claim_status",
}

default allow := false

allow if {
	input.agent == "Claims Agent"
	input.tool in allowed_tools
}
