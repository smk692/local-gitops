# Mac Mini 인프라 구성 가이드

맥 미니를 활용한 프로덕션 수준의 Kubernetes 기반 인프라 구성 문서입니다.

## 📋 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [사전 요구사항](#사전-요구사항)
3. [빠른 시작](#빠른-시작)
4. [상세 구성](#상세-구성)
5. [애플리케이션 배포](#애플리케이션-배포)
6. [모니터링 및 관리](#모니터링-및-관리)
7. [트러블슈팅](#트러블슈팅)
8. [성능 최적화](#성능-최적화)

---

## 🏗️ 아키텍처 개요

### 전체 구조

```
Mac Mini (Single Node)
├── k3d (Kubernetes in Docker)
│   ├── Namespace: infra
│   │   ├── Kafka (1 broker + ZooKeeper)
│   │   ├── PostgreSQL (+ PgBouncer)
│   │   ├── Kafka UI
│   │   └── pgAdmin
│   ├── Namespace: backend
│   │   └── Backend Service (Node.js/Express)
│   ├── Namespace: frontend
│   │   └── Frontend Service (Next.js/React)
│   └── Namespace: monitoring
│       ├── Loki (로그 저장)
│       ├── Promtail (로그 수집)
│       └── Grafana (시각화)
└── NGINX Ingress Controller
```

### 네트워크 구성

- **내부 통신**: Kubernetes ClusterIP 서비스
- **외부 접근**: Ingress (NGINX) → Port 8080/8443
- **로컬 DNS**: /etc/hosts 기반 도메인 매핑

### 리소스 할당 (16GB RAM 기준)

| 서비스 | CPU 요청/제한 | 메모리 요청/제한 |
|--------|--------------|----------------|
| Kafka | 1000m/2000m | 2Gi/3Gi |
| PostgreSQL | 500m/1000m | 1Gi/2Gi |
| Backend (각) | 500m/1000m | 512Mi/1Gi |
| Frontend (각) | 500m/1000m | 512Mi/1Gi |
| Loki | 250m/500m | 256Mi/512Mi |
| Grafana | 250m/500m | 256Mi/512Mi |

---

## 📦 사전 요구사항

### 하드웨어

- **Mac Mini**: M1/M2/M4 칩셋
- **메모리**: 최소 16GB RAM 권장
- **저장공간**: 최소 50GB 여유 공간
- **네트워크**: 안정적인 인터넷 연결

### 소프트웨어

- **macOS**: Monterey (12.0) 이상
- **Homebrew**: 패키지 관리자
- **Docker Desktop**: 선택사항 (k3d가 자체 컨테이너 런타임 사용)

---

## 🚀 빠른 시작

### 1. 전체 스택 배포 (원클릭)

```bash
cd scripts
./deploy-all.sh
```

이 스크립트는 다음을 자동으로 실행합니다:
1. k3d 클러스터 생성
2. Kafka 배포
3. PostgreSQL 배포
4. 모니터링 스택 배포
5. 네트워킹 설정

**예상 소요 시간**: 약 15-20분

### 2. /etc/hosts 업데이트

```bash
sudo nano /etc/hosts
```

다음 라인들을 추가:
```
127.0.0.1 app.local
127.0.0.1 api.local
127.0.0.1 kafka-ui.local
127.0.0.1 pgadmin.local
127.0.0.1 grafana.local
```

### 3. 접속 확인

브라우저에서 다음 URL 접속:

- **Kafka UI**: http://kafka-ui.local:8080
- **pgAdmin**: http://pgadmin.local:8080
- **Grafana**: http://grafana.local:8080

---

## ⚙️ 상세 구성

### 개별 컴포넌트 배포

#### k3s 클러스터만 설치

```bash
cd scripts
./install-k3s.sh
```

#### Kafka만 배포

```bash
cd scripts
./deploy-kafka.sh
```

#### PostgreSQL만 배포

```bash
cd scripts
./deploy-postgres.sh
```

#### 모니터링 스택만 배포

```bash
cd scripts
./deploy-monitoring.sh
```

### Helm Values 커스터마이징

각 서비스의 설정은 `helm/` 디렉토리에서 수정 가능:

- `helm/kafka-values.yaml`: Kafka 설정
- `helm/postgres-values.yaml`: PostgreSQL 설정
- `helm/loki-values.yaml`: 모니터링 설정

예시: Kafka 메모리 증가
```yaml
# helm/kafka-values.yaml
resources:
  limits:
    memory: 4Gi  # 2Gi → 4Gi로 증가
```

변경 후 재배포:
```bash
helm upgrade kafka bitnami/kafka \
  --namespace infra \
  --values helm/kafka-values.yaml
```

---

## 📱 애플리케이션 배포

### 1. Docker 이미지 준비

#### 백엔드 이미지 빌드

```bash
cd your-backend-project
docker build -t your-registry/backend:v1.0 .
docker push your-registry/backend:v1.0
```

#### 프론트엔드 이미지 빌드

```bash
cd your-frontend-project
docker build -t your-registry/frontend:v1.0 .
docker push your-registry/frontend:v1.0
```

### 2. Kubernetes 매니페스트 업데이트

#### 백엔드 이미지 업데이트

`k8s/backend/deployment.yaml` 파일에서:
```yaml
spec:
  template:
    spec:
      containers:
      - name: backend
        image: your-registry/backend:v1.0  # 이 부분 수정
```

#### 프론트엔드 이미지 업데이트

`k8s/frontend/deployment.yaml` 파일에서:
```yaml
spec:
  template:
    spec:
      containers:
      - name: frontend
        image: your-registry/frontend:v1.0  # 이 부분 수정
```

### 3. 애플리케이션 배포

```bash
# 백엔드 배포
kubectl apply -f k8s/backend/

# 프론트엔드 배포
kubectl apply -f k8s/frontend/
```

### 4. 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n backend
kubectl get pods -n frontend

# 로그 확인
kubectl logs -n backend -l app=backend-service
kubectl logs -n frontend -l app=frontend-service
```

### 5. 접속 테스트

```bash
# 백엔드 API 테스트
curl http://api.local:8080/api/health

# 프론트엔드 접속
open http://app.local:8080
```

---

## 📊 모니터링 및 관리

### Grafana 대시보드 접속

```bash
# Grafana admin 비밀번호 확인
kubectl get secret -n monitoring loki-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# 접속: http://grafana.local:8080
# Username: admin
# Password: (위에서 확인한 비밀번호)
```

### 로그 조회

#### Grafana에서 로그 조회

1. Grafana 접속 후 Explore 메뉴
2. Loki 데이터소스 선택
3. 쿼리 예시:
```logql
{namespace="backend"}
{namespace="frontend"}
{app="backend-service"} |= "error"
```

#### kubectl로 직접 로그 조회

```bash
# 특정 Pod 로그
kubectl logs -n backend <pod-name>

# 실시간 로그 스트리밍
kubectl logs -n backend <pod-name> -f

# 이전 컨테이너 로그
kubectl logs -n backend <pod-name> --previous
```

### Kafka 관리

#### Kafka UI 접속
- URL: http://kafka-ui.local:8080
- Kafka 브로커, 토픽, 컨슈머 그룹 관리 가능

#### CLI로 Kafka 조작

```bash
# Kafka 클라이언트 Pod 생성
kubectl run kafka-client --rm -it \
  --image docker.io/bitnami/kafka:latest \
  --namespace infra \
  --command -- bash

# 토픽 생성
kafka-topics.sh --create \
  --bootstrap-server kafka:9092 \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 1

# 토픽 목록
kafka-topics.sh --list \
  --bootstrap-server kafka:9092

# 메시지 전송
kafka-console-producer.sh \
  --broker-list kafka:9092 \
  --topic test-topic

# 메시지 수신
kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic test-topic \
  --from-beginning
```

### PostgreSQL 관리

#### pgAdmin 접속
- URL: http://pgadmin.local:8080
- Email: admin@local.com
- Password: admin123

#### CLI로 PostgreSQL 접속

```bash
# PostgreSQL 비밀번호 확인
PGPASSWORD=$(kubectl get secret -n infra postgresql \
  -o jsonpath="{.data.postgres-password}" | base64 -d)

# PostgreSQL 클라이언트 실행
kubectl run postgres-client --rm -it \
  --image docker.io/bitnami/postgresql:latest \
  --namespace infra \
  --env="PGPASSWORD=$PGPASSWORD" \
  --command -- psql \
  --host postgresql \
  -U postgres \
  -d appdb
```

### 리소스 모니터링

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods --all-namespaces

# 특정 namespace
kubectl top pods -n backend
kubectl top pods -n frontend
```

---

## 🔧 트러블슈팅

### Pod가 시작되지 않는 경우

```bash
# Pod 상태 확인
kubectl describe pod <pod-name> -n <namespace>

# 이벤트 확인
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# 로그 확인
kubectl logs <pod-name> -n <namespace>
```

### 이미지 Pull 실패

```bash
# ImagePullBackOff 오류 시
kubectl describe pod <pod-name> -n <namespace>

# Private 레지스트리 사용 시 Secret 생성
kubectl create secret docker-registry regcred \
  --docker-server=<registry-url> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>

# Deployment에 Secret 추가
spec:
  template:
    spec:
      imagePullSecrets:
      - name: regcred
```

### Ingress 접속 불가

```bash
# Ingress Controller 상태 확인
kubectl get pods -n kube-system | grep ingress

# Ingress 리소스 확인
kubectl get ingress --all-namespaces

# /etc/hosts 확인
cat /etc/hosts | grep local

# Ingress 상세 확인
kubectl describe ingress <ingress-name> -n <namespace>
```

### 메모리 부족 (OOMKilled)

```bash
# OOMKilled Pod 확인
kubectl get pods --all-namespaces | grep OOMKilled

# 리소스 제한 증가
# deployment.yaml에서 resources.limits.memory 증가
kubectl edit deployment <deployment-name> -n <namespace>
```

### Kafka 연결 실패

```bash
# Kafka Pod 상태 확인
kubectl get pods -n infra | grep kafka

# Kafka 로그 확인
kubectl logs -n infra kafka-0

# Kafka 서비스 확인
kubectl get svc -n infra | grep kafka

# 연결 테스트
kubectl run kafka-test --rm -it \
  --image docker.io/bitnami/kafka:latest \
  --namespace infra \
  --command -- bash
# 컨테이너 내부에서:
kafka-broker-api-versions.sh --bootstrap-server kafka:9092
```

### PostgreSQL 연결 실패

```bash
# PostgreSQL Pod 상태
kubectl get pods -n infra | grep postgresql

# PostgreSQL 로그
kubectl logs -n infra postgresql-0

# 서비스 확인
kubectl get svc -n infra | grep postgresql

# 연결 테스트
kubectl run pg-test --rm -it \
  --image docker.io/bitnami/postgresql:latest \
  --namespace infra \
  --command -- bash
# 컨테이너 내부에서:
pg_isready -h postgresql -p 5432
```

### 클러스터 초기화 (전체 삭제 후 재시작)

```bash
# k3d 클러스터 삭제
k3d cluster delete macmini-cluster

# 재배포
cd scripts
./deploy-all.sh
```

---

## ⚡ 성능 최적화

### Kafka 최적화

#### 프로듀서 설정
```properties
# application.properties or environment variables
batch.size=32768
linger.ms=10
compression.type=lz4
buffer.memory=67108864
```

#### 토픽 파티션 증가
```bash
kafka-topics.sh --alter \
  --bootstrap-server kafka:9092 \
  --topic your-topic \
  --partitions 6
```

### PostgreSQL 최적화

#### 연결 풀링 (PgBouncer 설정)
```yaml
# helm/postgres-values.yaml
primary:
  pgBouncer:
    defaultPoolSize: 25  # 기본 20에서 증가
    maxClientConnections: 1500
```

#### 쿼리 성능 분석
```sql
-- 느린 쿼리 찾기
SELECT * FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- 인덱스 사용 확인
EXPLAIN ANALYZE SELECT ...;
```

### 애플리케이션 최적화

#### HPA (Horizontal Pod Autoscaler) 조정

```yaml
# k8s/backend/hpa.yaml
spec:
  minReplicas: 2
  maxReplicas: 8  # 5에서 8로 증가
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 60  # 70%에서 60%로 감소 (더 빠른 스케일링)
```

#### 리소스 제한 조정

```yaml
# k8s/backend/deployment.yaml
resources:
  limits:
    cpu: 2000m  # 1000m에서 증가
    memory: 2Gi  # 1Gi에서 증가
  requests:
    cpu: 1000m  # 500m에서 증가
    memory: 1Gi  # 512Mi에서 증가
```

### 모니터링 최적화

#### Loki 보관 기간 조정

```yaml
# helm/loki-values.yaml
loki:
  config:
    table_manager:
      retention_period: 336h  # 14일 (기본 7일에서 증가)
```

---

## 🔐 보안 권장사항

### 1. Secret 관리

프로덕션 환경에서는 반드시 다음 비밀번호를 변경하세요:

```yaml
# helm/postgres-values.yaml
auth:
  postgresPassword: "strong-password-here"
  password: "strong-password-here"

# k8s/backend/deployment.yaml (Secret)
stringData:
  db-password: "strong-password-here"
  jwt-secret: "strong-jwt-secret-here"
```

### 2. Network Policy 활성화

이미 `k8s/ingress/network-policy.yaml`에 정의되어 있습니다.
추가 제한이 필요한 경우 수정하세요.

### 3. RBAC 설정

각 namespace별로 ServiceAccount와 RoleBinding 생성:

```bash
kubectl create serviceaccount backend-sa -n backend
kubectl create role backend-role -n backend \
  --verb=get,list,watch \
  --resource=pods,services
kubectl create rolebinding backend-binding -n backend \
  --role=backend-role \
  --serviceaccount=backend:backend-sa
```

---

## 📚 참고 자료

- [k3d 공식 문서](https://k3d.io/)
- [Bitnami Kafka Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/kafka)
- [Bitnami PostgreSQL Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/postgresql)
- [Grafana Loki 문서](https://grafana.com/docs/loki/latest/)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/home/)

---

## 🤝 기여 및 지원

문제 발생 시:
1. 로그 확인: `kubectl logs`
2. 이벤트 확인: `kubectl get events`
3. 리소스 상태: `kubectl describe`

추가 질문이나 개선 사항은 프로젝트 관리자에게 문의하세요.
