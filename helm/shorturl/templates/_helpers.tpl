{{- define "shorturl.fullname" -}}
shorturl
{{- end -}}

{{- define "shorturl.labels" -}}
app.kubernetes.io/name: shorturl
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "shorturl.selectorLabels" -}}
app.kubernetes.io/name: shorturl
{{- end -}}

{{/*
Shared pod spec for both the one-shot seed Job and the recurring CronJob
that refresh the ECR docker-registry pull secret. Takes .Values.ecrPull as
context (region/registry/secretName/credentialsSecretName). Kept as one
named template so the two callers can't drift apart.
*/}}
{{- define "shorturl.ecrRefreshPodSpec" -}}
serviceAccountName: ecr-pull-refresher
restartPolicy: Never
initContainers:
  - name: fetch-kubectl
    # Pinned-ish: matches whatever's "stable" at pull time. If this ever
    # breaks, pin to an explicit version instead of stable.txt.
    image: alpine:3.20
    command:
      - sh
      - -c
      - |
        apk add --no-cache curl >/dev/null
        KVER="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
        curl -L -o /shared/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
        chmod +x /shared/kubectl
    volumeMounts:
      - name: shared
        mountPath: /shared
containers:
  - name: refresh
    image: amazon/aws-cli:latest
    command: ["sh", "/scripts/refresh.sh"]
    env:
      - name: ECR_REGION
        value: {{ .region | quote }}
      - name: ECR_REGISTRY
        value: {{ .registry | quote }}
      - name: SECRET_NAME
        value: {{ .secretName | quote }}
      - name: POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: PATH
        value: "/shared:/usr/local/bin:/usr/bin:/bin"
    envFrom:
      - secretRef:
          name: {{ .credentialsSecretName }}
    volumeMounts:
      - name: shared
        mountPath: /shared
      - name: script
        mountPath: /scripts
volumes:
  - name: shared
    emptyDir: {}
  - name: script
    configMap:
      name: ecr-pull-refresh-script
      defaultMode: 0755
{{- end -}}
