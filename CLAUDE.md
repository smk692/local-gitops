# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mac Mini M4 프로덕션급 Kubernetes 인프라 프로젝트. k3d 기반 로컬 Kubernetes 환경에서 Kafka, PostgreSQL, 모니터링 스택을 운영합니다.

**핵심 원칙**: TDD 기반 개발 - 모든 서비스는 테스트 환경에서 검증 후 프로덕션 적용

## Critical Architecture Notes

### k3d 클러스터 구성

클러스터명: `macmini-cluster`

**포트 매핑** (k3d 생성 시 설정됨):
- `8080` → 클러스터 80 (HTTP Ingress)
- `8443` → 클러스터 443 (HTTPS Ingress)
- `6550` → 클러스터 6443 (Kubernetes API)

**Ingress Controller**: nginx-ingress (kube-system namespace)

### Bitnami Chart Version Compatibility (2025-10-26 검증됨)

**Kafka 배포시 필수 사항**:
- Helm Chart: **31.5.0** (Kafka 3.9.0용)
- Image: `bitnamilegacy/kafka:3.9.0-debian-12-r12`
- Chart 32.x는 Kafka 4.0용이므로 3.9.x 이미지와 호환 불가
- `global.security.allowInsecureImages: true` 필수 (legacy 이미지 사용)

**PostgreSQL 배포시**:
- Helm으로 배포하지 않고 k8s manifest 직접 사용
- Namespace: `database` (infra가 아님!)
- 별도 디렉토리: `/Users/sonmingi/Desktop/database/`
- 스키마 기반 dev/prod 환경 분리 (단일 DB, 스키마로 격리)

### KRaft Mode Configuration

Kafka는 ZooKeeper 없이 KRaft 모드로 실행:
- Single broker combined mode (controller + broker)
- `kraftVersion: 0` (static quorum for Kafka 3.x)
- `controller.extraConfig`로 quorum voters 직접 주입 필요
- 환경변수: `KAFKA_CFG_CONTROLLER_QUORUM_VOTERS` 설정 필수

### Namespace Structure

```
infra/      - Kafka, Kafka UI
database/   - PostgreSQL, pgAdmin
backend/    - 백엔드 서비스
frontend/   - 프론트엔드 서비스
monitoring/ - Loki, Promtail, Grafana, Prometheus
argocd/     - ArgoCD GitOps (선택)
cert-manager/ - TLS 인증서 관리 (선택)
```

## Project Structure (2025-11 Updated)

```
infra/
├── k3d/
│   └── k3d-config.yaml          # 선언적 k3d 클러스터 설정
├── helm/
│   ├── kafka-values.yaml        # Kafka Helm values
│   ├── loki-values.yaml         # Loki + Grafana (데이터소스 자동 설정)
│   ├── prometheus-values.yaml   # Prometheus values
│   ├── ingress-nginx-values.yaml # NGINX Ingress values
│   ├── cert-manager-values.yaml # cert-manager values
│   ├── argocd-values.yaml       # ArgoCD values
│   └── profiles/                # 리소스 프로파일 (8gb, 16gb, 32gb)
├── k8s/
│   ├── namespaces/
│   ├── cert-manager/            # TLS 인증서 설정
│   │   ├── cluster-issuer.yaml
│   │   └── certificates.yaml
│   └── argocd/                  # ArgoCD Applications
│       └── apps/
├── scripts/
│   ├── lib/                     # 공통 라이브러리
│   │   ├── common.sh            # 로깅, 체크포인트, 유틸리티
│   │   ├── k3d.sh               # k3d 관리 함수
│   │   └── validation.sh        # 검증 함수
│   ├── phases/                  # 단계별 배포 스크립트
│   │   ├── 01-cluster.sh        # k3d, Helm repos, namespaces, ingress
│   │   ├── 02-infra.sh          # Kafka, Kafka UI
│   │   ├── 03-database.sh       # PostgreSQL, pgAdmin, schemas
│   │   ├── 04-monitoring.sh     # Loki, Promtail, Grafana, Prometheus
│   │   ├── 05-apps.sh           # Backend, Frontend, Ingress routes
│   │   ├── 06-tls.sh            # cert-manager, Let's Encrypt
│   │   └── 07-argocd.sh         # ArgoCD GitOps
│   ├── utils/
│   │   ├── health-check.sh      # 종합 상태 확인
│   │   └── setup-hosts.sh       # /etc/hosts 자동 설정
│   ├── deploy-all.sh            # 통합 배포 (Phase 기반)
│   └── install-k3s.sh           # k3d 클러스터 설치
└── secrets/
    ├── templates/               # Secret 템플릿
    │   ├── postgres-secret.yaml.tpl
    │   ├── pgadmin-secret.yaml.tpl
    │   ├── postgres-exporter-secret.yaml.tpl
    │   └── grafana-secret.yaml.tpl
    ├── generate-secrets.sh      # Secret 생성/관리
    └── .env                     # 비밀번호 (gitignore)
```

