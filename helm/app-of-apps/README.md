# Argo CD app-of-apps chart

The chart renders child Argo CD Applications from a shared Git repository and
revision. The selected ShortURL values overlay is controlled by
`shorturl.valuesFile`.

The default profile renders the complete local platform. Setting `ci.enabled`
to `true` renders only the `namespaces` and `shorturl` Applications, avoiding
private controller images and the observability stack in the disposable CI
cluster. Controller lifecycle tests can additionally set
`ci.controllersEnabled=true`; this opts Kurama and Amenotejikara into CI while
leaving Redis and the observability stack disabled. Set
`kurama.externalSecret.enabled=false` when the target cluster does not install
External Secrets Operator; Argo CD then removes only `shorturl-api-auth` from
the rendered Kurama resources.

```bash
helm template root helm/app-of-apps \
  --set-string shorturl.valuesFile=values-ci.yaml \
  --set ci.enabled=true
```

```bash
helm template root helm/app-of-apps \
  --set-string shorturl.valuesFile=values-ci.yaml \
  --set ci.enabled=true \
  --set ci.controllersEnabled=true \
  --set kurama.externalSecret.enabled=false
```

