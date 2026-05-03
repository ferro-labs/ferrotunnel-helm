# ferrotunnel

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/ferro-labs)](https://artifacthub.io/packages/helm/ferro-labs/ferrotunnel)

Helm chart for running the [FerroTunnel](https://github.com/ferro-labs/ferrotunnel) server on Kubernetes.

## Install

Create the required token Secret:

```sh
kubectl create secret generic ferrotunnel-auth \
  --from-literal=token='replace-with-a-long-random-token'
```

Install the chart from this directory:

```sh
helm upgrade --install ferrotunnel . \
  --set auth.existingSecret=ferrotunnel-auth
```

For local template rendering only:

```sh
helm template ferrotunnel . --set auth.token=dev-token
```

Rendering fails unless one of these is set:

- `auth.existingSecret`
- `auth.token`
- `auth.allowEmptyToken=true`

`auth.allowEmptyToken` is intended only for exceptional test/render workflows.

For production and GitOps, do not commit `auth.token` in values files. Prefer External Secrets Operator (or another cloud secret-sync controller), Sealed Secrets, SOPS-encrypted manifests, or a manually-created Kubernetes Secret referenced by `auth.existingSecret`.

When rotating a Secret referenced by `auth.existingSecret`, restart the Deployment (for example `kubectl rollout restart deployment/<release>-ferrotunnel`) so pods read the new token.

## Production caveats

- The default is one replica. Multi-replica deployments and HPA may disrupt active tunnels unless client reconnect and server drain behavior has been validated for your workload.
- Kubernetes Ingress exposes only HTTP traffic. It does not expose the control plane on port `7835`; use a LoadBalancer, NodePort, Gateway TCPRoute, or infrastructure load balancer for that listener.
- Ingress TLS terminates HTTP traffic at the ingress controller. `tls.*` configures FerroTunnel's own TLS listener; these are separate TLS layers and may use different Secrets.
- Empty NetworkPolicy peer lists allow all sources for that listener.
- `image.tag` defaults to the published GHCR tag matching `appVersion` with a `v` prefix, for example `v1.0.8`. Before releasing, verify the GHCR image tag exists, for example `docker manifest inspect ghcr.io/ferro-labs/ferrotunnel:v<appVersion>` when Docker is available.

## Exposed ports

| Name | Port | Protocol | Description |
| --- | ---: | --- | --- |
| `control` | `7835` | TCP | FerroTunnel client control plane |
| `http` | `8080` | TCP | HTTP ingress and `/health` |
| `metrics` | `9090` | TCP | Optional `/metrics` and `/health/ready` |

## Common values

| Value | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/ferro-labs/ferrotunnel` | Container image repository |
| `image.tag` | `v1.0.8` | Container image tag |
| `replicaCount` | `1` | Number of server pods when HPA is disabled |
| `commonLabels` | `{}` | Additional labels on resource metadata, not selectors |
| `commonAnnotations` | `{}` | Additional annotations on resource metadata |
| `deploymentStrategy` | RollingUpdate, `maxUnavailable: 0`, `maxSurge: 1` | Deployment update strategy |
| `terminationGracePeriodSeconds` | `30` | Pod termination grace period |
| `server.logLevel` | `info` | `RUST_LOG` value |
| `server.metrics` | `false` | Enables metrics listener and metrics Service |
| `server.observability` | `false` | Enables FerroTunnel observability flag |
| `auth.existingSecret` | `""` | Existing Secret containing the token |
| `auth.tokenKey` | `token` | Secret key used for `FERROTUNNEL_TOKEN` |
| `auth.token` | `""` | Inline token for local/dev use |
| `service.control.type` | `ClusterIP` | Service type for port `7835` |
| `service.http.type` | `ClusterIP` | Service type for port `8080` |
| `service.metrics.type` | `ClusterIP` | Service type for port `9090` |
| `extraEnvFrom` | `[]` | Additional `envFrom` sources for the server container |
| `priorityClassName`, `runtimeClassName`, `schedulerName` | `""` | Optional pod scheduling/runtime knobs |
| `ingress.enabled` | `false` | Creates Ingress for HTTP traffic only |
| `tls.enabled` | `false` | Mounts TLS Secret and sets FerroTunnel TLS env vars |
| `serviceMonitor.enabled` | `false` | Creates a Prometheus Operator ServiceMonitor |
| `networkPolicy.enabled` | `false` | Creates a NetworkPolicy for server pods |
| `autoscaling.enabled` | `false` | Creates an HPA |
| `podDisruptionBudget.enabled` | `false` | Creates a PDB |

## HTTP ingress

Kubernetes Ingress is only for FerroTunnel HTTP ingress traffic on port `8080`. It does not expose the control plane on port `7835`.

Use wildcard DNS when exposing arbitrary tunnel hostnames:

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: "*.tunnels.example.com"
      paths:
        - path: /
          pathType: Prefix
```

## Service exposure

Each Service (`control`, `http`, and `metrics`) supports Kubernetes Service knobs such as `nodePort`, `loadBalancerIP`, `loadBalancerClass`, `externalTrafficPolicy`, `internalTrafficPolicy`, `ipFamilyPolicy`, `ipFamilies`, and `sessionAffinity`. `nodePort` is rendered only for `NodePort` and `LoadBalancer` services.

```yaml
service:
  control:
    type: LoadBalancer
    port: 7835
    loadBalancerClass: service.k8s.aws/nlb
    externalTrafficPolicy: Local
  http:
    type: NodePort
    port: 8080
    nodePort: 30080
```

## Metrics

```yaml
server:
  metrics: true

serviceMonitor:
  enabled: true
```

Metrics are served at `/metrics` on the metrics Service. `serviceMonitor.enabled=true` requires `server.metrics=true`.

## TLS

```yaml
tls:
  enabled: true
  existingSecret: ferrotunnel-tls
  certKey: tls.crt
  keyKey: tls.key
  caKey: ca.crt
  clientAuth: true
```

The TLS Secret is mounted read-only at `tls.mountPath` and mapped to FerroTunnel TLS environment variables.

`FERROTUNNEL_TLS_CA` is only set when `tls.clientAuth=true`; otherwise the chart configures server TLS without enabling mTLS.

## Autoscaling

Autoscaling requires at least one utilization target and matching resource requests:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  targetCPUUtilizationPercentage: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

CPU targets require `resources.requests.cpu`; memory targets require `resources.requests.memory`.

## NetworkPolicy

When `networkPolicy.enabled=true`, the chart restricts allowed ports to the configured FerroTunnel listeners. Empty ingress peer lists allow traffic from all sources on that listener. Set `controlIngress`, `httpIngress`, and `metricsIngress` to restrict source namespaces, pods, or CIDRs.

For example:

```yaml
networkPolicy:
  enabled: true
  controlIngress:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: tunnel-clients
  httpIngress:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  metricsIngress:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
```

## Security

Defaults are intentionally locked down:

- non-root UID/GID `65532`
- read-only root filesystem
- no privilege escalation
- all capabilities dropped
- `RuntimeDefault` seccomp
- service account token automount disabled

## Validate

```sh
helm lint . --set auth.token=lint-token
helm template ferrotunnel . --set auth.existingSecret=ferrotunnel-auth
helm template ferrotunnel . -f ci/minimal-values.yaml
```

## License

Apache-2.0.
