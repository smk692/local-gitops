# Mac Mini 인프라 구성

맥 미니에서 프로덕션 수준의 Kubernetes 기반 인프라를 구성하는 프로젝트입니다.

## ✨ 주요 기능

- 🚀 **k3d 기반 Kubernetes 클러스터**: 경량화되고 빠른 로컬 Kubernetes 환경
- 📨 **Kafka 이벤트 스트리밍**: 마이크로서비스 간 비동기 통신
- 🗄️ **PostgreSQL 데이터베이스**: 연결 풀링(PgBouncer) 및 트랜잭션 모드 최적화
- 📊 **통합 모니터링 스택**:
  - Loki + Promtail (로그 수집)
  - Prometheus + Exporters (메트릭 수집)
  - Grafana (통합 대시보드)
- 🌐 **NGINX Ingress**: 통합 라우팅 및 SSL/TLS 지원
- 🔐 **보안 강화**:
  - Secret 관리 시스템
  - Network Policies (Namespace 격리)
  - 비밀번호 자동 생성
- ⚡ **리소스 프로파일**: 8GB/16GB/32GB Mac Mini 사양별 최적화

## 📁 프로젝트 구조

```
infra/
├── k8s/                     # Kubernetes 매니페스트
│   ├── namespaces/          # Namespace 정의
│   ├── kafka/               # Kafka + Kafka UI
│   ├── postgres/            # PostgreSQL + pgAdmin
│   ├── backend/             # 백엔드 서비스 템플릿
│   ├── frontend/            # 프론트엔드 서비스 템플릿
│   ├── monitoring/          # Loki 모니터링 스택
│   └── ingress/             # Ingress 및 네트워크 정책
├── helm/                    # Helm values 파일
│   ├── kafka-values.yaml
│   ├── postgres-values.yaml
│   ├── loki-values.yaml
│   ├── prometheus-values.yaml
│   └── profiles/            # 리소스 프로파일 (8GB/16GB/32GB)
├── secrets/                 # 보안 정보 관리 (Git 제외)
│   ├── README.md
│   ├── templates/           # Secret 템플릿 파일
│   └── generate-secrets.sh  # 비밀번호 생성/렌더/적용
├── scripts/                 # 설치 및 배포 스크립트
│   ├── lib/                 # 공통 라이브러리 모듈
│   ├── phases/              # Phase별 배포 스크립트 (01~07)
│   ├── utils/               # 유틸리티 (health-check, setup-hosts)
│   ├── install-k3s.sh       # k3d 클러스터 설치
│   └── deploy-all.sh        # 통합 Phase 기반 배포
└── docs/                    # 상세 문서
    ├── README.md            # 전체 가이드
    ├── ARCHITECTURE.md      # 아키텍처 설계
    ├── CI-CD.md             # CI/CD 파이프라인
    ├── MONITORING.md        # 모니터링 가이드
    └── SECURITY.md          # 보안 가이드
```

## 🚀 빠른 시작

### 1. 사전 요구사항

- Mac Mini (M1/M2/M4)
- macOS Monterey 이상
- RAM: 8GB (최소), 16GB (권장), 32GB (고성능)
- 50GB 이상 여유 공간
- Docker Desktop 설치

### 2. 보안 설정 (첫 배포 시)

```bash
# Secret 생성 (비밀번호 자동 생성)
cd secrets
./generate-secrets.sh

# 생성된 비밀번호 확인 (선택사항)
cat postgres-password.txt
cat postgres-app-password.txt
```

### 3. 리소스 프로파일 선택 (선택사항)

Mac Mini 사양에 맞는 프로파일 선택:

```bash
# 8GB RAM
export PROFILE=8gb

# 16GB RAM (기본값)
export PROFILE=16gb

# 32GB RAM
export PROFILE=32gb
```

상세 정보는 [helm/profiles/README.md](helm/profiles/README.md) 참조

### 4. 전체 스택 배포

```bash
cd scripts
./deploy-all.sh
```

### 5. /etc/hosts 설정

```bash
sudo nano /etc/hosts
```

다음 내용 추가:
```
127.0.0.1 app.local
127.0.0.1 api.local
127.0.0.1 kafka-ui.local
127.0.0.1 pgadmin.local
127.0.0.1 grafana.local
```

