OPA ?= opa

CRM_POLICY := policy/crm/claims_agent/claims_agent_crm.rego
CRM_QUERY := data.crm.claims_agent.allow
CRM_ALLOWED_INPUT := policy/testdata/claims_agent_crm_allowed.json
CRM_DENIED_INPUT := policy/testdata/claims_agent_crm_denied.json

AUTHZ_POLICY := policy/authz/admin_file.rego
AUTHZ_QUERY := data.authz.allow
AUTHZ_ADMIN_INPUT := policy/testdata/admin_file_admin.json
AUTHZ_OWNER_INPUT := policy/testdata/admin_file_owner.json
AUTHZ_DENIED_INPUT := policy/testdata/admin_file_denied.json

.PHONY: eval-allowed eval-denied eval-authz-admin eval-authz-owner eval-authz-denied test test-crm test-authz

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

test: test-crm test-authz
	@echo "Policy tests passed"

test-crm:
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_ALLOWED_INPUT) $(CRM_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(CRM_POLICY) --input $(CRM_DENIED_INPUT) $(CRM_QUERY))" = "false"

test-authz:
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_ADMIN_INPUT) $(AUTHZ_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_OWNER_INPUT) $(AUTHZ_QUERY))" = "true"
	@test "$$($(OPA) eval --format raw --data $(AUTHZ_POLICY) --input $(AUTHZ_DENIED_INPUT) $(AUTHZ_QUERY))" = "false"