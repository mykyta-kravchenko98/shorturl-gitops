package main

import rego.v1

hook_annotations(resource) := object.get(
  object.get(resource, "metadata", {}),
  "annotations",
  {},
)

is_helm_hook(resource) if {
  object.get(hook_annotations(resource), "helm.sh/hook", "") != ""
}

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  is_helm_hook(resource)
  object.get(hook_annotations(resource), "helm.sh/hook-delete-policy", "") == ""

  message := sprintf(
    "%s %s Helm hook must set helm.sh/hook-delete-policy",
    [resource.kind, resource_name(resource)],
  )
}

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  resource.kind == "Job"
  is_helm_hook(resource)
  object.get(resource.spec, "activeDeadlineSeconds", 0) <= 0

  message := sprintf(
    "Job %s Helm hook must set a positive spec.activeDeadlineSeconds timeout",
    [resource_name(resource)],
  )
}
