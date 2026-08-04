package main

import rego.v1

matching_resource(kind, name, namespace) if {
  some entry in resource_entries
  resource := entry.contents
  resource.kind == kind
  resource_name(resource) == name
  resource_namespace(resource) == namespace
}

deny contains message if {
  some entry in resource_entries
  binding := entry.contents
  binding.kind == "RoleBinding"
  binding.roleRef.kind == "Role"
  not matching_resource("Role", binding.roleRef.name, resource_namespace(binding))

  message := sprintf(
    "RoleBinding %s must reference an existing Role in namespace %s",
    [resource_name(binding), resource_namespace(binding)],
  )
}

deny contains message if {
  some entry in resource_entries
  binding := entry.contents
  binding.kind == "RoleBinding"
  some subject in object.get(binding, "subjects", [])
  subject.kind == "ServiceAccount"
  object.get(subject, "namespace", "") == ""

  message := sprintf(
    "RoleBinding %s ServiceAccount subject %s must set namespace explicitly",
    [resource_name(binding), subject.name],
  )
}

deny contains message if {
  some entry in resource_entries
  binding := entry.contents
  binding.kind == "RoleBinding"
  some subject in object.get(binding, "subjects", [])
  subject.kind == "ServiceAccount"
  namespace := object.get(subject, "namespace", "")
  namespace != ""
  not matching_resource("ServiceAccount", subject.name, namespace)

  message := sprintf(
    "RoleBinding %s must reference existing ServiceAccount %s in namespace %s",
    [resource_name(binding), subject.name, namespace],
  )
}