## Common Commands

### 전체 인프라 배포 (Phase 기반)

```bash
cd /Users/sonmingi/Desktop/infra/scripts

# 전체 배포 (Phase 1-5)
./deploy-all.sh

# 자동 확인 없이 배포
./deploy-all.sh -y

# 중단된 배포 재개
./deploy-all.sh --resume

# 특정 Phase만 실행
./deploy-all.sh -p 2  # Phase 2: Infrastructure (Kafka)

# TLS + ArgoCD 포함 전체 배포
ENABLE_TLS=true ENABLE_ARGOCD=true ./deploy-all.sh -y

# 현재 배포 상태 확인
./deploy-all.sh --status

# 사전 요구사항만 검증
./deploy-all.sh --validate

# 체크포인트 초기화 후 새로 배포
./deploy-all.sh --clean
```

**배포 Phase 순서**:
1. **Phase 1**: Cluster Setup (k3d, Helm repos, namespaces, ingress)
2. **Phase 2**: Infrastructure (Kafka, Kafka UI)
3. **Phase 3**: Database (PostgreSQL, pgAdmin, schemas)
4. **Phase 4**: Monitoring (Loki, Promtail, Grafana, Prometheus)
5. **Phase 5**: Applications (Backend, Frontend, Ingress routes)
6. **Phase 6**: TLS (cert-manager, Let's Encrypt) - 선택적
7. **Phase 7**: ArgoCD (GitOps) - 선택적

### 개별 Phase 스크립트 실행

```bash
cd /Users/sonmingi/Desktop/infra/scripts

# Phase 1: 클러스터 설정
source lib/common.sh && source phases/01-cluster.sh && phase_01_cluster

# Phase 2: Kafka 인프라
source lib/common.sh && source phases/02-infra.sh && phase_02_infrastructure

# Phase 6: TLS 설정
source lib/common.sh && source phases/06-tls.sh && phase_06_tls

# Phase 7: ArgoCD 설정
source lib/common.sh && source phases/07-argocd.sh && phase_07_argocd
```

### 유틸리티 명령어

```bash
cd /Users/sonmingi/Desktop/infra/scripts

# /etc/hosts 자동 설정
sudo ./utils/setup-hosts.sh add       # hosts 항목 추가
./utils/setup-hosts.sh check          # 현재 설정 확인
sudo ./utils/setup-hosts.sh remove    # hosts 항목 제거

# 종합 상태 확인
./utils/health-check.sh
```

### 레거시 개별 스크립트 (하위 호환)

```bash
cd /Users/sonmingi/Desktop/infra/scripts

# k3s 클러스터 설치
./install-k3s.sh

# Kafka 배포
./deploy-kafka.sh

# 모니터링 배포
./deploy-monitoring.sh

# Prometheus 배포
./deploy-prometheus.sh
```

### 상태 확인

```bash
# 모든 Pod 상태
kubectl get pods --all-namespaces

# 특정 네임스페이스
kubectl get pods -n infra      # Kafka
kubectl get pods -n database   # PostgreSQL, pgAdmin
kubectl get pods -n monitoring # Grafana, Prometheus, Loki

# 로그 확인
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> -c <container-name>

# 서비스 및 Ingress
kubectl get svc --all-namespaces
kubectl get ingress --all-namespaces

# Helm 릴리스 확인
helm list --all-namespaces
```

### 리소스 사용량

```bash
kubectl top nodes
kubectl top pods --all-namespaces
kubectl top pods -n infra
```

### Helm 관리

```bash
# 설치된 릴리스 확인
helm list -n infra

# 릴리스 업그레이드
helm upgrade kafka bitnami/kafka --version 31.5.0 \
  -n infra -f helm/kafka-values.yaml

# 릴리스 삭제
helm uninstall kafka -n infra
```

## TDD Workflow

### 1. 테스트 환경 준비

```bash
# 테스트용 네임스페이스 생성
kubectl create namespace test

# 테스트 리소스 배포
kubectl apply -f k8s/backend/ -n test
```

### 2. 서비스 검증

```bash
# Pod 상태 확인
kubectl get pods -n test
kubectl describe pod <pod-name> -n test

# 로그 실시간 확인
kubectl logs -f <pod-name> -n test

# 서비스 연결 테스트
kubectl run test-client --rm -it --restart=Never \
  --image=curlimages/curl:latest -n test \
  -- curl http://service-name:port/health
```

### 3. 프로덕션 적용

검증 완료 후에만:
```bash
kubectl apply -f k8s/backend/ -n backend
kubectl apply -f k8s/frontend/ -n frontend
```

## Configuration Files

### Helm Values 우선순위

1. `helm/profiles/{8gb|16gb|32gb}-profile.yaml` - 리소스 프로파일
2. `helm/kafka-values.yaml` - Kafka 설정
3. `helm/postgres-values.yaml` - PostgreSQL 설정
4. `helm/loki-values.yaml` - Loki + Grafana 설정 (데이터소스, 대시보드 포함)
5. `helm/prometheus-values.yaml` - Prometheus 설정
6. `helm/ingress-nginx-values.yaml` - NGINX Ingress Controller 설정
7. `helm/cert-manager-values.yaml` - cert-manager 설정 (선택적)
8. `helm/argocd-values.yaml` - ArgoCD 설정 (선택적)

### Kafka Values 구조

```yaml
global.security.allowInsecureImages: true  # Legacy 이미지 허용
image.repository: bitnamilegacy/kafka
image.tag: "3.9.0-debian-12-r12"
controller:
  combinedMode.enabled: true
  extraConfig: |
    controller.quorum.voters=...
kraft:
  enabled: true
  kraftVersion: 0
  controllerQuorumVoters: "..."
```

### PostgreSQL Values 구조

```yaml
architecture: standalone
primary:
  resources: {...}
  pgBouncer.enabled: true
  extendedConfiguration: |
    max_connections = 150
    shared_buffers = 512MB
```

## Known Issues & Solutions

### Kafka 배포 실패

**증상**: `controller.quorum.voters is not set`
**원인**: Chart 버전과 이미지 버전 불일치
**해결**:
1. Chart 31.5.0 사용 확인
2. `controller.extraConfig`로 quorum voters 직접 설정
3. `KAFKA_CFG_CONTROLLER_QUORUM_VOTERS` 환경변수 설정

### pgAdmin CrashLoopBackOff

**증상**: `PGADMIN_DEFAULT_EMAIL and PGADMIN_DEFAULT_PASSWORD required`
**해결**: `k8s/postgres/pgadmin.yaml`에 환경변수 직접 설정

### Bitnami 이미지 Pull 실패

**증상**: `image not found` (free tier 제한)
**해결**: `bitnamilegacy` repository 사용

## Service URLs

### /etc/hosts 설정 (Ingress 사용 시)

```bash
# 수동 설정
# /etc/hosts에 추가
127.0.0.1 kafka-ui.son.duckdns.org
127.0.0.1 pgadmin.son.duckdns.org
127.0.0.1 grafana.son.duckdns.org
127.0.0.1 app.son.duckdns.org
127.0.0.1 api.son.duckdns.org
127.0.0.1 argocd.son.duckdns.org

# 자동 설정 (권장)
cd /Users/sonmingi/Desktop/infra/scripts
sudo ./utils/setup-hosts.sh add
```

### 서비스 접속 URL (포트 8080/8443)

```
Kafka UI:    http://kafka-ui.son.duckdns.org:8080
pgAdmin:     http://pgadmin.son.duckdns.org:8080
Grafana:     http://grafana.son.duckdns.org:8080
Frontend:    http://app.son.duckdns.org:8080
Backend API: http://api.son.duckdns.org:8080/api
ArgoCD:      https://argocd.son.duckdns.org:8443  (TLS 활성화 시)
```

### Port-Forward 대안

```bash
# Ingress 없이 직접 접근
kubectl port-forward -n infra svc/kafka-ui 8080:8080
kubectl port-forward -n database svc/pgadmin 5050:80
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

## Internal Service Endpoints

```
Kafka Bootstrap:    kafka.infra.svc.cluster.local:9092
PostgreSQL:         postgresql.database.svc.cluster.local:5432
PostgreSQL (Dev):   postgresql://appuser:appuser123@postgresql.database.svc.cluster.local:5432/appdb?currentSchema=dev_schema
PostgreSQL (Prod):  postgresql://appuser:appuser123@postgresql.database.svc.cluster.local:5432/appdb?currentSchema=prod_schema
```

## Security & Secrets

### Secret 템플릿 시스템

Secret은 템플릿 기반으로 관리됩니다. 템플릿 파일은 `secrets/templates/`에 위치합니다.

**템플릿 파일**:
- `postgres-secret.yaml.tpl` - PostgreSQL 자격 증명
- `pgadmin-secret.yaml.tpl` - pgAdmin 자격 증명
- `postgres-exporter-secret.yaml.tpl` - Prometheus PostgreSQL Exporter
- `grafana-secret.yaml.tpl` - Grafana 관리자 자격 증명

### Secret 관리 명령어

```bash
cd /Users/sonmingi/Desktop/infra/secrets

# 보안 비밀번호 자동 생성 (.env 파일 생성)
./generate-secrets.sh generate

# 템플릿으로 Secret YAML 렌더링
./generate-secrets.sh render

# Kubernetes에 Secret 적용
./generate-secrets.sh apply

# 한 번에 모두 실행 (generate + render + apply)
./generate-secrets.sh all

# 현재 Secret 상태 확인
./generate-secrets.sh show

# 비밀번호 교체 (새 비밀번호 생성 + 적용)
./generate-secrets.sh rotate

# 렌더링된 파일 정리
./generate-secrets.sh clean
```

### .env 환경변수 구조

```bash
# secrets/.env (gitignore됨)
POSTGRES_PASSWORD=<32자 랜덤>
POSTGRES_APP_PASSWORD=<32자 랜덤>
POSTGRES_REPLICATION_PASSWORD=<32자 랜덤>
PGADMIN_EMAIL=admin@local.dev
PGADMIN_PASSWORD=<32자 랜덤>
GRAFANA_ADMIN_PASSWORD=<32자 랜덤>
```

### 비밀번호 확인

```bash
# 로컬 .env 파일에서 확인
cat secrets/.env

# Kubernetes Secret에서 확인
kubectl get secret postgres-secret -n database \
  -o jsonpath="{.data.postgres-password}" | base64 -d

kubectl get secret postgres-secret -n database \
  -o jsonpath="{.data.app-password}" | base64 -d

kubectl get secret loki-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

**기본 자격 증명** (generate 실행 전):
- PostgreSQL admin: `postgres` / `postgres123`
- PostgreSQL app: `appuser` / `appuser123`
- pgAdmin: `admin@local.dev` / `admin123`

**권장**: 프로덕션 환경에서는 반드시 `./generate-secrets.sh all` 실행

## Resource Profiles

Mac Mini 사양별 최적화:

- **8GB**: 개발/테스트 (Kafka 1GB, PostgreSQL 1GB)
- **16GB**: 소규모 프로덕션 (Kafka 2-3GB, PostgreSQL 1-2GB)
- **32GB**: 중규모 프로덕션 (Kafka 4-6GB, PostgreSQL 3-4GB)

프로파일 적용:
```bash
export PROFILE=16gb  # 8gb, 16gb, 32gb
# 배포 스크립트가 자동으로 프로파일 적용
```

## Monitoring Queries

### Loki (Logs)

```logql
{namespace="backend"}
{namespace="frontend"}
{app="backend-service"} |= "error"
{namespace="infra"} |= "kafka"
```

### Prometheus (Metrics)

```promql
# CPU 사용률
rate(container_cpu_usage_seconds_total[5m])

# 메모리 사용량
container_memory_usage_bytes

# PostgreSQL 연결 수
pg_stat_activity_count

# Kafka consumer lag
kafka_consumergroup_lag
```

## Development Workflow

1. **변경 사항 적용**: Helm values 또는 K8s manifests 수정
2. **테스트 네임스페이스 배포**: `kubectl apply -f ... -n test`
3. **검증**: Pod 상태, 로그, 메트릭 확인
4. **프로덕션 적용**: `kubectl apply -f ... -n <prod-namespace>`
5. **모니터링**: Grafana에서 메트릭 및 로그 확인

## PostgreSQL 관리

### 데이터베이스 위치

**중요**: PostgreSQL은 별도 디렉토리에서 관리됨
- 위치: `/Users/sonmingi/Desktop/database/`
- 네임스페이스: `database`
- 문서: `/Users/sonmingi/Desktop/database/README.md`

### 기본 명령어

```bash
cd /Users/sonmingi/Desktop/database/scripts

# 배포
./deploy.sh

# 스키마 초기화 (dev/prod 분리)
./init-schemas.sh

# 상태 확인
./status.sh

# psql 접속
./connect.sh dev_schema   # Dev 환경
./connect.sh prod_schema  # Prod 환경

# Port-forward (외부 접속용)
./port-forward.sh
# 실행 후: PostgreSQL → localhost:5432, pgAdmin → http://localhost:8080
```

### 스키마 구조

PostgreSQL은 단일 데이터베이스(`appdb`)에 스키마로 환경 분리:

```
appdb
├── dev_schema   # 개발/테스트 환경
├── prod_schema  # 프로덕션 환경
└── public       # 기본 스키마 (미사용)
```

### 연결 문자열

**클러스터 내부 (k3s Pod에서)**:
```
Dev:  postgresql://appuser:appuser123@postgresql.database.svc.cluster.local:5432/appdb?currentSchema=dev_schema
Prod: postgresql://appuser:appuser123@postgresql.database.svc.cluster.local:5432/appdb?currentSchema=prod_schema
```

**외부 (Mac Mini에서, port-forward 실행 중)**:
```
Dev:  postgresql://appuser:appuser123@localhost:5432/appdb?currentSchema=dev_schema
Prod: postgresql://appuser:appuser123@localhost:5432/appdb?currentSchema=prod_schema
```

### 테이블 확인

```bash
# Dev 스키마 테이블 목록
kubectl exec -n database postgresql-0 -- psql -U appuser -d appdb \
  -c "SET search_path = dev_schema; \dt"

# Prod 스키마 테이블 목록
kubectl exec -n database postgresql-0 -- psql -U appuser -d appdb \
  -c "SET search_path = prod_schema; \dt"
```

### 연결 테스트

```bash
# 클러스터 내부에서 테스트
kubectl run pg-test --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --env="PGPASSWORD=appuser123" \
  -- psql -h postgresql.database.svc.cluster.local -U appuser -d appdb \
  -c "SET search_path = dev_schema; SELECT current_schema();"
```

## Kafka 테스트

```bash
# 토픽 목록 확인
kubectl exec -n infra kafka-controller-0 -- kafka-topics.sh \
  --list --bootstrap-server localhost:9092

# 토픽 생성
kubectl exec -n infra kafka-controller-0 -- kafka-topics.sh \
  --create --topic test-topic --partitions 1 --replication-factor 1 \
  --bootstrap-server localhost:9092

# 메시지 전송
kubectl exec -n infra kafka-controller-0 -- bash -c \
  'echo "Hello Kafka" | kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092'

# 메시지 수신
kubectl exec -n infra kafka-controller-0 -- kafka-console-consumer.sh \
  --topic test-topic --from-beginning --max-messages 1 \
  --bootstrap-server localhost:9092 --timeout-ms 5000
```

## Important Notes

- **ARM64 호환성**: Mac Mini M4는 ARM64 아키텍처 - 모든 이미지 ARM64 지원 확인 필수
- **Helm Chart 버전 고정**: 안정성을 위해 Chart 버전 명시적 지정
- **리소스 제한**: 각 서비스의 resources.limits 설정으로 노드 과부하 방지
- **HPA 활성화**: Backend/Frontend는 자동 스케일링 지원
- **PVC 정리**: StatefulSet 삭제 시 PVC는 자동 삭제되지 않음 - 수동 삭제 필요
- **스크립트 실행 위치**: 배포 스크립트는 `scripts/` 디렉토리에서 실행해야 함 (상대경로 참조)
- **Phase 기반 배포**: `deploy-all.sh`는 체크포인트 기반으로 중단/재개 가능

## TLS/cert-manager (선택적)

### 개요

cert-manager를 통한 자동 TLS 인증서 관리. Let's Encrypt ACME 프로토콜 사용.

### 활성화

```bash
# Phase 6만 실행
./deploy-all.sh -p 6

# 또는 전체 배포 시 TLS 포함
ENABLE_TLS=true ./deploy-all.sh -y
```

### ClusterIssuer 종류

| 이름 | 용도 | 설명 |
|------|------|------|
| `letsencrypt-staging` | 테스트 | 브라우저 신뢰 안함, rate limit 관대 |
| `letsencrypt-prod` | 프로덕션 | 브라우저 신뢰, rate limit 엄격 |
| `selfsigned-issuer` | 개발 | 자체 서명, 즉시 발급 |
| `internal-ca-issuer` | 내부 | 내부 CA 기반 |

### 인증서 상태 확인

```bash
# ClusterIssuer 상태
kubectl get clusterissuer

# Certificate 상태
kubectl get certificate --all-namespaces

# 인증서 상세 정보
kubectl describe certificate wildcard-son-duckdns -n cert-manager

# cert-manager 로그
kubectl logs -n cert-manager -l app=cert-manager
```

### Ingress TLS 어노테이션

Ingress에 TLS 자동 적용:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  tls:
    - hosts:
        - grafana.son.duckdns.org
      secretName: grafana-tls
```

### 인증서 도메인

자동 생성되는 인증서:
- `*.son.duckdns.org` (wildcard)
- `son.duckdns.org` (루트)

## ArgoCD GitOps (선택적)

### 개요

ArgoCD를 통한 GitOps 기반 지속적 배포. Git 저장소를 Single Source of Truth로 사용.

### 활성화

```bash
# Phase 7만 실행
./deploy-all.sh -p 7

# 또는 전체 배포 시 ArgoCD 포함
ENABLE_ARGOCD=true ./deploy-all.sh -y

# TLS + ArgoCD 함께
ENABLE_TLS=true ENABLE_ARGOCD=true ./deploy-all.sh -y
```

### 접속 정보

```
URL:      https://argocd.son.duckdns.org:8443
Username: admin
Password: (자동 생성됨)
```

### 관리자 비밀번호 확인

```bash
# 초기 관리자 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 또는 secrets/.env 확인 (배포 시 저장됨)
grep ARGOCD secrets/.env
```

### ArgoCD 상태 확인

```bash
# ArgoCD Pod 상태
kubectl get pods -n argocd

# ArgoCD 서비스
kubectl get svc -n argocd

# Application 목록
kubectl get applications -n argocd

# AppProject 목록
kubectl get appprojects -n argocd
```

### ArgoCD CLI 사용

```bash
# CLI 설치 (macOS)
brew install argocd

# 로그인 (port-forward 필요)
kubectl port-forward svc/argocd-server -n argocd 8443:443 &
argocd login localhost:8443 --username admin --password <password> --insecure

# 애플리케이션 동기화
argocd app sync infrastructure

# 애플리케이션 상태
argocd app get infrastructure
```

### AppProject 구성

| 프로젝트 | 대상 Namespace | 설명 |
|---------|----------------|------|
| `infrastructure` | * | 인프라 컴포넌트 (Kafka, PostgreSQL 등) |
| `applications` | backend, frontend | 애플리케이션 배포 |

### Git 저장소 연결

`k8s/argocd/apps/infra-app.yaml`에서 저장소 URL 수정:

```yaml
spec:
  source:
    repoURL: https://github.com/YOUR_USERNAME/infra.git  # ← 실제 저장소로 변경
    targetRevision: HEAD
    path: k8s
```

## Grafana 자동 프로비저닝

### 데이터소스 (자동 설정)

배포 시 자동으로 설정되는 데이터소스:

| 데이터소스 | 유형 | 엔드포인트 |
|-----------|------|-----------|
| Loki | logs | `http://loki:3100` |
| Prometheus | metrics | `http://prometheus-server.monitoring:80` |
| PostgreSQL | database | `postgresql.database.svc.cluster.local:5432` |

### 대시보드 프로바이더

| 프로바이더 | 경로 | 용도 |
|-----------|------|------|
| default | `/var/lib/grafana/dashboards/default` | 기본 대시보드 |
| infrastructure | `/var/lib/grafana/dashboards/infrastructure` | 인프라 대시보드 |
| kubernetes | `/var/lib/grafana/dashboards/kubernetes` | K8s 대시보드 |

### 사전 설치 대시보드

Grafana.com에서 자동 로드:

| ID | 대시보드 | 용도 |
|----|---------|------|
| 1860 | Node Exporter Full | 노드 메트릭 |
| 18276 | Kafka Exporter | Kafka 모니터링 |
| 9628 | PostgreSQL Database | PostgreSQL 모니터링 |
| 15661 | K8s Namespace Resources | 네임스페이스별 리소스 |

### ConfigMap 대시보드 추가

Sidecar가 `grafana_dashboard: "1"` 라벨이 있는 ConfigMap을 자동 로드:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    { ... dashboard JSON ... }
```

## Code Review Workflow

### 개요

20년 경력 시니어 DevOps 엔지니어 수준의 6도메인 종합 코드 리뷰 시스템.

**6개 리뷰 도메인**:
1. **Architecture** - 네임스페이스, Phase 배포, Helm 구조
2. **Performance** - ARM64 최적화, 메모리 프로파일 (Mac Mini M4)
3. **Security** - Secret 템플릿, RBAC, SecurityContext
4. **Quality** - Shellcheck, YAML lint, 문서화
5. **Testing** - 검증 함수, Health check, dry-run
6. **Operations** - 모니터링, 로깅, 체크포인트

### GitHub Actions 워크플로우

| 워크플로우 | 트리거 | 용도 |
|-----------|--------|------|
| `claude-code-review.yml` | PR 생성/업데이트 | 6도메인 자동 리뷰 |
| `claude.yml` | `@claude` 멘션 | 대화형 어시스턴트 |
| `infra-lint.yml` | Push/PR | 자동 린트 검사 |

### 사용 방법

**자동 PR 리뷰**:
PR 생성 시 자동으로 6도메인 리뷰 실행

**수동 리뷰 요청**:
```
@claude /review
@claude fix this
@claude explain this change
```

**로컬 리뷰**:
```bash
/sc:review                           # 전체 리뷰
/sc:review --domain security         # 보안 도메인만
/sc:review scripts/ --focus bash     # Bash 스크립트만
/sc:review --depth quick             # 빠른 검사
```

### 리뷰 체크리스트

#### Critical (머지 전 필수 수정)

**Architecture**:
- [ ] 네임스페이스 격리 (infra/database/monitoring/backend/frontend)
- [ ] Chart 버전 고정 (예: kafka 31.5.0)
- [ ] Phase 함수 멱등성

**Performance (Mac Mini M4)**:
- [ ] ARM64 이미지 명시 (x86 에뮬레이션 금지)
- [ ] 프로파일별 메모리 제한

**Security**:
- [ ] YAML/스크립트에 평문 비밀번호 없음
- [ ] Secret 템플릿 사용

**Quality**:
- [ ] Shellcheck 통과
- [ ] YAML 문법 유효

#### Important (권장 수정)

- 라이브러리 sourcing 확인 (common.sh, validation.sh)
- `set -e` 에러 종료 설정
- Health probes 설정

### 심각도 분류

| 심각도 | 설명 | 예시 |
|--------|------|------|
| **Critical** | 머지 차단 | 하드코딩된 비밀번호, ARM64 미지원 이미지 |
| **Important** | 권장 수정 | 누락된 에러 핸들링, 비효율적 패턴 |
| **Suggested** | 개선 권장 | 코드 스타일, 문서화 개선 |
