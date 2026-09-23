package coding.github_mcp

import rego.v1

# Hook input contract:
# {
#   "agent": "Copilot" | "Claude" | "GitHub Copilot",
#   "server": "github" | "mcp_github" | "github-mcp-server",
#   "tool": "mcp_github_mcp_se_search_issues",
#   "arguments": { ... },
#   "user_approved": true | false
# }
trusted_agents := {"Claude", "Copilot", "GitHub Copilot"}

github_servers := {"github", "mcp_github", "github-mcp-server"}

read_tools := {
	"mcp_github_mcp_se_get_me",
	"mcp_github_mcp_se_get_commit",
	"mcp_github_mcp_se_get_file_contents",
	"mcp_github_mcp_se_get_label",
	"mcp_github_mcp_se_get_latest_release",
	"mcp_github_mcp_se_get_release_by_tag",
	"mcp_github_mcp_se_get_tag",
	"mcp_github_mcp_se_get_team_members",
	"mcp_github_mcp_se_get_teams",
	"mcp_github_mcp_se_issue_read",
	"mcp_github_mcp_se_list_branches",
	"mcp_github_mcp_se_list_commits",
	"mcp_github_mcp_se_list_issue_fields",
	"mcp_github_mcp_se_list_issue_types",
	"mcp_github_mcp_se_list_issues",
	"mcp_github_mcp_se_list_pull_requests",
	"mcp_github_mcp_se_list_releases",
	"mcp_github_mcp_se_list_repository_collaborators",
	"mcp_github_mcp_se_list_tags",
	"mcp_github_mcp_se_pull_request_read",
	"mcp_github_mcp_se_search_code",
	"mcp_github_mcp_se_search_commits",
	"mcp_github_mcp_se_search_issues",
	"mcp_github_mcp_se_search_pull_requests",
	"mcp_github_mcp_se_search_repositories",
	"mcp_github_mcp_se_search_users",
}

write_tools := {
	"mcp_github_mcp_se_add_comment_to_pending_review",
	"mcp_github_mcp_se_add_issue_comment",
	"mcp_github_mcp_se_add_reply_to_pull_request_comment",
	"mcp_github_mcp_se_create_branch",
	"mcp_github_mcp_se_create_or_update_file",
	"mcp_github_mcp_se_create_pull_request",
	"mcp_github_mcp_se_create_pull_request_with_copilot",
	"mcp_github_mcp_se_pull_request_review_write",
	"mcp_github_mcp_se_push_files",
	"mcp_github_mcp_se_request_copilot_review",
	"mcp_github_mcp_se_update_pull_request",
	"mcp_github_mcp_se_update_pull_request_branch",
}

direct_branch_write_tools := {
	"mcp_github_mcp_se_create_or_update_file",
	"mcp_github_mcp_se_push_files",
}

protected_refs := {"main", "master", "refs/heads/main", "refs/heads/master"}

tool_name := object.get(input, "tool", "")

arguments := object.get(input, "arguments", {})

default allow := false

allow if {
	trusted_agent
	github_call
	tool_name in read_tools
}

allow if {
	trusted_agent
	github_call
	tool_name in write_tools
	input.user_approved == true
	not protected_branch_write
}

trusted_agent if {
	input.agent in trusted_agents
}

github_call if {
	object.get(input, "server", "") in github_servers
}

github_call if {
	startswith(tool_name, "mcp_github_")
}

protected_branch_write if {
	tool_name in direct_branch_write_tools
	object.get(arguments, "branch", "") in protected_refs
}

protected_branch_write if {
	tool_name in direct_branch_write_tools
	object.get(arguments, "ref", "") in protected_refs
}
