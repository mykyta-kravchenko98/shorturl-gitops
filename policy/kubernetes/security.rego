package main

import rego.v1

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  pod_context := object.get(pod_spec(resource), "securityContext", {})
  some container in pod_containers(resource)
  container_context := object.get(container, "securityContext", {})
  not object.get(pod_context, "runAsNonRoot", false)
  not object.get(container_context, "runAsNonRoot", false)

  message := sprintf(
    "%s %s container %s must runAsNonRoot at pod or container level",
    [resource.kind, resource_name(resource), container.name],
  )
}

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  pod_context := object.get(pod_spec(resource), "securityContext", {})
  some container in pod_containers(resource)
  container_context := object.get(container, "securityContext", {})
  not secure_seccomp(pod_context)
  not secure_seccomp(container_context)

  message := sprintf(
    "%s %s container %s must use RuntimeDefault or Localhost seccomp",
    [resource.kind, resource_name(resource), container.name],
  )
}

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  some container in pod_containers(resource)
  container_context := object.get(container, "securityContext", {})
  capabilities := object.get(container_context, "capabilities", {})
  not "ALL" in object.get(capabilities, "drop", [])

  message := sprintf(
    "%s %s container %s must drop ALL Linux capabilities",
    [resource.kind, resource_name(resource), container.name],
  )
}
