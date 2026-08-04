package main

import rego.v1

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  not resource.kind in cluster_scoped_kinds
  resource_namespace(resource) == ""

  message := sprintf(
    "%s %s must set metadata.namespace explicitly",
    [resource.kind, resource_name(resource)],
  )
}
