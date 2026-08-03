{{- define "shorturl.fullname" -}}
shorturl
{{- end -}}

{{- define "shorturl.labels" -}}
app.kubernetes.io/name: shorturl
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ required "imageVersion is required" .Values.imageVersion | quote }}
{{- end -}}

{{- define "shorturl.selectorLabels" -}}
app.kubernetes.io/name: shorturl
{{- end -}}

{{- define "shorturl.imageRef" -}}
{{- if .image.digest -}}
{{ .image.repository }}@{{ .image.digest }}
{{- else -}}
{{ .image.repository }}:{{ required "imageVersion is required when an image digest is empty" .version }}
{{- end -}}
{{- end -}}

{{/*
Shared pod spec for both the one-shot seed Job and the recurring CronJob
that refresh the ECR docker-registry pull secret. Takes .Values.ecrRefresh as
context (region/registry/secretName/credentialsSecretName). Kept as one
named template so the two callers can't drift apart.
*/}}
{{- define "shorturl.ecrRefreshPodSpec" -}}
serviceAccountName: ecr-pull-refresher
restartPolicy: Never
initContainers:
  - name: fetch-kubectl
    image: {{ .kubectl.downloadImage | quote }}
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsUser: 100
      runAsGroup: 101
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL
    command:
      - sh
      - -c
      - |
        curl -fsSL -o /shared/kubectl "https://dl.k8s.io/release/{{ .kubectl.version }}/bin/linux/amd64/kubectl"
        echo "{{ .kubectl.sha256 }}  /shared/kubectl" | sha256sum -c -
        chmod +x /shared/kubectl
    volumeMounts:
      - name: shared
        mountPath: /shared
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 200m
        memory: 64Mi
containers:
  - name: refresh
    image: {{ .awsCliImage | quote }}
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      runAsUser: 100
      runAsGroup: 101
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 200m
        memory: 64Mi
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
