# 아키텍처 상세 설계

## 시스템 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                         Mac Mini Host                        │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              k3d Kubernetes Cluster                    │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────────────┐  │ │
│  │  │         NGINX Ingress Controller                │  │ │
│  │  │         (Port 8080:80, 8443:443)                │  │ │
│  │  └─────────────────────────────────────────────────┘  │ │
│  │                         │                              │ │
│  │         ┌───────────────┼───────────────┐             │ │
│  │         │               │               │             │ │
│  │    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐        │ │
│  │    │Frontend │    │Backend  │    │  Infra  │        │ │
│  │    │Namespace│    │Namespace│    │Namespace│        │ │
│  │    └────┬────┘    └────┬────┘    └────┬────┘        │ │
│  │         │              │              │             │ │
│  │    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐        │ │
│  │    │Next.js  │    │Node.js  │    │  Kafka  │        │ │
│  │    │Frontend │◄───┤Backend  │◄───┤  Broker │        │ │
│  │    │Service  │    │Service  │    │         │        │ │
│  │    └─────────┘    └────┬────┘    └─────────┘        │ │
│  │                         │              │             │ │
│  │                    ┌────▼────┐    ┌────▼────┐        │ │
│  │                    │Postgres │    │ZooKeeper│        │ │
│  │                    │+ Pooler │    └─────────┘        │ │
│  │                    └─────────┘                       │ │
│  │                                                       │ │
│  │  ┌─────────────────────────────────────────────────┐  │ │
│  │  │         Monitoring Namespace                    │  │ │
│  │  │                                                  │  │ │
│  │  │  ┌────────┐  ┌────────┐  ┌────────┐           │  │ │
│  │  │  │  Loki  │  │Promtail│  │Grafana │           │  │ │
│  │  │  │ (Logs) │◄─┤(Collect)│  │  (UI)  │           │  │ │
│  │  │  └────────┘  └────────┘  └────────┘           │  │ │
│  │  └─────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 데이터 플로우

### 1. HTTP 요청 플로우

```
사용자 브라우저
    ↓ (http://app.local:8080)
NGINX Ingress Controller
    ↓
Frontend Service (ClusterIP)
    ↓
Frontend Pod (Next.js)
    ↓ (http://api.local:8080/api)
NGINX Ingress Controller
    ↓
Backend Service (ClusterIP)
    ↓
Backend Pod (Node.js)
```

### 2. 데이터베이스 접근 플로우

```
Backend Pod
    ↓ (postgresql.infra.svc.cluster.local:5432)
PgBouncer (Connection Pooler)
    ↓
PostgreSQL Primary
    ↓
Persistent Volume (Local Storage)
```

### 3. 이벤트 스트리밍 플로우

```
Backend Producer
    ↓ (kafka.infra.svc.cluster.local:9092)
Kafka Broker
    ↓
Kafka Topic (Partitioned)
    ↓
Backend Consumer(s)
```

### 4. 로그 수집 플로우

```
All Pods (stdout/stderr)
    ↓
Promtail DaemonSet
    ↓ (collect & label)
Loki Service
    ↓ (store)
Loki Persistent Volume
    ↑ (query)
Grafana Dashboard
```

## 네트워크 아키텍처

### Service Types

| 서비스 | Type | 설명 |
|--------|------|------|
| Frontend | ClusterIP | 내부 통신, Ingress를 통해 외부 노출 |
| Backend | ClusterIP | 내부 통신, Ingress를 통해 외부 노출 |
| Kafka | ClusterIP | 내부 통신만 (외부 접근 불가) |
| PostgreSQL | ClusterIP | 내부 통신만 (외부 접근 불가) |
| Kafka UI | ClusterIP | Ingress를 통해 외부 노출 |
| pgAdmin | ClusterIP | Ingress를 통해 외부 노출 |
| Grafana | ClusterIP | Ingress를 통해 외부 노출 |

### Network Policies

#### Frontend Namespace
- **Ingress**: Ingress Controller에서만 허용
- **Egress**: Backend Namespace로만 허용 + DNS

#### Backend Namespace
- **Ingress**: Frontend + Ingress Controller에서 허용
- **Egress**: Infra Namespace (Kafka, PostgreSQL) + DNS

