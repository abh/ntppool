# NTP Pool Configuration Guide

This document provides comprehensive guidance for configuring the NTP Pool Project across all deployment environments and components.

## Overview

The NTP Pool Project uses a multi-layered configuration system that combines:
- **Environment variables** for core application settings
- **Kubernetes Helm charts** for service deployment configuration
- **HashiCorp Vault** for secrets management
- **Deployment-specific overrides** for different environments (development, test, production)

## Core Configuration System

The core configuration is managed by the Go `config` package (`../go/ntp/common/config/`) which loads settings from environment variables.

### Environment Variables

#### Required Core Settings
```bash
# Deployment environment (devel, test, prod)
deployment_mode=prod

# Web interface hostnames (comma-separated, first is primary)
web_hostname=www.ntppool.org,api.ntppool.org,www.pool.ntp.org

# Management interface hostname
manage_hostname=manage.ntppool.org

# TLS settings for web and management interfaces
web_tls=yes        # Enable HTTPS for web (yes/no/true/false)
manage_tls=yes     # Enable HTTPS for management (yes/no/true/false)
```

#### Application Settings
```bash
# Database connection
db_dsn=dbi:mysql:database=ntppool;host=ntp-db-mysql-master.ntpdb;mysql_enable_utf8=1
db_user=ntppool

# Email configuration
email_default=ask@ntppool.org
email_help=help@ntppool.org
email_notifications=ask@ntppool.org
email_sender=ask@ntppool.org
email_support=server-owner-help@ntppool.org
email_vendors=vendors@ntppool.org

# Pool domain and static assets
pool_domain=pool.ntp.org
static_base=/static/
www_cname=www-lb.ntppool.org.
```

#### Authentication
```bash
# Auth0 integration
auth0_client=kDlOYWYyIQlLMjgyzrKJhQmARaM8rOaM
auth0_domain=login.ntppool.org
```

#### Performance and Infrastructure
```bash
# HTTP server settings
httpd_maxclients=10

# Proxy/CDN configuration
proxyip_configmap=fastly-ips
```

### Deployment Environment Configuration

The system supports three deployment environments with automatic API endpoint resolution:

#### Development (`devel`/`dev`)
- **API Host**: `https://dev-api.ntppool.dev`
- **Management URL**: `https://manage.askdev.grundclock.com`
- **Monitor Domain**: `devel.mon.ntppool.dev`
- **Monitor API**: `https://api.devel.mon.ntppool.dev`

#### Test/Beta (`test`/`beta`)
- **API Host**: `https://beta-api.ntppool.dev`
- **Management URL**: `https://manage.beta.grundclock.com`
- **Monitor Domain**: `test.mon.ntppool.dev`
- **Monitor API**: `https://api.test.mon.ntppool.dev`

#### Production (`prod`)
- **API Host**: `https://api.ntppool.dev`
- **Management URL**: `https://manage.ntppool.org`
- **Monitor Domain**: `mon.ntppool.dev`
- **Monitor API**: `https://api.mon.ntppool.dev`

### Environment Variable Overrides
```bash
# Override default API host for any environment
API_HOST=https://custom-api.example.com
```

## Kubernetes/Helm Configuration

The NTP Pool services are deployed using Helm charts with environment-specific value files.

### Chart Structure
- **Main Chart**: `ntppool-charts/pub/charts/ntppool/`
- **Values Files**: Environment-specific configurations in `ntppool-k8s/`
  - `prod/prod-values.yaml` - Production configuration
  - `devel/dev-values-*.yaml` - Development configurations
  - `beta/beta-values.yaml` - Beta/test configuration

### Service Configuration

#### Main Application (`ntppool`)
```yaml
config:
  deployment_mode: "prod"
  web_hostname: "www.ntppool.org,api.ntppool.org,www.pool.ntp.org"
  manage_hostname: "manage.ntppool.org"
  web_tls: "yes"
  manage_tls: "yes"
  db_dsn: "dbi:mysql:database=ntppool;host=ntp-db-mysql-master.ntpdb;mysql_enable_utf8=1"
  db_user: "ntppool"
  # ... additional config options

replicaCount: 12  # Production scale
resources:
  limits:
    cpu: 1
    memory: 1500Mi
  requests:
    cpu: 200m
    memory: 300Mi
```

