OPA ?= opa
UV ?= uv
WASM_DIR := build/wasm
REGO_POLICIES := $(shell find policy -name '*.rego' -type f)

CRM_POLICY := policy/crm/claims_agent/claims_agent_crm.rego
CRM_QUERY := data.crm.claims_agent.allow
CRM_ALLOWED_INPUT := policy/testdata/claims_agent_crm_allowed.json
CRM_DENIED_INPUT := policy/testdata/claims_agent_crm_denied.json

AUTHZ_POLICY := policy/authz/admin_file.rego
AUTHZ_QUERY := data.authz.allow
AUTHZ_ADMIN_INPUT := policy/testdata/admin_file_admin.json
AUTHZ_OWNER_INPUT := policy/testdata/admin_file_owner.json
AUTHZ_DENIED_INPUT := policy/testdata/admin_file_denied.json

GITHUB_MCP_POLICY := policy/coding/github_mcp/github_mcp.rego
GITHUB_MCP_QUERY := data.coding.github_mcp.allow
GITHUB_MCP_READ_ALLOWED_INPUT := policy/testdata/github_mcp_read_allowed.json
GITHUB_MCP_WRITE_ALLOWED_INPUT := policy/testdata/github_mcp_write_allowed.json
GITHUB_MCP_DENIED_INPUT := policy/testdata/github_mcp_denied.json

.PHONY: python-sync python-check eval-allowed eval-denied eval-authz-admin eval-authz-owner eval-authz-denied eval-github-mcp-read eval-github-mcp-write eval-github-mcp-denied compile-wasm test test-crm test-authz test-github-mcp

python-sync:
	$(UV) sync

python-check: python-sync
	$(UV) run python -c "from opapywasm import OpaWasmPolicy; print('opa-py-wasm ready')"

eval-allowed:
	$(OPA) eval --format pretty --data $(CRM_POLICY) --input $(CRM_ALLOWED_INPUT) $(CRM_QUERY)

eval-denied:
	$(OPA) eval --format pretty --data $(CRM_POLICY) --input $(CRM_DENIED_INPUT) $(CRM_QUERY)

eval-authz-admin:
	$(OPA) eval --format pretty --data $(AUTHZ_POLICY) --input $(AUTHZ_ADMIN_INPUT) $(AUTHZ_QUERY)

eval-authz-owner:
	$(OPA) eval --format pretty --data $(AUTHZ_POLICY) --input $(AUTHZ_OWNER_INPUT) $(AUTHZ_QUERY)

eval-authz-denied:
	$(OPA) eval --format pretty --data $(AUTHZ_POLICY) --input $(AUTHZ_DENIED_INPUT) $(AUTHZ_QUERY)

eval-github-mcp-read:
	$(OPA) eval --format pretty --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_READ_ALLOWED_INPUT) $(GITHUB_MCP_QUERY)

eval-github-mcp-write:
	$(OPA) eval --format pretty --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_WRITE_ALLOWED_INPUT) $(GITHUB_MCP_QUERY)

eval-github-mcp-denied:
	$(OPA) eval --format pretty --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_DENIED_INPUT) $(GITHUB_MCP_QUERY)

compile-wasm:
	@mkdir -p $(WASM_DIR)
	@for policy in $(REGO_POLICIES); do \
		package=$$(awk '/^package / { print $$2; exit }' "$$policy"); \
		entrypoint=$$(printf '%s' "$$package" | tr . /)/allow; \
		bundle=$$(basename "$$policy" .rego).tar.gz; \
		echo "Compiling $$policy -> $(WASM_DIR)/$$bundle ($$entrypoint)"; \
		$(OPA) build --target wasm --entrypoint "$$entrypoint" --output "$(WASM_DIR)/$$bundle" "$$policy"; \
	done

test: test-crm test-authz test-github-mcp
	@echo "Policy tests passed"

test-crm:
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_ALLOWED_INPUT) $(CRM_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_DENIED_INPUT) $(CRM_QUERY))" = "false"

test-authz:
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_ADMIN_INPUT) $(AUTHZ_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_OWNER_INPUT) $(AUTHZ_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_DENIED_INPUT) $(AUTHZ_QUERY))" = "false"

test-github-mcp:
	@test "$$($(OPA) eval --format raw --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_READ_ALLOWED_INPUT) $(GITHUB_MCP_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_WRITE_ALLOWED_INPUT) $(GITHUB_MCP_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_DENIED_INPUT) $(GITHUB_MCP_QUERY))" = "false"