#### Infra Namespace
- **Ingress**: Backend Namespace에서 허용 + Ingress Controller (관리 UI)
- **Egress**: 제한 없음

## 스토리지 아키텍처

### Persistent Volumes

| 서비스 | StorageClass | Size | Purpose |
|--------|--------------|------|---------|
| Kafka | local-path | 10Gi | 메시지 저장 |
| ZooKeeper | local-path | 2Gi | 메타데이터 저장 |
| PostgreSQL | local-path | 10Gi | 데이터베이스 |
| Loki | local-path | 5Gi | 로그 저장 |
| Grafana | local-path | 2Gi | 대시보드 설정 |

### Storage Backend

k3d는 기본적으로 `local-path-provisioner`를 사용:
- 실제 경로: Mac Mini 호스트의 `/tmp/k3d-storage`
- 자동 프로비저닝 지원
- 단일 노드 환경에 최적화

## 리소스 관리

### Resource Quotas (권장)

```yaml
# 각 namespace에 적용 가능
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: backend
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    persistentvolumeclaims: "5"
```

### LimitRange (권장)

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: mem-limit-range
  namespace: backend
spec:
  limits:
  - default:
      memory: 512Mi
      cpu: 500m
    defaultRequest:
      memory: 256Mi
      cpu: 250m
    type: Container
```

## 확장성 고려사항

### 수평 확장 (Horizontal Scaling)

#### 지원됨
- Frontend Pods (HPA)
- Backend Pods (HPA)
- Promtail (DaemonSet - 노드당 1개)

#### 제한적
- Kafka (단일 브로커, 멀티 노드 시 가능)
- PostgreSQL (단일 인스턴스, Patroni로 HA 구성 가능)
- Loki (단일 인스턴스, 분산 모드 가능)

### 수직 확장 (Vertical Scaling)

리소스 제한 조정으로 가능:
```bash
kubectl set resources deployment backend-service \
  -n backend \
  --limits=cpu=2,memory=2Gi \
  --requests=cpu=1,memory=1Gi
```

## 보안 아키텍처

### Authentication & Authorization

```
사용자 → Ingress (SSL/TLS) → Service → Pod
                                ↓
                        RBAC 검증 (ServiceAccount)
                                ↓
                        NetworkPolicy 검증
                                ↓
                        리소스 접근
```

### Secrets 관리

1. **Kubernetes Secrets**: 기본 방식
2. **External Secrets Operator**: 권장 (프로덕션)
3. **Sealed Secrets**: Git 저장용

### Pod Security

```yaml
# 권장 설정
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
```

## 고가용성 (HA) 로드맵

현재 구성은 단일 노드이지만, 향후 확장 가능:

### Phase 1: 현재 (Single Node)
- k3d 단일 서버 노드
- StatefulSet으로 상태 관리
- 로컬 스토리지

### Phase 2: Multi-Node (추가 Mac Mini)
- k3d 멀티 노드 클러스터
- Kafka 3-broker 클러스터
- PostgreSQL HA (Patroni/Stolon)
- 분산 스토리지 (Longhorn/Rook-Ceph)

### Phase 3: Production Grade
- 외부 로드밸런서
- 외부 인증 (OAuth/OIDC)
- 중앙 로깅 (ELK Stack)
- Service Mesh (Istio/Linkerd)

## 성능 벤치마크

### 예상 처리량 (16GB Mac Mini M1 기준)

| 서비스 | 지표 | 값 |
|--------|------|-----|
| Backend | Requests/sec | ~500-1000 |
| Kafka | Messages/sec | ~2500 |
| PostgreSQL | Transactions/sec | ~1000-2000 |
| Frontend | Concurrent Users | ~100-200 |

**참고**: 실제 성능은 애플리케이션 복잡도에 따라 다릅니다.

## 모니터링 메트릭

### Kubernetes 레벨
- Node CPU/Memory 사용률
- Pod 상태 및 재시작 횟수
- PersistentVolume 사용량

### 애플리케이션 레벨
- HTTP 요청/응답 시간
- 에러율
- 데이터베이스 쿼리 성능

### 인프라 레벨
- Kafka 레그 (lag)
- PostgreSQL 커넥션 풀 상태
- 디스크 I/O 및 네트워크 대역폭
