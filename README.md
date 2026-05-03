# FerroTunnel Helm Charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/ferro-labs)](https://artifacthub.io/packages/helm/ferro-labs/ferrotunnel)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

Official Helm chart repository for running the [FerroTunnel](https://github.com/ferro-labs/ferrotunnel) server on Kubernetes.

FerroTunnel is a reverse tunnel server. This chart deploys the server-side control plane and HTTP ingress path. Client mode is intentionally not part of the first chart release.

## Charts

| Chart | Description | Chart version | App version |
| --- | --- | --- | --- |
| [`ferrotunnel`](./charts/ferrotunnel) | FerroTunnel server for Kubernetes | `0.1.0` | `1.0.8` |

## What the chart deploys

| Component | Default | Purpose |
| --- | --- | --- |
| Deployment | `ferrotunnel server` | Runs the FerroTunnel server process |
| Control service | `7835/TCP` | Tunnel clients connect here |
| HTTP service | `8080/TCP` | Public HTTP ingress and `/health` |
| Metrics service | `9090/TCP` | Optional `/metrics` and `/health/ready` |
| Secret | token key `token` | Provides `FERROTUNNEL_TOKEN` |
| Optional Ingress | HTTP service only | Routes browser/client HTTP traffic by host |

The control plane is not exposed through Kubernetes Ingress. Use a `LoadBalancer`, `NodePort`, Gateway API TCP route, or infrastructure load balancer for port `7835`.

## Install from source

Create the required auth token as a Kubernetes Secret:

```sh
kubectl create namespace ferrotunnel

kubectl create secret generic ferrotunnel-auth \
  --namespace ferrotunnel \
  --from-literal=token='replace-with-a-long-random-token'
```

Install the chart:

```sh
helm upgrade --install ferrotunnel ./charts/ferrotunnel \
  --namespace ferrotunnel \
  --set auth.existingSecret=ferrotunnel-auth
```

Run the chart test after installation:

```sh
helm test ferrotunnel --namespace ferrotunnel
```

## Install from the Helm repository

After the first chart release is published:

```sh
helm repo add ferro-labs https://ferro-labs.github.io/ferrotunnel-helm
helm repo update

helm upgrade --install ferrotunnel ferro-labs/ferrotunnel \
  --namespace ferrotunnel \
  --create-namespace \
  --set auth.existingSecret=ferrotunnel-auth
```

## Production example

```yaml
image:
  repository: ghcr.io/ferro-labs/ferrotunnel
  tag: v1.0.8

server:
  logLevel: info
  metrics: true

auth:
  existingSecret: ferrotunnel-auth

service:
  control:
    type: LoadBalancer
    port: 7835
    externalTrafficPolicy: Local
  http:
    type: LoadBalancer
    port: 8080
  metrics:
    type: ClusterIP
    port: 9090

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi

podDisruptionBudget:
  enabled: true
  minAvailable: 1

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

serviceMonitor:
  enabled: true
```

Production notes:

- The chart defaults to one replica. Multi-replica/HPA deployments can disrupt active tunnels unless reconnect and drain behavior is validated.
- Do not commit `auth.token` in production/GitOps values. Prefer External Secrets, Sealed Secrets, SOPS, or a manually-created Secret via `auth.existingSecret`.
- Rotating a Secret referenced by `auth.existingSecret` requires a Deployment rollout restart so pods read the new token.
- `image.tag` defaults to the published GHCR tag matching `appVersion` with a `v` prefix; verify the GHCR tag exists before release.

Install with:

```sh
helm upgrade --install ferrotunnel ./charts/ferrotunnel \
  --namespace ferrotunnel \
  -f values.production.yaml
```

## HTTP ingress and wildcard DNS

FerroTunnel routes tunneled HTTP traffic by the `Host` header. For public HTTP traffic, configure wildcard DNS and an ingress controller or load balancer that preserves the host header.

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: "*.tunnels.example.com"
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: ferrotunnel-wildcard-tls
      hosts:
        - "*.tunnels.example.com"
```

This exposes only the HTTP listener on `8080`. It does not expose the tunnel control plane on `7835`.

Ingress TLS terminates public HTTP traffic at the ingress controller. FerroTunnel `tls.*` configures the FerroTunnel server TLS listener and is separate from Ingress TLS.

## TLS for FerroTunnel traffic

To enable FerroTunnel TLS, mount an existing Kubernetes Secret containing the configured certificate and key names:

```sh
kubectl create secret generic ferrotunnel-tls \
  --namespace ferrotunnel \
  --from-file=tls.crt=server.crt \
  --from-file=tls.key=server.key \
  --from-file=ca.crt=ca.crt
```

```yaml
tls:
  enabled: true
  existingSecret: ferrotunnel-tls
  certKey: tls.crt
  keyKey: tls.key
  caKey: ca.crt
  clientAuth: true
```

When enabled, the chart sets:

| Environment variable | Value |
| --- | --- |
| `FERROTUNNEL_TLS_CERT` | `<tls.mountPath>/<tls.certKey>` |
| `FERROTUNNEL_TLS_KEY` | `<tls.mountPath>/<tls.keyKey>` |
| `FERROTUNNEL_TLS_CA` | `<tls.mountPath>/<tls.caKey>`, only when `tls.clientAuth=true` |
| `FERROTUNNEL_TLS_CLIENT_AUTH` | `true`, only when `tls.clientAuth=true` |

## Security defaults

The chart defaults to a hardened container profile:

- non-root user and group `65532`
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- all Linux capabilities dropped
- `RuntimeDefault` seccomp profile
- service account token automount disabled

Keep `auth.existingSecret` as the normal production path. `auth.token` is useful for local rendering and tests, but should not be committed in values files.

## Observability

Set `server.metrics=true` to expose the metrics service:

```yaml
server:
  metrics: true

serviceMonitor:
  enabled: true
```

Metrics are exposed at `/metrics` on port `9090`. The metrics listener also exposes `/health/ready`.

## Autoscaling

Autoscaling requires at least one utilization target and matching resource requests:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
```

CPU targets require `resources.requests.cpu`; memory targets require `resources.requests.memory`.

## NetworkPolicy

When enabled, the chart creates peer-list based ingress rules per listener. Empty `controlIngress`, `httpIngress`, or `metricsIngress` lists allow all sources for that listener; set peer lists explicitly to restrict namespaces, pods, or CIDRs.

## Development

Validate the chart locally:

```sh
helm lint charts/ferrotunnel --set auth.token=lint-token
helm template ferrotunnel charts/ferrotunnel --set auth.existingSecret=ferrotunnel-auth
helm template ferrotunnel charts/ferrotunnel -f charts/ferrotunnel/ci/minimal-values.yaml
```

If `ct` is installed:

```sh
ct lint --config ct.yaml --charts charts/ferrotunnel
```

The chart `appVersion` tracks the FerroTunnel application version. The default image tag is the matching published GHCR tag with a `v` prefix, for example `v1.0.8`.

## Release process

Merges to `main` run `.github/workflows/release.yml`; maintainers can also start it manually with `workflow_dispatch`.

The release workflow:

1. Installs Helm.
2. Runs `helm/chart-releaser-action`.
3. Publishes chart packages and `index.yaml` to `gh-pages`.
4. Copies `artifacthub-repo.yml` to `gh-pages` for Artifact Hub discovery.

Pull requests run chart-testing lint through `.github/workflows/lint-test.yml`.

## License

Apache-2.0. See [`LICENSE`](./LICENSE).