### 6. 서비스 접속

- **Kafka UI**: http://kafka-ui.local:8080
- **pgAdmin**: http://pgadmin.local:8080 (비밀번호는 secrets/ 디렉토리 참조)
- **Grafana**: http://grafana.local:8080 (admin / [비밀번호는 설치 로그 확인])
- **Prometheus**: `kubectl port-forward -n monitoring svc/prometheus-server 9090:80`

## 📊 시스템 아키텍처

```
┌─────────────────────────────────────────────┐
│            NGINX Ingress Controller         │
│            (Port 8080:80, 8443:443)         │
└─────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
   ┌────▼────┐   ┌────▼────┐   ┌───▼────┐
   │Frontend │   │Backend  │   │ Infra  │
   │Namespace│   │Namespace│   │Namespace│
   └────┬────┘   └────┬────┘   └───┬────┘
        │            │             │
   ┌────▼────┐  ┌────▼────┐  ┌────▼────┐
   │Next.js  │  │Node.js  │  │  Kafka  │
   │Frontend │◄─┤Backend  │◄─┤ Broker  │
   └─────────┘  └────┬────┘  └─────────┘
                     │            │
                ┌────▼────┐  ┌────▼────┐
                │Postgres │  │ZooKeeper│
                │+Pooler  │  └─────────┘
                └─────────┘
```

## 📦 개별 Phase 배포

각 Phase를 개별적으로 배포할 수 있습니다:

```bash
cd scripts

# Phase 1: 클러스터만
./deploy-all.sh -p 1

# Phase 2: Kafka 인프라만
./deploy-all.sh -p 2

# Phase 3: PostgreSQL만
./deploy-all.sh -p 3

# Phase 4: 모니터링 스택만
./deploy-all.sh -p 4

# Phase 5: 애플리케이션만
./deploy-all.sh -p 5

# Phase 6: TLS/cert-manager (선택)
ENABLE_TLS=true ./deploy-all.sh -p 6

# Phase 7: ArgoCD (선택)
ENABLE_ARGOCD=true ./deploy-all.sh -p 7
```

## 🔧 애플리케이션 배포

### 1. Docker 이미지 빌드

```bash
# 백엔드
cd your-backend-project
docker build -t your-registry/backend:v1.0 .
docker push your-registry/backend:v1.0

# 프론트엔드
cd your-frontend-project
docker build -t your-registry/frontend:v1.0 .
docker push your-registry/frontend:v1.0
```

### 2. Kubernetes 매니페스트 업데이트

`k8s/backend/deployment.yaml` 및 `k8s/frontend/deployment.yaml`에서 이미지 경로를 업데이트하세요.

### 3. 배포

```bash
kubectl apply -f k8s/backend/
kubectl apply -f k8s/frontend/
```

## 📊 모니터링

### Grafana 통합 대시보드

```bash
# Admin 비밀번호 확인
kubectl get secret -n monitoring loki-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# 접속: http://grafana.local:8080
```

### 로그 조회 (Loki)

Grafana Explore에서 Loki 쿼리:
```logql
{namespace="backend"}
{namespace="frontend"}
{app="backend-service"} |= "error"
```

### 메트릭 조회 (Prometheus)

```bash
# Prometheus UI 직접 접속
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# 브라우저: http://localhost:9090
```

주요 메트릭:
```promql
# Pod CPU 사용률
rate(container_cpu_usage_seconds_total[5m])

# Pod 메모리 사용량
container_memory_usage_bytes

# PostgreSQL 연결 수
pg_stat_activity_count

# Kafka consumer lag
kafka_consumergroup_lag
```

자세한 모니터링 가이드: [docs/MONITORING.md](docs/MONITORING.md)

## 🔍 트러블슈팅

### Pod 상태 확인

