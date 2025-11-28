# 보안 가이드

이 문서는 Mac Mini 인프라의 보안 설정 및 베스트 프랙티스에 대한 포괄적인 가이드입니다.

## 📋 목차

1. [보안 개요](#보안-개요)
2. [Secret 관리](#secret-관리)
3. [데이터베이스 보안](#데이터베이스-보안)
4. [Kafka 보안](#kafka-보안)
5. [네트워크 보안](#네트워크-보안)
6. [인증 및 권한](#인증-및-권한)
7. [컨테이너 보안](#컨테이너-보안)
8. [모니터링 보안](#모니터링-보안)
9. [프로덕션 체크리스트](#프로덕션-체크리스트)

## 보안 개요

### 구현된 보안 계층

```
┌─────────────────────────────────────────────┐
│  네트워크 보안                               │
│  - Network Policies                         │
│  - Ingress 접근 제어                         │
└─────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────┐
│  인증 및 권한                                │
│  - RBAC                                      │
│  - Service Accounts                          │
│  - Secret 기반 인증                          │
└─────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────┐
│  애플리케이션 보안                           │
│  - PostgreSQL SCRAM-SHA-256                 │
│  - Kafka SASL_SSL (선택적)                  │
│  - Security Context                          │
└─────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────┐
│  데이터 보안                                 │
│  - PersistentVolume 암호화                  │
│  - Secret 암호화 (etcd)                     │
│  - Backup 암호화                            │
└─────────────────────────────────────────────┘
```

### 위험 평가 매트릭스

| 자산 | 위협 | 현재 완화 | 추가 조치 필요 |
|------|------|-----------|----------------|
| PostgreSQL 데이터 | 무단 접근 | ✅ 강력한 인증, Network Policy | 🔄 데이터 암호화 |
| Kafka 메시지 | 도청 | ⚠️ plaintext (dev) | 🔄 SASL_SSL 활성화 |
| Secret 정보 | 유출 | ✅ Git 제외, 자동 생성 | 🔄 External Secrets |
| 관리 도구 | 무단 접근 | ✅ Secret 기반 인증 | 🔄 MFA, VPN |
| 로그/메트릭 | 민감 정보 노출 | ⚠️ 기본 설정 | 🔄 로그 필터링 |

## Secret 관리

### 자동 Secret 생성

```bash
cd secrets/
./generate-secrets.sh
```

생성되는 Secret:
- `postgres-password.txt`: PostgreSQL postgres 사용자 비밀번호
- `postgres-app-password.txt`: PostgreSQL appuser 비밀번호
- `backend-secrets.yaml`: Backend 서비스용 Secret (DB 비밀번호, JWT, API 키)
- `frontend-secrets.yaml`: Frontend 서비스용 Secret

### Secret 적용

```bash
cd secrets/

# 전체 프로세스 (생성 + 렌더링 + 적용)
./generate-secrets.sh all

# 또는 단계별:
./generate-secrets.sh generate  # .env 비밀번호 생성
./generate-secrets.sh render    # 템플릿 → YAML 렌더링
./generate-secrets.sh apply     # K8s Secret 적용

# 비밀번호 교체
./generate-secrets.sh rotate
```

### Git에서 제외

`.gitignore` 파일에 다음이 포함되어 있는지 확인:

```gitignore
# Sensitive configuration files
secrets/
*.secret.yaml
*.secret.yml
*-secrets.yaml
*-secrets.yml

# Password files
*.txt
!secrets/README.md

# Environment-specific values
helm/*-local.yaml
k8s/*/secrets.yaml
```

### Secret 로테이션

**주기적 비밀번호 변경 (권장: 90일)**

```bash
# 1. 새 비밀번호 생성
cd secrets/
./generate-secrets.sh

# 2. PostgreSQL 비밀번호 업데이트
NEW_PASSWORD=$(cat postgres-password.txt)

helm upgrade postgresql bitnami/postgresql \
  --namespace infra \
  --reuse-values \
  --set auth.postgresPassword="$NEW_PASSWORD"

# 3. 애플리케이션 Secret 업데이트
kubectl apply -f backend-secrets.yaml
kubectl rollout restart deployment/backend-service -n backend

# 4. 이전 비밀번호 파일 삭제
shred -u old-passwords.txt
```

### Secret 백업

**암호화된 백업 생성**

```bash
# 모든 Secret 추출
kubectl get secrets --all-namespaces -o yaml > all-secrets.yaml

# GPG로 암호화
gpg --symmetric --cipher-algo AES256 all-secrets.yaml

# 원본 파일 안전하게 삭제
shred -u all-secrets.yaml

# 백업 저장
mv all-secrets.yaml.gpg ~/secure-backup/
```

**복구**

```bash
# 복호화
gpg --decrypt all-secrets.yaml.gpg > all-secrets.yaml

# 적용
kubectl apply -f all-secrets.yaml

# 파일 삭제
shred -u all-secrets.yaml
```

## 데이터베이스 보안

### PostgreSQL 보안 설정

**인증 강화**

`helm/postgres-values.yaml`에 구현됨:

```yaml
auth:
  postgresPassword: ""  # 외부에서 주입
  username: "appuser"
  password: ""          # 외부에서 주입
  database: "appdb"

primary:
  extendedConfiguration: |
    # 강력한 인증
    password_encryption = scram-sha-256

    # SSL 연결 (프로덕션)
    ssl = on
    ssl_cert_file = '/etc/ssl/certs/server.crt'
    ssl_key_file = '/etc/ssl/private/server.key'
```

**SSL/TLS 설정**

```bash
# 자체 서명 인증서 생성 (개발용)
openssl req -new -x509 -days 365 -nodes \
  -text -out server.crt -keyout server.key \
  -subj "/CN=postgresql.infra.svc.cluster.local"

# Secret으로 저장
kubectl create secret tls postgresql-tls \
  --cert=server.crt \
  --key=server.key \
  -n infra

# helm values 업데이트
helm upgrade postgresql bitnami/postgresql \
  --namespace infra \
  --reuse-values \
  --set tls.enabled=true \
  --set tls.certificatesSecret=postgresql-tls
```

**연결 제한 및 모니터링**

```yaml
primary:
  extendedConfiguration: |
    # 연결 수 제한 (프로파일별)
    max_connections = 150

    # 유휴 연결 타임아웃
    idle_in_transaction_session_timeout = 300000  # 5분

    # 쿼리 로깅 (성능 모니터링)
    log_min_duration_statement = 1000  # 1초 이상 쿼리
    log_connections = on
    log_disconnections = on

    # 성능 통계
    shared_preload_libraries = 'pg_stat_statements'
    pg_stat_statements.track = all
```

### PgBouncer 보안

**트랜잭션 모드 (연결 효율성)**

```yaml
primary:
  pgBouncer:
    enabled: true
    poolMode: transaction  # 보안성과 효율성 균형
    maxClientConnections: 200
    defaultPoolSize: 10
```

**인증 모드**

```yaml
primary:
  pgBouncer:
    auth_type: scram-sha-256  # 강력한 인증
    ignore_startup_parameters: extra_float_digits
```

### pgAdmin 보안

**Secret 기반 인증**

```bash
# pgAdmin credentials Secret 생성
kubectl create secret generic pgadmin-credentials \
  --from-literal=email="admin@yourdomain.com" \
  --from-literal=password="$(openssl rand -base64 32)" \
  -n infra

# Secret을 pgadmin.yaml에서 참조
# 이미 k8s/postgres/pgadmin.yaml에 구현됨
```

**추가 보안 설정**

```yaml
env:
- name: PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION
  value: "True"
- name: PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED
  value: "True"
- name: PGADMIN_CONFIG_SESSION_EXPIRATION_TIME
  value: "60"  # 60분
```

## Kafka 보안

### 개발 환경 (현재 설정)

`helm/kafka-values.yaml`:

```yaml
auth:
  clientProtocol: plaintext
  interBrokerProtocol: plaintext
```

⚠️ **경고**: plaintext는 개발/테스트 전용입니다.

### 프로덕션 환경 (SASL_SSL)

**1. SSL 인증서 생성**

```bash
# CA 키 생성
openssl genrsa -out ca-key.pem 2048
openssl req -new -x509 -days 365 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=Kafka-CA"

# 브로커 키 생성
openssl genrsa -out kafka-key.pem 2048
openssl req -new -key kafka-key.pem -out kafka-csr.pem \
  -subj "/CN=kafka.infra.svc.cluster.local"

# 서명
openssl x509 -req -in kafka-csr.pem -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out kafka-cert.pem -days 365

# Keystore 생성
openssl pkcs12 -export -in kafka-cert.pem -inkey kafka-key.pem \
  -out kafka.p12 -name kafka -password pass:changeit

# JKS로 변환
keytool -importkeystore -srckeystore kafka.p12 -srcstoretype PKCS12 \
  -destkeystore kafka.keystore.jks -deststoretype JKS \
  -srcstorepass changeit -deststorepass changeit

# Truststore 생성
keytool -import -file ca-cert.pem -alias CARoot \
  -keystore kafka.truststore.jks -storepass changeit -noprompt
```

**2. Secret 생성**

```bash
kubectl create secret generic kafka-jks \
  --from-file=kafka.keystore.jks \
  --from-file=kafka.truststore.jks \
  -n infra
```

**3. Kafka 설정 업데이트**

`helm/kafka-values.yaml`:

```yaml
auth:
  clientProtocol: sasl_ssl
  interBrokerProtocol: sasl_ssl
  sasl:
    mechanisms: SCRAM-SHA-256
    users:
      - admin
      - producer
      - consumer
    passwords:
      - "ADMIN_PASSWORD"
      - "PRODUCER_PASSWORD"
      - "CONSUMER_PASSWORD"
  tls:
    type: jks
    existingSecret: kafka-jks
    keystorePassword: "changeit"
    truststorePassword: "changeit"
```

**4. 재배포**

```bash
helm upgrade kafka bitnami/kafka \
  --namespace infra \
  --values helm/kafka-values.yaml \
  --wait
```

### Kafka ACL (접근 제어)

```bash
# Producer ACL
kafka-acls.sh --authorizer-properties \
  zookeeper.connect=zookeeper:2181 \
  --add --allow-principal User:producer \
  --operation Write --topic my-topic

# Consumer ACL
kafka-acls.sh --authorizer-properties \
  zookeeper.connect=zookeeper:2181 \
  --add --allow-principal User:consumer \
  --operation Read --topic my-topic \
  --group my-consumer-group
```

## 네트워크 보안

### Network Policies

**Namespace 격리 (이미 구현됨)**

`k8s/ingress/network-policies.yaml`:

```yaml
# Backend → PostgreSQL만 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-postgres
  namespace: infra
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: postgresql
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: backend
    ports:
    - protocol: TCP
      port: 5432
```

### Ingress 보안

**Basic Auth 추가**

```bash
# htpasswd 파일 생성
htpasswd -c auth admin

# Secret 생성
kubectl create secret generic basic-auth \
  --from-file=auth \
  -n infra

# Ingress에 annotation 추가
kubectl annotate ingress pgadmin-ingress \
  nginx.ingress.kubernetes.io/auth-type=basic \
  nginx.ingress.kubernetes.io/auth-secret=basic-auth \
  nginx.ingress.kubernetes.io/auth-realm="Authentication Required" \
  -n infra
```

**Rate Limiting**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend-ingress
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-connections: "10"
```

**IP Whitelist (프로덕션)**

```yaml
annotations:
  nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

### Service Mesh (선택적)

**Istio 도입 시 mTLS**

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: backend
spec:
  mtls:
    mode: STRICT
```

## 인증 및 권한

### RBAC 설정

**Service Account 생성**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: backend
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backend-role
  namespace: backend
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backend-rolebinding
  namespace: backend
subjects:
- kind: ServiceAccount
  name: backend-sa
  namespace: backend
roleRef:
  kind: Role
  name: backend-role
  apiGroup: rbac.authorization.k8s.io
```

**Deployment에 적용**

```yaml
spec:
  template:
    spec:
      serviceAccountName: backend-sa
```

### JWT 인증 (Backend)

**Backend Secret에 이미 포함됨**

```yaml
# secrets/generate-secrets.sh에서 생성
jwt-secret: "$(openssl rand -base64 64)"
```

**사용 예시**

```javascript
// Backend JWT 검증
const jwt = require('jsonwebtoken');
const secret = process.env.JWT_SECRET;

function verifyToken(token) {
  return jwt.verify(token, secret);
}
```

## 컨테이너 보안

### Security Context

**Pod Security Context**

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  fsGroup: 1001
  seccompProfile:
    type: RuntimeDefault
```

**Container Security Context**

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
```

### Image Scanning

**Trivy를 사용한 취약점 스캔**

```bash
# 이미지 스캔
trivy image your-registry/backend:v1.0

# 심각도 필터
trivy image --severity HIGH,CRITICAL your-registry/backend:v1.0

# CI/CD 통합
trivy image --exit-code 1 --severity CRITICAL your-registry/backend:v1.0
```

### Pod Security Standards

**PSS Enforcing 모드 (권장)**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: backend
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

## 모니터링 보안

### Grafana 보안

**강력한 Admin 비밀번호**

```bash
# 기존 비밀번호 변경
NEW_PASSWORD=$(openssl rand -base64 24)

kubectl patch secret loki-grafana -n monitoring \
  -p="{\"data\":{\"admin-password\":\"$(echo -n $NEW_PASSWORD | base64)\"}}"

# Grafana Pod 재시작
kubectl rollout restart deployment/loki-grafana -n monitoring
```

**Anonymous 접근 비활성화**

`helm/loki-values.yaml`:

```yaml
grafana:
  grafana.ini:
    auth.anonymous:
      enabled: false
```

**LDAP/OAuth 통합 (프로덕션)**

```yaml
grafana:
  grafana.ini:
    auth.ldap:
      enabled: true
      config_file: /etc/grafana/ldap.toml
```

### Prometheus 보안

**RBAC for Service Monitors**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: ["nodes", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
```

### 민감 로그 필터링

**Promtail에서 민감 정보 마스킹**

```yaml
scrape_configs:
- job_name: kubernetes-pods
  pipeline_stages:
  - replace:
      expression: '(password|token|secret)=\S+'
      replace: '$1=***REDACTED***'
```

## 프로덕션 체크리스트

### 배포 전 필수 사항

- [ ] **Secret 관리**
  - [ ] 모든 기본 비밀번호 변경
  - [ ] Secret 자동 생성 스크립트 실행
  - [ ] Secret 로테이션 정책 수립

- [ ] **데이터베이스 보안**
  - [ ] PostgreSQL SSL/TLS 활성화
  - [ ] 강력한 인증 설정 (SCRAM-SHA-256)
  - [ ] 연결 제한 설정
  - [ ] 정기 백업 구성

- [ ] **Kafka 보안**
  - [ ] SASL_SSL 활성화
  - [ ] ACL 설정
  - [ ] 메시지 암호화 (필요시)

- [ ] **네트워크 보안**
  - [ ] Network Policies 검토 및 강화
  - [ ] Ingress Basic Auth 또는 OAuth
  - [ ] Rate Limiting 설정
  - [ ] IP Whitelist 구성

- [ ] **컨테이너 보안**
  - [ ] 이미지 취약점 스캔
  - [ ] Pod Security Standards 적용
  - [ ] Security Context 설정
  - [ ] 최소 권한 원칙 적용

- [ ] **모니터링 보안**
  - [ ] Grafana 인증 강화
  - [ ] 민감 로그 필터링
  - [ ] 모니터링 접근 제어

- [ ] **인증 및 권한**
  - [ ] RBAC 정책 검토
  - [ ] Service Account 최소 권한
  - [ ] JWT/API Key 로테이션

### 운영 중 정기 점검

**매주**
- [ ] 보안 로그 검토
- [ ] 이상 트래픽 모니터링
- [ ] 실패한 인증 시도 확인

**매월**
- [ ] 이미지 취약점 재스캔
- [ ] Secret 만료 확인
- [ ] 백업 테스트

**분기별**
- [ ] Secret 로테이션
- [ ] 보안 정책 검토
- [ ] 침투 테스트 (가능한 경우)

## 사고 대응

### 침해 의심 시

1. **즉시 조치**
   ```bash
   # 의심되는 Pod 격리
   kubectl label pod suspicious-pod quarantine=true

   # Network Policy로 격리
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: quarantine
   spec:
     podSelector:
       matchLabels:
         quarantine: "true"
     policyTypes:
     - Ingress
     - Egress
   EOF
   ```

2. **로그 수집**
   ```bash
   # Pod 로그 백업
   kubectl logs suspicious-pod > incident-logs.txt

   # 이벤트 수집
   kubectl get events --all-namespaces > incident-events.txt
   ```

3. **분석 및 복구**
   - 로그 분석으로 침해 경로 파악
   - 취약점 패치
   - Secret 전체 로테이션
   - 필요시 Pod 재생성

## 추가 리소스

- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/overview/)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [PostgreSQL Security Best Practices](https://www.postgresql.org/docs/current/security.html)
- [Apache Kafka Security](https://kafka.apache.org/documentation/#security)
