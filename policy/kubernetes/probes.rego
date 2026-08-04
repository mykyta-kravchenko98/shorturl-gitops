package main

import rego.v1

deny contains message if {
  some entry in resource_entries
  workload := entry.contents
  workload.kind in workload_kinds
  some container in workload_containers(workload)
  object.get(container, "livenessProbe", null) == null

  message := sprintf(
    "%s %s long-lived container %s must define livenessProbe",
    [workload.kind, resource_name(workload), container.name],
  )
}

deny contains message if {
  some entry in resource_entries
  workload := entry.contents
  workload.kind in workload_kinds
  some container in workload_containers(workload)
  object.get(container, "readinessProbe", null) == null

  message := sprintf(
    "%s %s long-lived container %s must define readinessProbe",
    [workload.kind, resource_name(workload), container.name],
  )
}
