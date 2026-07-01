# Socket Firewall Helm Chart

Kubernetes Helm chart for deploying the Socket.dev Registry Firewall. Blocks vulnerable and malicious packages before they reach your cluster.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- Socket.dev API token with scopes: `packages`, `entitlements:list`
  - Create at: Socket Dashboard → Settings → API Tokens

## Quick Start

```bash
# Add your Socket API token
export SOCKET_API_TOKEN="your-token-here"

# Install with path-based routing (recommended)
helm install socket-firewall . \
  --namespace socket-firewall --create-namespace \
  --set socket.apiToken=$SOCKET_API_TOKEN \
  --set pathRouting.enabled=true \
  --set pathRouting.domain=sfw.company.com \
  --set 'pathRouting.routes[0].path=/npm' \
  --set 'pathRouting.routes[0].upstream=https://registry.npmjs.org' \
  --set 'pathRouting.routes[0].registry=npm' \
  --set 'pathRouting.routes[1].path=/pypi' \
  --set 'pathRouting.routes[1].upstream=https://pypi.org' \
  --set 'pathRouting.routes[1].registry=pypi'

# Verify deployment
kubectl get pods -n socket-firewall -l app.kubernetes.io/name=socket-firewall

# Port-forward for testing
kubectl port-forward svc/socket-firewall 8443:443 -n socket-firewall

# Test health
curl -sk https://localhost:8443/health

# Test npm through the firewall
npm install express --registry https://localhost:8443/npm/ --strict-ssl=false
```

For simpler installs, use a values file instead of `--set` flags. See [examples/](examples/) for ready-made configs.

## Configuration

### Required

| Parameter | Description |
|-----------|-------------|
| `socket.apiToken` | Socket.dev API token |

### Registry Configuration

**Path-based routing (recommended):** A single domain with path prefixes for each registry.

```yaml
pathRouting:
  enabled: true
  domain: sfw.company.com
  routes:
    - path: /npm
      upstream: https://registry.npmjs.org
      registry: npm
    - path: /pypi
      upstream: https://pypi.org
      registry: pypi
    - path: /maven
      upstream: https://repo1.maven.org/maven2
      registry: maven
```

**Domain-based routing (alternative):** Each registry gets its own subdomain.

```yaml
registries:
  npm:
    enabled: true
    domains:
      - npm.internal.example.com
  pypi:
    enabled: true
    domains:
      - pypi.internal.example.com
```

