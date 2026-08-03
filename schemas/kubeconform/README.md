# Kubeconform custom schemas

The static gate uses Kubernetes `1.31.14` schemas from kubeconform's default
registry and the vendored custom-resource schemas in this directory. Runtime
validation never uses a floating custom-schema registry.

Schema filenames follow kubeconform's
`{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json` convention.

## Sources

| Resources | Runtime version | CRD source | Source SHA-256 |
| --- | --- | --- | --- |
| Argo CD `Application` | Argo CD `v2.12.6` / chart `7.6.12` | `https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.6/manifests/crds/application-crd.yaml` | `fc13177c2bccfb24c3f03795b26cd570665496d537f724fd6f9acec58e915877` |
| ESO `ExternalSecret`, `SecretStore` | ESO/chart `v2.6.0` | `https://raw.githubusercontent.com/external-secrets/external-secrets/v2.6.0/deploy/crds/bundle.yaml` | `dc07cbccdd15956661d81562dd46b657e2b02e760669f3dbf2ac2f1778e27705` |
| `CredentialRotation` | repository CRD | `k8s/amenotejikara/crd.yaml` | checked by `local-crds.sha256` |
| `TrafficScenario` | repository CRD | `k8s/kurama/crd.yaml` | checked by `local-crds.sha256` |

The schemas were generated with `scripts/openapi2jsonschema.py` from
kubeconform `v0.8.0` commit
`02374e583d700721f57300fae78e11acd27ee539` and
`DENY_ROOT_ADDITIONAL_PROPERTIES=1`. The converter SHA-256 was
`d145babfbb765004030764e1b4e518bfb7a4bd7f111691a08fa57983b81881f3`.

When either repository CRD changes, `make test-kubeconform` fails its
line-ending-normalized checksum check. Regenerate all custom schemas with:

```bash
make update-kubeconform-schemas
```

The maintenance command requires `curl`, `python3`, the Python `venv` module,
and network access. It creates an isolated temporary environment, verifies the
downloaded converter and public CRDs against the hashes above, updates the five
vendored schemas, and recalculates `local-crds.sha256`. It is intentionally not
part of `make test-static` because it downloads inputs and modifies tracked
files.

Always review the generated schema diff and run `make test-kubeconform` before
committing. Public CRD schema upgrades must be committed together with the
runtime chart version that introduces them.