#### Supporting Services

**GeoIP Service**
```yaml
geoip:
  enabled: true
  replicaCount: 2
  # Vault integration for MaxMind license
  annotations:
    vault.hashicorp.com/agent-inject-secret-config: "kv/ntppool/geoip/config"
```

**SMTP Service**
```yaml
smtp:
  replicaCount: 2
  config:
    RELAY_NETWORKS: ":10.2.0.0/16:10.3.0.0/16:10.42.0.0/16"
    SMARTHOST_ADDRESS: "smtp.sparkpostmail.com"
    SMARTHOST_PORT: "587"
    SMARTHOST_USER: "SMTP_Injection"
```

**Screensnap Service**
```yaml
screensnap:
  enabled: true
  replicaCount: 2
  upstream_base: https://www.ntppool.org
```

### Scheduled Jobs
```yaml
jobs:
  combust-cleanup:
    enabled: true
    schedule: "12 * * * *"
  db-cleanup:
    enabled: true
    schedule: "17 * * * *"
  server-notifications:
    enabled: true
    schedule: "*/10 * * * *"
  zone-stats:
    enabled: true
    schedule: "57 */4 * * *"
```

### Ingress Configuration
```yaml
ingress:
  enabled: true
  class: haproxy
  types:
    - web
    - manage
    - data-api
  annotations:
    haproxy-ingress.github.io/hsts-max-age: "63072000"
    haproxy-ingress.github.io/hsts-include-subdomains: "true"
    haproxy-ingress.github.io/maxconn-server: "1"
```

## Secrets Management (Vault)

The NTP Pool Project uses HashiCorp Vault for comprehensive secrets management with automatic secret injection into Kubernetes pods.

### Vault Integration Architecture

#### Vault Agent Injection
All production services use Vault Agent for automatic secret injection:
```yaml
podAnnotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-inject-token: "true"
  vault.hashicorp.com/agent-cache-enable: "true"
  vault.hashicorp.com/role: "ntppool-prod"
  vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
  vault.hashicorp.com/tls-secret: "vault-kube-ca"
```

### Secret Categories

#### 1. Database Credentials (Dynamic Secrets)
**Production:**
```yaml
vault.hashicorp.com/agent-inject-secret-database: "/database/creds/ntpdb-prod"
vault.hashicorp.com/agent-inject-template-database: |
  {{- with secret "database/creds/ntpdb-prod" -}}
  {{ .Data | toUnescapedJSON }}
  {{- end }}
```

**Development:**
```yaml
vault.hashicorp.com/agent-inject-secret-database: "/database/creds/ntp-askntp"
```

- **Path**: `/database/creds/{environment-role}`
- **Type**: Dynamic credentials with automatic rotation
- **Access**: JSON file at `/vault/secrets/database.json` in containers
- **Usage**: Application reads from `db_auth_file` config pointing to Vault-injected file

#### 2. Application Secrets
```yaml
secrets:
  # Authentication tokens
  auth0_secret: "Base64-encoded-auth0-secret"
  account_id_key: "Random string for account IDs"
  vendor_zone_id_key: "Random string for vendor zones"

  # Database (legacy/fallback)
  db_pass: "__file__"  # Points to Vault-injected file
  db_auth_file: "/vault/secrets/database.json"

  # SMTP credentials
  smtp_pass: "SMTP service password"
```

#### 3. Third-Party Service Secrets

**GeoIP Configuration (MaxMind)**
```yaml
vault.hashicorp.com/agent-inject-secret-config: "kv/ntppool/geoip/config"
vault.hashicorp.com/agent-inject-template-config: |
  {{ with secret "kv/ntppool/geoip/config" -}}
    export GEOIPUPDATE_ACCOUNT_ID="{{ .Data.data.account_id }}"
    export GEOIPUPDATE_LICENSE_KEY="{{ .Data.data.license_key }}"
  {{- end }}
```

**SMTP Service Configuration**
```yaml
config:
  SMARTHOST_PASSWORD: "145c21af7b4bd672de3c9119fc2ab08c88f99796"  # SparkPost API key
```

#### 4. TLS Certificates
```yaml
vault.hashicorp.com/agent-inject-secret-vault-ca: "/pki_root/cert/ca"
vault.hashicorp.com/agent-inject-template-vault-ca: |
  {{- with secret "pki_root/cert/ca" -}}
  {{ .Data.certificate }}
  {{- end }}
```