### All Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Docker image | `socketdev/socket-registry-firewall` |
| `image.tag` | Image tag. Empty means track the chart's `appVersion` (single source of truth). Set to override. | `""` |
| `image.pullPolicy` | Image pull policy | `Always` |
| `replicaCount` | Number of replicas (ignored if autoscaling enabled) | `1` |
| `socket.apiToken` | Socket API token | `""` |
| `socket.existingSecret` | Use existing secret | `""` |
| `socket.failOpen` | Allow downloads if API unavailable | `true` |
| `socket.cacheTtl` | Cache TTL in seconds | `600` |
| `socket.logLevel` | Log level (error, warn, info, debug) | `""` (info) |
| **Path-Based Routing** | | |
| `pathRouting.enabled` | Enable path-based routing | `false` |
| `pathRouting.domain` | Domain for path routing | `""` |
| `pathRouting.configMode` | Config mode: upstream, middle, or omit for downstream | `""` |
| `pathRouting.routes` | List of path/upstream/registry route objects | `[]` |
| **DNS Override Mode** | | |
| `dnsRouting.enabled` | Enable DNS override (transparent proxy) mode | `false` |
| `dnsRouting.registries` | List of registries to route via DNS override (npm, pypi, maven, cargo, rubygems, openvsx, nuget, go, conda) | `[]` |
| **Domain-Based Routing** | | |
| `registries.<name>.enabled` | Enable registry (npm, pypi, maven, etc.) | `false` |
| `registries.<name>.domains` | Custom domains for registry | `[]` |
| **Integrations** | | |
| `metadataFiltering.enabled` | Filter blocked packages from metadata | `false` |
| `metadataFiltering.prefetchEnabled` | Warm metadata decisions in the background (CE-274). Empty = firewall default | `""` |
| `metadataFiltering.maxConcurrent` | Per-worker concurrent metadata filter ops | `""` |
| `metadataFiltering.packageFilterTimeout` | Time budget (s) per metadata filter op | `""` |
| `externalRegistryCooldown.enabled` | Publish-date enforcement for unsupported ecosystems (e.g. gradle) | `false` |
| `externalRegistryCooldown.cooldownPeriod` | Block packages published more recently than this (e.g. `7d`) | `""` |
| `externalRegistryCooldown.registries` | External registries to monitor (name/url/ecosystem/auth) | `[]` |
| `externalRegistryCooldown.privateRegistry.enabled` | Cooldown queries against a private (Artifactory/Nexus) registry | `false` |
| `redis.enabled` | Enable Redis caching for API lookups | `false` |
| `redis.sslServerName` | TLS SNI name for managed Redis | `""` |
| `splunk.enabled` | Enable Splunk HEC integration | `false` |
| `webhook.enabled` | Enable webhook event delivery | `false` |
| **Config tuning** | | |
| `socket.blockLogLevel` / `warnLogLevel` / `monitorLogLevel` / `ignoreLogLevel` | Per-action SOCKET_DECISION log levels. Empty = firewall default | `""` |
| `socket.cacheRevalidationJitterSeconds` | Stale-while-revalidate jitter (CE-274). Empty = firewall default | `""` |
| `socket.cacheRevalidationAsync` | Revalidate cache entries asynchronously. Empty = firewall default | `""` |
| `nginx.resolver` | DNS resolver for upstream name resolution | `""` |
| **Raw config passthrough** | _see [Configuration coverage](#configuration-coverage-value-managed-vs-passthrough)_ | |
| `socket.extraConfig` | Map deep-merged over the generated `socket.yml` (wins on conflicts) | `{}` |
| `socket.configOverride` | Map that replaces `socket.yml` wholesale (ignores all other values) | `{}` |
| **Infrastructure** | | |
| `tls.generateSelfSigned` | Generate self-signed certs | `true` |
| `tls.existingSecret` | Use existing TLS secret | `""` |
| `service.type` | Service type | `ClusterIP` |
| `ingress.enabled` | Enable Ingress | `false` |
| `ingress.className` | Ingress class (nginx, alb, traefik) | `""` |
| `autoscaling.enabled` | Enable HorizontalPodAutoscaler | `false` |
| `podDisruptionBudget.enabled` | Keep pods available during node maintenance | `true` |
| `topologySpreadConstraints` | Evenly spread replicas across zones/nodes | `[]` |
| `extraContainers` | Sidecar containers (auth proxies, log collectors) | `[]` |
| `resources.limits.cpu` | CPU limit | `4` |
| `resources.limits.memory` | Memory limit | `8Gi` |
| `terminationGracePeriodSeconds` | Pod grace period; set ≥ `forwardProxy.maxTunnelLifetimeSeconds` when CONNECT is enabled | `""` (30s) |
| **Forward Proxy (HTTP CONNECT)** | _CASB CONNECT tunnels — see [section below](#forward-proxy-http-connect)_ | |
| `forwardProxy.enabled` | Enable the CONNECT listener (requires image ≥ 1.1.275) | `false` |
| `forwardProxy.port` | CONNECT listener port | `3128` |
| `forwardProxy.maxTunnelLifetimeSeconds` | Hard cap on a single tunnel's lifetime | `600` |
| `forwardProxy.maxConnectionsPerSource` | Per-source-IP concurrent tunnel cap | `64` |
| `forwardProxy.proxyProtocolPort` | Internal loopback PROXY-protocol port | `8081` |
| `forwardProxy.skipStreamLuaCheck` | Bypass nginx stream-lua capability check (custom images only) | `false` |
| `forwardProxy.service.enabled` | Create a dedicated L4 Service for CONNECT (required to expose it externally) | `false` |
| `forwardProxy.service.type` | `LoadBalancer` (NLB) or `NodePort` — **not** behind an ALB/L7 ingress | `LoadBalancer` |
| `forwardProxy.service.annotations` | Annotations for the L4 Service (e.g. AWS NLB) | `{}` |
| `forwardProxy.service.loadBalancerSourceRanges` | CIDRs allowed to reach the CONNECT listener (your CASB egress) | `[]` |
| **Security** | | |
| `securityContext` | Container security context | PSS restricted (see values.yaml) |
| `podSecurityContext` | Pod-level security context | `{}` |
| `initContainers.copyApp.securityContext` | copy-app init container security context | PSS restricted |
| `initContainers.certGenerator.securityContext` | generate-certs init container security context | PSS restricted |

See [values.yaml](values.yaml) for all options.

### Configuration Coverage (value-managed vs passthrough)

The chart renders the firewall's `socket.yml` at `/app/socket.yml`. Keys fall
into two buckets:

- **Value-managed** — exposed as first-class Helm values (the tables above and
  in `values.yaml`). Covers the common `socket`, `cache`, `proxy`, `nginx`,
  routing (`pathRouting` / `registries` / `dnsRouting`), `metadataFiltering`,
  `externalRegistryCooldown`, `redis`, `splunk`, `webhook`, `lua`, `clientIp`,
  and `forwardProxy` settings.
- **Passthrough** — any key in the authoritative
  [`socket.defaults.yml`](tests/socket.defaults.yml) reference that the chart
  does not (yet) expose as a value. Set these via `socket.extraConfig` (deep
  merge) or `socket.configOverride` (wholesale replace). This means the chart
  can render an **arbitrary, complete `socket.yml` with zero dropped keys** —
  no kustomize post-render step required.

**`socket.extraConfig`** — deep-merged over the generated config, so you keep
all the value-managed keys and only add/override what you need:

```yaml
socket:
  extraConfig:
    socket:
      api_url: https://api.socket.internal
      outbound_proxy: http://proxy.corp:3128
      no_proxy: .corp,.svc
    ports:
      disable_http: true          # not reachable via service.* alone
    ssl:
      ca_cert: /etc/nginx/ssl/corp-ca.pem
    nginx:
      gzip:
        enabled: "on"
      proxy_cache:
        enabled: "on"
```

**`socket.configOverride`** — replaces `socket.yml` entirely (every other
config-feeding value is ignored). Use it to pin an exact, audited config:

```yaml
socket:
  configOverride:
    socket:
      api_url: https://api.socket.dev
      fail_open: false
    cache:
      ttl: 600
    # ... a full socket.yml ...
```

The vendored [`socket.defaults.yml`](tests/socket.defaults.yml) documents every
key. A CI check (`tests/validate_config_coverage.py`) renders the chart against
it to guarantee no keys are dropped.

> Note on merge semantics: `extraConfig` deep-merges maps but **replaces lists**
> wholesale (e.g. `pathRouting.routes`). YAML-magic scalars like `on`/`off` are
> quoted (`"on"`) so they survive as strings.

### Raw Kubernetes Manifests (no Helm)

Pre-rendered manifests for a representative deployment live in
[`rendered/`](rendered/) for operators who deploy with `kubectl` instead of
Helm, and as a reviewable reference of what the chart produces:

```bash
kubectl apply -f rendered/socket-firewall.yaml
```

Regenerate them after chart changes with `rendered/generate.sh`.

### Example Configurations

Pre-built configurations for common deployment scenarios:

```bash
# Corporate network (internal DNS + corp CA)
helm install socket-firewall . -f examples/corporate.yaml \
  --set socket.apiToken=$SOCKET_API_TOKEN

# Remote-first (public domain + MDM-pushed configs)
helm install socket-firewall . -f examples/remote-first.yaml \
  --set socket.apiToken=$SOCKET_API_TOKEN \
  --set ingress.hosts[0].host=sfw.yourcompany.com
```

## Proxy Modes

### Path-Based Routing (Recommended)

A single domain serves all registries via URL path prefixes. Simplest to deploy and manage.

```yaml
pathRouting:
  enabled: true
  domain: sfw.company.com
  routes:
    - path: /npm
      upstream: https://registry.npmjs.org
      registry: npm
    - path: /pypi
      upstream: https://pypi.org
      registry: pypi
    - path: /maven
      upstream: https://repo1.maven.org/maven2
      registry: maven
```

| Registry | Path | Upstream |
|----------|------|----------|
| npm | `/npm/` | `registry.npmjs.org` |
| PyPI | `/pypi/` | `pypi.org` |
| Maven | `/maven/` | `repo1.maven.org/maven2` |
| Cargo | `/cargo/` | `index.crates.io` |
| RubyGems | `/rubygems/` | `rubygems.org` |
| NuGet | `/nuget/` | `api.nuget.org` |
| Go | `/go/` | `proxy.golang.org` |
| Conda | `/conda/` | `conda.anaconda.org` |

### Domain-Based Routing

Each registry gets its own subdomain. Use when `pathRouting.enabled` is `false`.

```yaml
registries:
  npm:
    enabled: true
    domains:
      - npm.company.internal
```

Then configure your package manager to use `https://npm.company.internal/`.

### DNS Override Mode (Transparent Proxy)

Point internal DNS for public registry domains directly at the firewall IP. No package manager configuration needed, but requires DNS control and trusted TLS certificates matching registry domains.

```yaml
dnsRouting:
  enabled: true
  registries:
    - npm
    - pypi
    - maven
```

Or via `--set` flags:

```bash
helm install socket-firewall . \
  --set socket.apiToken=$SOCKET_API_TOKEN \
  --set dnsRouting.enabled=true \
  --set 'dnsRouting.registries={npm,pypi,maven}'
```

**Required DNS entries** (create A or CNAME records pointing to the firewall IP):

| Registry | Hostnames to reroute |
|----------|---------------------|
| npm | `registry.npmjs.org` |
| PyPI | `pypi.org`, `files.pythonhosted.org` |
| Maven | `repo1.maven.org`, `repo.maven.apache.org` |
| Cargo | `index.crates.io` |
| RubyGems | `rubygems.org` |
| NuGet | `api.nuget.org` |
| Go | `proxy.golang.org` |
| OpenVSX | `open-vsx.org` |
| Conda | `conda.anaconda.org` |

**Combining with path routing:** DNS override and path routing can be enabled together for hybrid deployments. For example, use path routing for CI/CD systems that can be reconfigured, and DNS override for developer laptops that should work without configuration changes.

## Using with Package Managers

Replace `sfw.company.com` with your firewall domain. These examples use path-based routing. For domain-based routing, replace the full URL with your custom domain (e.g., `https://npm.company.internal/`).

### npm / yarn / pnpm

```bash
npm config set registry https://sfw.company.com/npm/

# If using self-signed certificates
npm config set strict-ssl false
# Or trust the CA certificate
npm config set cafile /path/to/socket-ca.crt
```

`.npmrc` (push via MDM):
```
registry=https://sfw.company.com/npm/
```

### pip (PyPI)

```bash
pip config set global.index-url https://sfw.company.com/pypi/simple/
pip config set global.trusted-host sfw.company.com
```

`pip.conf` (push via MDM):
```ini
[global]
index-url = https://sfw.company.com/pypi/simple/
```

### Maven

Add to `~/.m2/settings.xml`:
```xml
<mirrors>
  <mirror>
    <id>socket-central</id>
    <url>https://sfw.company.com/maven/</url>
    <mirrorOf>central</mirrorOf>
  </mirror>
</mirrors>
```

### NuGet (dotnet)

```bash
dotnet nuget add source https://sfw.company.com/nuget/v3/index.json -n socket-firewall
```

`NuGet.Config`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="socket-firewall" value="https://sfw.company.com/nuget/v3/index.json" />
  </packageSources>
</configuration>
```

### Go

```bash
export GOPROXY=https://sfw.company.com/go/,direct

# For self-signed certificates
export GOINSECURE=sfw.company.com
```

### Cargo

```toml
# ~/.cargo/config.toml
[registries.socket]
index = "sparse+https://sfw.company.com/cargo/"
```

## Ingress Configuration

Expose the firewall externally using an Ingress controller.

### nginx Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
  hosts:
    - host: sfw.company.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: sfw-tls
      hosts:
        - sfw.company.com
```

### AWS ALB Ingress

> An ALB cannot carry the HTTP CONNECT method. For CASB CONNECT tunnels, see
> [Forward Proxy (HTTP CONNECT)](#forward-proxy-http-connect).

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
  hosts:
    - host: sfw.company.com
      paths:
        - path: /
          pathType: Prefix
```

### Transparent Proxy (Multiple Hosts)

Route multiple registry domains through the firewall:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
  hosts:
    - host: registry.npmjs.org
      paths:
        - path: /
          pathType: Prefix
    - host: pypi.org
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: registry-tls
      hosts:
        - registry.npmjs.org
        - pypi.org
```

## Forward Proxy (HTTP CONNECT)

Some CASBs (e.g. Netskope or Zscaler in proxy-chaining mode) reach upstream
proxies via an HTTP `CONNECT` tunnel instead of a standard HTTPS request. Enable
the firewall's CONNECT listener with `forwardProxy.enabled` (requires image
≥ 1.1.275).

Because `CONNECT` is a raw TCP tunnel, it cannot pass through a Layer-7 Ingress
(nginx, Traefik, AWS ALB) — those terminate TLS and parse HTTP. Expose it with a
**Layer-4 (TCP passthrough) load balancer** by setting
`forwardProxy.service.enabled=true`, which creates a dedicated Service for the
CONNECT port. Your existing Ingress/Service keeps serving normal HTTPS traffic.

```yaml
forwardProxy:
  enabled: true
  service:
    enabled: true
    type: LoadBalancer   # must be L4 (TCP passthrough), not an L7 ingress
```

See [`examples/forward-proxy.yaml`](examples/forward-proxy.yaml) for a complete
example.

## TLS Configuration

### Self-Signed (Default)

The chart generates self-signed certificates automatically. Extract the CA cert:

```bash
POD=$(kubectl get pod -l app.kubernetes.io/name=socket-firewall -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /etc/nginx/ssl/ca.crt > socket-ca.crt
```

### Existing Certificate

```yaml
tls:
  generateSelfSigned: false
  existingSecret: my-tls-secret  # must contain tls.crt and tls.key
```

### cert-manager

Create a Certificate resource and reference the secret:

```yaml
tls:
  generateSelfSigned: false
  existingSecret: socket-firewall-tls
  certManager: true
```

`certManager: true` remaps `tls.crt` to `fullchain.pem` and `tls.key` to `privkey.pem`,
which are the filenames nginx expects.

By default the chart also projects `ca.crt` from the secret. ACME issuers like Let's
Encrypt don't populate `ca.crt` (the chain is in `tls.crt`), so set `includeCaCrt: false`
to skip it:

```yaml
tls:
  generateSelfSigned: false
  existingSecret: socket-firewall-tls
  certManager: true
  includeCaCrt: false
```

Keep `includeCaCrt: true` (the default) for CA, SelfSigned, or Vault issuers if you want
the CA cert mounted at `/etc/nginx/ssl/ca.crt` for client trust extraction.

## Autoscaling

Enable horizontal pod autoscaling to handle variable load:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80  # optional
```

When enabled, the HorizontalPodAutoscaler manages replica count based on CPU and/or memory utilization. The `replicaCount` value is ignored.

**Requirements:**
- Kubernetes metrics-server must be installed
- Resource requests must be set (they are by default)

**Verify autoscaling:**
```bash
kubectl get hpa socket-firewall
kubectl describe hpa socket-firewall
```

## Spreading Replicas Across Zones

When you run more than one replica (via `replicaCount` or autoscaling), use
`topologySpreadConstraints` to distribute pods evenly across availability zones
(or nodes) so a single zone/node failure can't take down a disproportionate share
of the fleet. This is preferred over soft pod anti-affinity, which the scheduler is
free to ignore and can pile replicas into one zone.

```yaml
replicaCount: 3
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway   # best-effort even spread; never blocks scheduling
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: socket-firewall
```

- `maxSkew: 1` keeps zones within one pod of each other.
- `whenUnsatisfiable: ScheduleAnyway` is a soft guarantee (recommended). Use
  `DoNotSchedule` for a hard guarantee — but be aware pods can stay `Pending` if a
  zone is full or you have fewer zones than replicas.
- Pin spreading to a specific revision by adding `matchLabelKeys: [pod-template-hash]`
  (requires Kubernetes 1.27+, satisfied by all currently-supported EKS and GKE versions).

**Compatibility:** `topologySpreadConstraints` is GA since Kubernetes 1.19, so it works
on every currently-supported cluster. The chart sets no `kubeVersion` floor.

## Using an Existing Secret for API Token

```bash
# Create secret
kubectl create secret generic socket-api-token \
  --from-literal=SOCKET_SECURITY_API_TOKEN=your-token

# Reference in values
helm install socket-firewall . \
  --set socket.existingSecret=socket-api-token
```

**Note:** If you update the API token, restart the deployment to pick up the new value:

```bash
kubectl rollout restart deployment/socket-firewall
```

## Redis Cache

Enable an external Redis cache for Socket API lookups when running multiple firewall replicas. Without Redis, each pod maintains its own in-memory cache.

```yaml
redis:
  enabled: true
  host: redis.default.svc.cluster.local
  port: 6379
  existingSecret: redis-credentials
  existingSecretKey: REDIS_PASSWORD
```

### Redis TLS

For Redis instances that require TLS (managed services like GCP Memorystore, AWS ElastiCache with in-transit encryption, or Azure Cache), enable `redis.ssl`.

If the Redis server uses a CA that isn't in the system trust store (this is the default for **GCP Memorystore**, which uses a per-instance private CA), provide the CA via an existing Kubernetes secret. The chart mounts it as a file at a known path inside the container.

```bash
# Store the CA cert in a secret
kubectl create secret generic redis-ca \
  --from-file=ca.crt=/path/to/redis-ca.pem
```

```yaml
redis:
  enabled: true
  host: 10.0.0.5
  port: 6379
  ssl: true
  sslVerify: true
  sslCaCertExistingSecret: redis-ca
  sslCaCertExistingSecretKey: ca.crt   # default
```

For mutual TLS, add the client cert and key the same way:

```yaml
redis:
  ssl: true
  sslCaCertExistingSecret: redis-ca
  sslClientCertExistingSecret: redis-client
  sslClientCertExistingSecretKey: client.crt
  sslClientKeyExistingSecret: redis-client
  sslClientKeyExistingSecretKey: client.key
```

The `sslCaCert`, `sslClientCert`, and `sslClientKey` fields remain available as raw file paths if you are delivering the cert files via your own volume or init container.

## Deployment Recommendations

### Corporate Network (On-Prem or VPN)

**Best approach: Internal DNS + Corporate CA**

Zero configuration required on developer laptops.

1. **Deploy the firewall** with `service.type=LoadBalancer` or behind an Ingress
2. **Internal DNS** resolves public registry domains to the firewall IP:
   ```
   registry.npmjs.org  →  10.0.0.50 (firewall IP)
   pypi.org            →  10.0.0.50
   crates.io           →  10.0.0.50
   ```
3. **Use a corporate CA certificate** that's already trusted on managed devices:
   ```yaml
   tls:
     generateSelfSigned: false
     existingSecret: corporate-wildcard-tls
   ```

**Result:** Developers run `npm install` as normal. Traffic routes through the firewall automatically.

**Tradeoff:** Only works when developers are on corporate network or VPN.

### Remote-First Companies

**Best approach: Custom domain + MDM-pushed configs**

For companies without a corporate network or VPN requirement.

1. **Deploy the firewall** with a public domain (e.g., `sfw.company.com`)
2. **Use a real SSL certificate** (Let's Encrypt via cert-manager, or commercial CA):
   ```yaml
   tls:
     generateSelfSigned: false
     existingSecret: sfw-company-com-tls
   ```
3. **Push package manager configs via MDM** (Jamf, Intune, etc.):

   `.npmrc`:
   ```
   registry=https://sfw.company.com/npm/
   ```

   `pip.conf`:
   ```ini
   [global]
   index-url = https://sfw.company.com/pypi/simple/
   ```

**Result:** Works from anywhere (home, coffee shop, office). No VPN required.

**Tradeoff:** Requires pushing 4-6 config files per laptop via endpoint management.

### Comparison

| Approach | Laptop Config | Works Remote | VPN Required |
|----------|---------------|--------------|--------------|
| Internal DNS + Corp CA | None | No | Yes |
| MDM + Custom Domain | Package manager configs | Yes | No |
| MDM + Transparent Proxy | /etc/hosts + cert trust | No | Yes |

### Security Considerations

- **Restrict access** to the firewall if exposed publicly (IP allowlist, VPN, or Zero Trust)
- **Use real certificates** in production to avoid cert trust issues
- **Monitor blocked packages** via the `/socket-stats` endpoint or Socket dashboard

## Pod Security Standards

The chart defaults to Pod Security Standards (PSS) **restricted** profile. All containers (including init containers) ship with:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

The firewall image writes configuration files to `/app/` at startup and nginx needs writable paths for cache, PID, and log files. The chart handles this with emptyDir volumes:

| Volume | Mount Path | Purpose |
|--------|-----------|---------|
| `app-data` | `/app` | Config generator output (config.env, resolvers.conf, nginx.conf) |
| `nginx-cache` | `/var/cache/nginx` | Proxy cache |
| `nginx-run` | `/var/run` | nginx PID file |
| `nginx-logs` | `/var/log/nginx` | Log files |
| `tmp` | `/tmp` | Config tool binary unpacking |

A `copy-app` init container copies the image's `/app/` contents to the writable emptyDir before the main container starts. The configmap mount at `/app/socket.yml` overlays on top.

To relax security for non-PSS clusters:

```yaml
securityContext: {}
initContainers:
  copyApp:
    securityContext: {}
  certGenerator:
    securityContext: {}
```

## Uninstall

```bash
helm uninstall socket-firewall
```

## Support

- [Socket.dev Documentation](https://docs.socket.dev)
