package main

import rego.v1

deny contains message if {
  some entry in resource_entries
  workload := entry.contents
  workload.kind in workload_kinds
  selector := object.get(object.get(workload.spec, "selector", {}), "matchLabels", {})
  labels := object.get(object.get(workload.spec.template, "metadata", {}), "labels", {})
  not selector_matches_labels(selector, labels)

  message := sprintf(
    "%s %s selector.matchLabels must match its pod-template labels",
    [workload.kind, resource_name(workload)],
  )
}

service_has_matching_workload(service) if {
  some entry in resource_entries
  workload := entry.contents
  workload.kind in workload_kinds
  resource_namespace(workload) == resource_namespace(service)
  labels := object.get(object.get(workload.spec.template, "metadata", {}), "labels", {})
  selector_matches_labels(service.spec.selector, labels)
}

deny contains message if {
  some entry in resource_entries
  service := entry.contents
  service.kind == "Service"
  selector := object.get(service.spec, "selector", {})
  count(selector) > 0
  not service_has_matching_workload(service)

  message := sprintf(
    "Service %s selector does not match any workload pod labels in namespace %s",
    [resource_name(service), resource_namespace(service)],
  )
}
