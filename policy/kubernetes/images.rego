package main

import rego.v1

deny contains message if {
  some entry in resource_entries
  resource := entry.contents
  some container in pod_containers(resource)
  image := object.get(container, "image", "")
  regex.match(":latest(@sha256:[0-9a-fA-F]{64})?$", image)

  message := sprintf(
    "%s %s container %s uses forbidden latest image %s",
    [resource.kind, resource_name(resource), container.name, image],
  )
}

deny contains message if {
  some entry in resource_entries
  production_entry(entry)
  resource := entry.contents
  some container in pod_containers(resource)
  image := object.get(container, "image", "")
  not regex.match("@sha256:[0-9a-fA-F]{64}$", image)

  message := sprintf(
    "%s %s container %s must pin its production image by sha256 digest: %s",
    [resource.kind, resource_name(resource), container.name, image],
  )
}