### Vault Roles and Policies

#### Environment-Specific Roles
- **Production**: `ntppool-prod`
- **Development**: `ntppool-dev`
- **GeoIP Services**: `ntppool-geoip`

#### Role Configuration
```bash
# Token settings
token_ttl=168h           # 7 days
token_max_ttl=168h       # Maximum 7 days
period=96h               # Must check-in every 4 days
token_num_uses=200       # Token usage limit

# Secret ID settings
secret_id_ttl=26280h     # 3 years
secret_id_num_uses=500   # Usage limit

# Policies
policies=monitor-{environment}
```

### Monitor Authentication System

The NTP Pool uses a custom AppRole-based authentication system for monitoring services:

#### Vault Perl Interface (`lib/NP/Vault.pm`)
- **Vault API**: `https://vault-active.ntpvault.svc:8200/v1`
- **Authentication**: Token-based with TLS client certificates
- **Role Management**: Automatic creation/deletion of monitoring roles
- **Secret Management**: Key-value store for monitoring configuration

#### Monitoring Domains
- **Development**: `devel.mon.ntppool.dev`
- **Test**: `test.mon.ntppool.dev`
- **Production**: `mon.ntppool.dev`

## Environment-Specific Configurations

### Development Environment
```yaml
# Development values (dev-values-ewr1.yaml)
config:
  deployment_mode: devel
  manage_hostname: manage.askdev.grundclock.com
  web_hostname: web.askdev.grundclock.com
  pool_domain: askdev.grundclock.com
  db_dsn: dbi:mysql:database=askntp;host=ntpdb-haproxy.ntpdb.svc.cluster.local
  db_user: askntp

# Resource allocation
replicaCount: 1
resources:
  limits:
    cpu: 2
    memory: 1500Mi
  requests:
    cpu: 10m
    memory: 400Mi

# External secret reference
secrets:
  existingSecret: "ntppool-secrets"
```

### Beta/Test Environment
```yaml
# Beta values (beta-values.yaml)
config:
  deployment_mode: beta
  manage_hostname: manage.ntp.test
  web_hostname: web.ntp.test,graphs.ntp.test
  pool_domain: beta.grundclock.com
  manage_tls: "no"  # Development uses HTTP
  web_tls: "no"
```

### Production Environment
```yaml
# Production values (prod-values.yaml)
config:
  deployment_mode: prod
  manage_hostname: manage.ntppool.org
  web_hostname: www.ntppool.org,api.ntppool.org,www.pool.ntp.org
  pool_domain: pool.ntp.org
  manage_tls: "yes"
  web_tls: "yes"

# High availability configuration
replicaCount: 12
resources:
  limits:
    cpu: 1
    memory: 1500Mi
  requests:
    cpu: 200m
    memory: 300Mi

# Full Vault integration
podAnnotations:
  vault.hashicorp.com/role: "ntppool-prod"
  instrumentation.opentelemetry.io/inject-sdk: "true"
```

## OpenTelemetry Integration

### Tracing Configuration
```yaml
config:
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4318"
  OTEL_BSP_MAX_EXPORT_BATCH_SIZE: "10"
  OTEL_SERVICE_NAME: "ntppool-web"
  OTEL_TRACES_EXPORTER: "otlp"
  OTEL_ATTRIBUTE_COUNT_LIMIT: "256"

podAnnotations:
  instrumentation.opentelemetry.io/inject-sdk: "true"
```

## Security Best Practices

### 1. Secret Management
- **Never commit secrets to repositories** - Use Vault for all sensitive data
- **Rotate database credentials** - Use Vault dynamic secrets for automatic rotation
- **Limit secret access** - Use environment-specific Vault roles and policies
- **Monitor secret usage** - Vault provides audit logs for all secret access

### 2. TLS/HTTPS Configuration
- **Always use TLS in production** - Set `web_tls=yes` and `manage_tls=yes`
- **HSTS headers** - Configured in ingress annotations for enhanced security
- **Certificate management** - Automated via cert-manager and Let's Encrypt

### 3. Network Security
- **Ingress restrictions** - Use HAProxy ingress with connection limits
- **Internal service communication** - Services communicate via cluster-internal DNS
- **Firewall rules** - Network policies restrict inter-pod communication

