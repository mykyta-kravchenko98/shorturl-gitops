package main

import rego.v1

cluster_scoped_kinds := {
  "APIService",
  "ClusterRole",
  "ClusterRoleBinding",
  "CustomResourceDefinition",
  "MutatingWebhookConfiguration",
  "Namespace",
  "Node",
  "PersistentVolume",
  "PriorityClass",
  "StorageClass",
  "ValidatingWebhookConfiguration",
}

workload_kinds := {"DaemonSet", "Deployment", "StatefulSet"}
pod_resource_kinds := workload_kinds | {"Job"}

resource_entries contains entry if {
  some entry in input
  is_object(entry)
  is_object(object.get(entry, "contents", null))
  object.get(entry.contents, "kind", "") != ""
}

resource_name(resource) := object.get(
  object.get(resource, "metadata", {}),
  "name",
  "<unnamed>",
)

resource_namespace(resource) := object.get(
  object.get(resource, "metadata", {}),
  "namespace",
  "",
)

pod_spec(resource) := resource.spec.template.spec if {
  resource.kind in pod_resource_kinds
}

pod_spec(resource) := resource.spec.jobTemplate.spec.template.spec if {
  resource.kind == "CronJob"
}

pod_containers(resource) := array.concat(
  object.get(pod_spec(resource), "initContainers", []),
  object.get(pod_spec(resource), "containers", []),
)

selector_matches_labels(selector, labels) if {
  count(selector) > 0
  every key, value in selector {
    object.get(labels, key, null) == value
  }
}

production_entry(entry) if {
  not endswith(entry.path, "helm-shorturl-ci.yaml")
}
