# Argo CD app-of-apps chart

The chart renders child Argo CD Applications from a shared Git repository and
revision. The selected ShortURL values overlay is controlled by
`shorturl.valuesFile`.

The default profile renders the complete local platform. Setting `ci.enabled`
to `true` renders only the `namespaces` and `shorturl` Applications, avoiding
private controller images and the observability stack in the disposable CI
cluster.

```bash
helm template root helm/app-of-apps \
  --set-string shorturl.valuesFile=values-ci.yaml \
  --set ci.enabled=true
```

