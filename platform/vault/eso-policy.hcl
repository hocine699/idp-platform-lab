# Lecture seule sur tous les secrets du coffre "secret/", pour ESO.
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
