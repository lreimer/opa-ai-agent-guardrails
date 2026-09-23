package authz

import rego.v1

# Standardmäßig wird der Zugriff verweigert
default allow := false

# Zugriff gewähren, wenn der Nutzer die Rolle "admin" hat
allow if {
	input.user.role == "admin"
}

# Zugriff gewähren, wenn der Nutzer Eigentümer des Dokuments ist
allow if {
	input.user.id == input.document.owner_id
}
