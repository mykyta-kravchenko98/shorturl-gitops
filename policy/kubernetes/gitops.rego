package main

import rego.v1

git_application_sources contains source if {
  some entry in resource_entries
  application := entry.contents
  application.kind == "Application"
  source := object.get(application.spec, "source", {})
  object.get(source, "repoURL", "") != ""
  object.get(source, "chart", "") == ""
}

git_application_sources contains source if {
  some entry in resource_entries
  application := entry.contents
  application.kind == "Application"
  some source in object.get(application.spec, "sources", [])
  object.get(source, "repoURL", "") != ""
  object.get(source, "chart", "") == ""
}

git_application_revisions := {
  object.get(source, "targetRevision", "") |
  some source in git_application_sources
}

deny contains "Git-based Argo Applications must set targetRevision" if {
  "" in git_application_revisions
}

deny contains message if {
  count(git_application_revisions) > 1
  revisions := concat(", ", sort(git_application_revisions))
  message := sprintf(
    "Git-based Argo Applications must use one targetRevision; found: %s",
    [revisions],
  )
}
