package main

import rego.v1

required_compute_resources := {"cpu", "memory"}

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  some container in pod_containers(resource)
  some compute_resource in required_compute_resources
  resources := object.get(container, "resources", {})
  requests := object.get(resources, "requests", {})
  object.get(requests, compute_resource, "") == ""

  message := sprintf(
    "%s %s container %s must set resources.requests.%s",
    [resource.kind, resource_name(resource), container.name, compute_resource],
  )
}

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  some container in pod_containers(resource)
  some compute_resource in required_compute_resources
  resources := object.get(container, "resources", {})
  limits := object.get(resources, "limits", {})
  object.get(limits, compute_resource, "") == ""

  message := sprintf(
    "%s %s container %s must set resources.limits.%s",
    [resource.kind, resource_name(resource), container.name, compute_resource],
  )
}
