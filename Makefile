OPA ?= opa
UV ?= uv
CARGO ?= cargo
ADK_AGENTS_DIR := agents
ADK_WEB_PORT ?= 8000
WASM_DIR := build/wasm
REGO_POLICIES := $(shell find policy -name '*.rego' -type f)
RUST_POLICY_BUNDLE := $(WASM_DIR)/github_mcp.tar.gz
RUST_POLICY_ENTRYPOINT := coding/github_mcp/allow

CRM_POLICY := policy/crm/claims_agent/claims_agent_crm.rego
CRM_QUERY := data.crm.claims_agent.allow
CRM_ALLOWED_INPUT := policy/testdata/claims_agent_crm_allowed.json
CRM_DENIED_INPUT := policy/testdata/claims_agent_crm_denied.json
CRM_ENVOY_ALLOWED_INPUT := policy/testdata/claims_agent_crm_envoy_allowed.json

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

CLC26_POLICY := policy/agents/clc26/clc26_agent.rego
CLC26_QUERY := data.agents.clc26.allow
CLC26_TESTDATA := policy/testdata/clc26_agent

QAWARE_POLICY := policy/agents/qaware/qaware_agent.rego
QAWARE_QUERY := data.agents.qaware.allow
QAWARE_REASONS_QUERY := data.agents.qaware.deny_reasons
QAWARE_TESTDATA := policy/testdata/qaware_agent
QAWARE_INPUT ?= $(QAWARE_TESTDATA)_response_buzzword_denied.json

.PHONY: python-sync python-check adk-web rust-build rust-check-policy-allowed rust-check-policy-write rust-check-policy-denied test-rust-hook eval-allowed eval-denied eval-authz-admin eval-authz-owner eval-authz-denied eval-github-mcp-read eval-github-mcp-write eval-github-mcp-denied eval-qaware-reasons compile-wasm extract-wasm test test-crm test-authz test-github-mcp test-clc26-agent test-qaware-agent

python-sync:
	$(UV) sync

python-check: python-sync
	$(UV) run python -c "from opapywasm import OpaWasmPolicy; print('opa-py-wasm ready')"

adk-web: python-sync extract-wasm
	$(UV) run adk web --port $(ADK_WEB_PORT) $(ADK_AGENTS_DIR)

rust-build:
	$(CARGO) build --bin check-policy

rust-check-policy-allowed: compile-wasm
	$(CARGO) run --quiet --bin check-policy -- $(RUST_POLICY_BUNDLE) $(RUST_POLICY_ENTRYPOINT) < $(GITHUB_MCP_READ_ALLOWED_INPUT)

rust-check-policy-write: compile-wasm
	$(CARGO) run --quiet --bin check-policy -- $(RUST_POLICY_BUNDLE) $(RUST_POLICY_ENTRYPOINT) < $(GITHUB_MCP_WRITE_ALLOWED_INPUT)

rust-check-policy-denied: compile-wasm
	@$(CARGO) run --quiet --bin check-policy -- $(RUST_POLICY_BUNDLE) $(RUST_POLICY_ENTRYPOINT) < $(GITHUB_MCP_DENIED_INPUT) 2>/dev/null; \
	status=$$?; \
	test $$status -eq 2

test-rust-hook: rust-build rust-check-policy-allowed rust-check-policy-write rust-check-policy-denied
	@echo "Rust policy hook tests passed"

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

eval-qaware-reasons:
	$(OPA) eval --format pretty --data $(QAWARE_POLICY) --input $(QAWARE_INPUT) $(QAWARE_REASONS_QUERY)

compile-wasm:
	@mkdir -p $(WASM_DIR)
	@for policy in $(REGO_POLICIES); do \
		package=$$(awk '/^package / { print $$2; exit }' "$$policy"); \
		entrypoint=$$(printf '%s' "$$package" | tr . /)/allow; \
		extra=""; \
		if grep -q '^deny_reasons ' "$$policy"; then extra="--entrypoint $$(printf '%s' "$$package" | tr . /)/deny_reasons"; fi; \
		bundle=$$(basename "$$policy" .rego).tar.gz; \
		echo "Compiling $$policy -> $(WASM_DIR)/$$bundle ($$entrypoint)"; \
		$(OPA) build --target wasm --entrypoint "$$entrypoint" $$extra --output "$(WASM_DIR)/$$bundle" "$$policy"; \
	done

extract-wasm: compile-wasm
	@set -e; for bundle in $(WASM_DIR)/*.tar.gz; do \
		policy_name=$$(basename "$$bundle" .tar.gz); \
		output="build/$$policy_name.wasm"; \
		echo "Extracting $$bundle -> $$output"; \
		tar -xOzf "$$bundle" /policy.wasm > "$$output"; \
	done

test: test-crm test-authz test-github-mcp test-clc26-agent test-qaware-agent
	@echo "Policy tests passed"

test-crm:
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_ALLOWED_INPUT) $(CRM_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_DENIED_INPUT) $(CRM_QUERY))" = "false"
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_ENVOY_ALLOWED_INPUT) $(CRM_QUERY))" = "true"

test-authz:
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_ADMIN_INPUT) $(AUTHZ_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_OWNER_INPUT) $(AUTHZ_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_DENIED_INPUT) $(AUTHZ_QUERY))" = "false"

test-github-mcp:
	@test "$$($(OPA) eval --format raw --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_READ_ALLOWED_INPUT) $(GITHUB_MCP_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_WRITE_ALLOWED_INPUT) $(GITHUB_MCP_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(GITHUB_MCP_POLICY) --input $(GITHUB_MCP_DENIED_INPUT) $(GITHUB_MCP_QUERY))" = "false"

test-clc26-agent:
	@test "$$($(OPA) eval --format raw --data $(CLC26_POLICY) --input $(CLC26_TESTDATA)_prompt_allowed.json $(CLC26_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(CLC26_POLICY) --input $(CLC26_TESTDATA)_prompt_denied.json $(CLC26_QUERY))" = "false"
	@test "$$($(OPA) eval --format raw --data $(CLC26_POLICY) --input $(CLC26_TESTDATA)_response_denied.json $(CLC26_QUERY))" = "false"
	@test "$$($(OPA) eval --format raw --data $(CLC26_POLICY) --input $(CLC26_TESTDATA)_tool_allowed.json $(CLC26_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(CLC26_POLICY) --input $(CLC26_TESTDATA)_tool_denied.json $(CLC26_QUERY))" = "false"

# Test inputs encode the expected decision in their file name: *_allowed.json or *_denied.json.
test-qaware-agent:
	@set -e; for input in $(QAWARE_TESTDATA)_*_allowed.json $(QAWARE_TESTDATA)_*_denied.json; do \
		case "$$input" in *_allowed.json) expected=true ;; *) expected=false ;; esac; \
		actual=$$($(OPA) eval --format raw --data $(QAWARE_POLICY) --input "$$input" $(QAWARE_QUERY)); \
		if [ "$$actual" != "$$expected" ]; then echo "FAIL $$input: expected $$expected, got $$actual"; exit 1; fi; \
	done