```bash
kubectl get pods --all-namespaces
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### 서비스 확인

```bash
kubectl get svc --all-namespaces
kubectl get ingress --all-namespaces
```

### 리소스 사용량

```bash
kubectl top nodes
kubectl top pods --all-namespaces
```

## 📖 상세 문서

더 자세한 내용은 다음 문서를 참고하세요:

- [전체 가이드](docs/README.md): 설치, 구성, 운영 가이드
- [아키텍처 설계](docs/ARCHITECTURE.md): 시스템 구조 및 설계 원칙
- [CI/CD 파이프라인](docs/CI-CD.md): 지속적 통합 및 배포
- [모니터링 가이드](docs/MONITORING.md): Prometheus, Loki, Grafana 활용법
- [보안 가이드](docs/SECURITY.md): 보안 설정 및 베스트 프랙티스
- [리소스 프로파일](helm/profiles/README.md): Mac Mini 사양별 최적화
- [Secret 관리](secrets/README.md): 비밀번호 및 민감 정보 관리

## 🛠️ 기술 스택

- **Kubernetes**: k3d (k3s in Docker)
- **Message Queue**: Apache Kafka + ZooKeeper (Bitnami Charts)
- **Database**: PostgreSQL + PgBouncer (Bitnami Charts)
- **Monitoring**:
  - Loki + Promtail (로그)
  - Prometheus + Exporters (메트릭)
  - Grafana (통합 대시보드)
- **Ingress**: NGINX Ingress Controller
- **Container Runtime**: Docker

## 📈 성능 최적화

### 리소스 프로파일

**8GB RAM (개발/테스트)**
- Kafka: 1GB / PostgreSQL: 1GB / Monitoring: 0.5GB
- Backend/Frontend: 각 1개 replica
- 동시 사용자: ~50명

**16GB RAM (기본/소규모 프로덕션)**
- Kafka: 2-3GB / PostgreSQL: 1-2GB / Monitoring: 1GB
- Backend/Frontend: 각 2개 replica
- 동시 사용자: ~100-200명

**32GB RAM (고성능/중규모 프로덕션)**
- Kafka: 4-6GB / PostgreSQL: 3-4GB / Monitoring: 1.5GB
- Backend/Frontend: 각 3개 replica
- 동시 사용자: ~500명

상세 정보: [helm/profiles/README.md](helm/profiles/README.md)

### HPA (Horizontal Pod Autoscaler)

백엔드와 프론트엔드는 CPU/메모리 사용률에 따라 자동 확장:
- 8GB: Backend 1-2, Frontend 1-2
- 16GB: Backend 2-5, Frontend 2-4
- 32GB: Backend 3-10, Frontend 3-8

## 🔐 보안

### 구현된 보안 기능

✅ **Secret 관리 시스템**
- 자동 비밀번호 생성 스크립트
- Git에서 민감 정보 제외 (.gitignore)
- 템플릿 파일로 안전한 배포

✅ **데이터베이스 보안**
- PostgreSQL: SCRAM-SHA-256 인증
- PgBouncer: 트랜잭션 모드 연결 풀링
- 연결 수 제한 (프로파일별)
- pgAdmin: Kubernetes Secret 기반 인증

✅ **Kafka 보안**
- 프로덕션용 SASL_SSL 설정 준비
- Security Context 활성화
- 비root 사용자로 실행

✅ **네트워크 보안**
- Network Policies (Namespace 격리)
- RBAC 권한 관리
- Ingress 접근 제어

### 프로덕션 권장사항

1. ✅ **비밀번호 관리**: secrets/ 디렉토리 활용
2. 🔄 **SSL/TLS 적용**: Let's Encrypt 또는 Cloudflare 인증서
3. 🔄 **Kafka SASL_SSL**: `kafka-values.yaml`에서 활성화
4. 🔄 **External Secrets Operator**: 클라우드 보안 통합
5. 🔄 **Pod Security Standards**: PSS Enforcing 모드

자세한 보안 가이드: [docs/SECURITY.md](docs/SECURITY.md)

## 🤝 기여

개선 사항이나 버그 리포트는 Issue를 통해 제출해주세요.

## 📄 라이선스

MIT License

## 📞 지원

문제가 발생하거나 질문이 있으시면:
1. [문서](docs/README.md) 확인
2. [트러블슈팅 가이드](docs/README.md#트러블슈팅) 참조
3. Issue 생성

---

**Made with ❤️ for Mac Mini Infrastructure**