### 4. Authentication
- **OAuth2/OIDC** - Auth0 integration for user authentication
- **API tokens** - Separate keys for different service integrations
- **Service accounts** - Kubernetes RBAC for pod-level permissions

## Configuration Examples

### Local Development Setup
```bash
# Environment variables for local development
export deployment_mode=devel
export web_hostname=localhost:8000
export manage_hostname=localhost:8001
export web_tls=no
export manage_tls=no
export db_dsn="dbi:mysql:database=ntpdev;host=localhost"
export db_user=ntpdev
export pool_domain=dev.pool.ntp.org
```

### Docker Compose Configuration
```yaml
# docker-compose.yml environment section
environment:
  - deployment_mode=devel
  - web_hostname=web.docker.local
  - manage_hostname=manage.docker.local
  - web_tls=no
  - manage_tls=no
  - db_dsn=dbi:mysql:database=ntppool;host=mysql
  - db_user=ntppool
  - pool_domain=docker.pool.ntp.org
```

### Production Kubernetes Deployment
```bash
# Deploy production configuration
helm install ntppool ntppool-charts/pub/charts/ntppool/ \
  -f ntppool-k8s/prod/prod-values.yaml \
  --namespace ntppool-prod

# Verify Vault integration
kubectl logs -n ntppool-prod deployment/ntppool -c vault-agent

# Check configuration
kubectl get configmap -n ntppool-prod ntppool-config -o yaml
```

## Troubleshooting

### Common Configuration Issues

#### 1. Vault Connection Problems
```bash
# Check Vault agent logs
kubectl logs -n ntppool-prod deployment/ntppool -c vault-agent

# Verify TLS configuration
kubectl get secret -n ntppool-prod vault-kube-ca

# Test Vault connectivity
kubectl exec -it deployment/ntppool -- curl -k https://vault-active.ntpvault.svc:8200/v1/sys/health
```

#### 2. Database Connection Issues
```bash
# Check database credentials
kubectl exec -it deployment/ntppool -- cat /vault/secrets/database.json

# Verify database connectivity
kubectl exec -it deployment/ntppool -- mysql -h ntp-db-mysql-master.ntpdb -u ntppool -p
```

#### 3. Configuration Validation
```bash
# Validate Helm chart values
helm lint ntppool-charts/pub/charts/ntppool/ -f prod-values.yaml

# Test configuration rendering
helm template ntppool ntppool-charts/pub/charts/ntppool/ -f prod-values.yaml

# Check running configuration
kubectl exec -it deployment/ntppool -- env | grep -E "(deployment_mode|hostname|tls)"
```

### Environment Variable Debugging
```perl
# Perl code to debug configuration (in application)
use NP::IntAPI;
my $config = Combust::Config->new;
warn "Deployment mode: " . $config->site->{ntppool}->{deployment_mode};
warn "Web hostname: " . $config->site->{ntppool}->{web_hostname};
```

## Configuration Reference Quick Start

### Essential Environment Variables Checklist
- [ ] `deployment_mode` - Set to `devel`, `test`, or `prod`
- [ ] `web_hostname` - Primary web interface hostname(s)
- [ ] `manage_hostname` - Management interface hostname
- [ ] `web_tls` / `manage_tls` - TLS configuration
- [ ] `db_dsn` - Database connection string
- [ ] `db_user` - Database username
- [ ] Email settings (`email_*` variables)
- [ ] `pool_domain` - NTP pool domain name

### Required Secrets (Vault or Kubernetes)
- [ ] Database credentials (`db_pass` or Vault dynamic secrets)
- [ ] Auth0 secret (`auth0_secret`)
- [ ] Account ID key (`account_id_key`)
- [ ] Vendor zone ID key (`vendor_zone_id_key`)
- [ ] SMTP password (`smtp_pass`)

### Production Deployment Checklist
- [ ] Vault integration configured with proper roles
- [ ] TLS enabled for all external interfaces
- [ ] Resource limits appropriate for load
- [ ] Monitoring and alerting configured
- [ ] Backup and disaster recovery tested
- [ ] Security scanning completed
- [ ] Performance testing validated

For additional support, contact ask@ntppool.org or refer to the project documentation at https://dev.ntppool.org/
