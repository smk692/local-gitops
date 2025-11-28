# Infrastructure Code Review Checklist

> Mac Mini M4 Kubernetes 인프라 프로젝트를 위한 20년 시니어 DevOps 엔지니어 수준의 종합 리뷰 체크리스트

## 개요

이 체크리스트는 6개 도메인에 걸친 종합적인 코드 리뷰를 위한 가이드입니다.

**심각도 분류**:
- **Critical** (🔴): 머지 차단 - 반드시 수정 필요
- **Important** (🟡): 권장 수정 - 가능하면 수정
- **Suggested** (🟢): 개선 권장 - 시간 여유 시 수정

---

## 1. Architecture Domain

### 🔴 Critical Checks

- [ ] **네임스페이스 격리**
  - infra, database, monitoring, backend, frontend 분리 확인
  - Cross-namespace 접근 시 FQDN 사용 (`service.namespace.svc.cluster.local`)

- [ ] **Chart 버전 고정**
  - Kafka: `31.5.0` (Kafka 3.9.x용)
  - Chart 버전과 이미지 버전 호환성 확인
  - `global.security.allowInsecureImages: true` (legacy 이미지)

- [ ] **Phase 함수 멱등성**
  - 모든 phase 함수는 반복 실행 가능해야 함
  - `kubectl apply` 또는 `helm upgrade --install` 사용
  - 조건부 실행: `if ! kubectl get ... > /dev/null 2>&1; then`

- [ ] **라이브러리 sourcing**
  ```bash
  source "$SCRIPT_DIR/lib/common.sh"
  source "$SCRIPT_DIR/lib/validation.sh"
  source "$SCRIPT_DIR/lib/k3d.sh"
  ```

### 🟡 Important Checks

- [ ] **레이블 컨벤션**
  ```yaml
  labels:
    app.kubernetes.io/name: service-name
    app.kubernetes.io/instance: release-name
    app.kubernetes.io/component: component-type
  ```

- [ ] **리소스 프로파일 분리**
  - `helm/profiles/8gb-profile.yaml`
  - `helm/profiles/16gb-profile.yaml`
  - `helm/profiles/32gb-profile.yaml`

### 🟢 Suggested Checks

- [ ] Pod anti-affinity for HA workloads
- [ ] Values 파일에 주석 추가

---

## 2. Performance Domain (Mac Mini M4)

### 🔴 Critical Checks

- [ ] **ARM64 이미지 명시**
  - x86 에뮬레이션 금지 (성능 저하)
  - `bitnamilegacy/kafka:3.9.0-debian-12-r12` (ARM64 지원)
  - 이미지 태그에 아키텍처 명시 권장

- [ ] **프로파일별 메모리 제한**
  | 프로파일 | Kafka | PostgreSQL | 기타 |
  |----------|-------|------------|------|
  | 8GB | 1GB | 1GB | 512MB |
  | 16GB | 2-3GB | 1-2GB | 1GB |
  | 32GB | 4-6GB | 3-4GB | 2GB |

- [ ] **M4 CPU 적정 request**
  - M4는 10 cores (Performance + Efficiency)
  - 단일 서비스 CPU request < 2 cores 권장
  - 전체 request 합계 < 8 cores 권장

- [ ] **busy-wait 금지**
  ```bash
  # Bad
  while ! kubectl get pod ...; do sleep 1; done

  # Good
  kubectl wait --for=condition=ready pod -l app=service --timeout=300s
  ```

### 🟡 Important Checks

- [ ] **JVM Heap 설정** (Kafka, Elasticsearch 등)
  ```yaml
  # 8GB 프로파일
  KAFKA_HEAP_OPTS: "-Xmx768m -Xms768m"
  # 16GB 프로파일
  KAFKA_HEAP_OPTS: "-Xmx2g -Xms2g"
  ```

- [ ] **PostgreSQL 설정**
  ```
  shared_buffers = 256MB  # 8GB 프로파일
  shared_buffers = 512MB  # 16GB 프로파일
  ```

### 🟢 Suggested Checks

- [ ] NVMe 스토리지 활용 (StatefulSet)
- [ ] kubectl 호출 캐싱

---

## 3. Security Domain

### 🔴 Critical Checks

- [ ] **평문 비밀번호 금지**
  ```yaml
  # Bad
  password: "mysecretpassword"

  # Good - Secret 참조
  password:
    secretKeyRef:
      name: postgres-secret
      key: postgres-password
  ```

- [ ] **Secret 템플릿 사용**
  - 위치: `secrets/templates/`
  - 생성: `./secrets/generate-secrets.sh all`
  - `.env` 파일은 `.gitignore`에 포함

- [ ] **.env 파일 커밋 금지**
  ```bash
  # .gitignore 확인
  grep -q "secrets/.env" .gitignore
  ```

- [ ] **runAsNonRoot SecurityContext**
  ```yaml
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  ```

### 🟡 Important Checks

- [ ] **Capabilities 제거**
  ```yaml
  securityContext:
    capabilities:
      drop:
        - ALL
  ```

- [ ] **NetworkPolicy 기본 설정**
  - 네임스페이스 간 트래픽 제한
  - 필요한 포트만 허용

### 🟢 Suggested Checks

- [ ] Pod Security Standards 적용
- [ ] 이미지 스캐닝 통합

---

## 4. Quality Domain

### 🔴 Critical Checks

- [ ] **Shebang 확인**
  ```bash
  #!/bin/bash
  # 또는
  #!/usr/bin/env bash
  ```

- [ ] **에러 종료 설정**
  ```bash
  set -e          # 에러 시 종료
  set -u          # 미정의 변수 에러 (권장)
  set -o pipefail # 파이프라인 에러 전파
  ```

- [ ] **Shellcheck 통과**
  ```bash
  shellcheck scripts/**/*.sh
  # 허용 예외: SC1091 (source), SC2034 (unused)
  ```

- [ ] **YAML 문법 유효**
  ```bash
  yamllint helm/*.yaml k8s/**/*.yaml
  kubectl apply --dry-run=client -f k8s/
  ```

- [ ] **CLAUDE.md 최신 상태**
  - 새로운 기능/변경사항 반영
  - 예시 명령어 동작 확인

### 🟡 Important Checks

- [ ] **함수 문서화**
  ```bash
  # Description: Deploy Kafka to infra namespace
  # Arguments:
  #   $1 - profile (8gb|16gb|32gb)
  # Returns:
  #   0 - success, 1 - failure
  deploy_kafka() {
    ...
  }
  ```

- [ ] **일관된 들여쓰기**
  - YAML: 2 spaces
  - Bash: 2 spaces

### 🟢 Suggested Checks

- [ ] Anchors/aliases for repeated YAML values
- [ ] 주석으로 비명시적 설정 설명

---

## 5. Testing Domain

### 🔴 Critical Checks

- [ ] **Preflight 검사 존재**
  ```bash
  run_preflight_checks() {
    check_required_tools
    validate_kubectl_connection
    validate_helm_repos
  }
  ```

- [ ] **배포 후 검증**
  ```bash
  validate_deployment() {
    kubectl wait --for=condition=ready pod -l app=kafka --timeout=300s
    kubectl exec kafka-0 -- kafka-topics.sh --list --bootstrap-server localhost:9092
  }
  ```

- [ ] **kubectl --dry-run 호환**
  ```bash
  # 모든 매니페스트가 dry-run 통과해야 함
  kubectl apply --dry-run=client -f k8s/namespace/
  ```

- [ ] **에러 경로 테스트**
  - 잘못된 입력 처리
  - 네트워크 타임아웃 처리
  - 리소스 부족 처리

### 🟡 Important Checks

- [ ] **Pod readiness 확인 후 진행**
  ```bash
  wait_for_pods() {
    local namespace=$1
    local label=$2
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout=300s
  }
  ```

- [ ] **CRD 스키마 검증**
  - cert-manager Certificates
  - ArgoCD Applications

### 🟢 Suggested Checks

- [ ] Bats 테스트 프레임워크 도입
- [ ] kubeval/kubeconform 통합

---

## 6. Operations Domain

### 🔴 Critical Checks

- [ ] **Prometheus scraping 설정**
  ```yaml
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
  ```

- [ ] **Grafana datasources 자동 프로비저닝**
  - Loki: `http://loki:3100`
  - Prometheus: `http://prometheus-server.monitoring:80`

- [ ] **체크포인트/재개 기능**
  ```bash
  # 체크포인트 저장
  save_checkpoint "phase_02"

  # 체크포인트에서 재개
  ./deploy-all.sh --resume
  ```

- [ ] **Health probes 설정**
  ```yaml
  livenessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10

  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
  ```

### 🟡 Important Checks

- [ ] **Alert rules 정의**
  - Pod crash loop
  - High memory usage
  - High CPU usage

- [ ] **롤백 절차 문서화**

### 🟢 Suggested Checks

- [ ] Runbooks for incident response
- [ ] Capacity planning guidelines

---

## 빠른 검사 스크립트

```bash
#!/bin/bash
# quick-review.sh - 빠른 리뷰 체크

echo "=== Quick Infrastructure Review ==="

# 1. Shellcheck
echo ">> Running shellcheck..."
shellcheck scripts/**/*.sh 2>/dev/null | head -20

# 2. YAML syntax
echo ">> Validating YAML..."
for f in helm/*.yaml k8s/**/*.yaml; do
  if ! kubectl apply --dry-run=client -f "$f" > /dev/null 2>&1; then
    echo "  ❌ $f"
  fi
done

# 3. Secret check
echo ">> Checking for hardcoded secrets..."
grep -rn "password:" helm/ k8s/ --include="*.yaml" | grep -v "secretKeyRef" | head -10

# 4. ARM64 check
echo ">> Checking ARM64 compatibility..."
grep -rn "image:" helm/ k8s/ --include="*.yaml" | grep -v "arm64\|aarch64\|bitnamilegacy" | head -10

echo "=== Review Complete ==="
```

---

## 참고 자료

- [CLAUDE.md](/CLAUDE.md) - 프로젝트 컨텍스트 및 컨벤션
- [/sc:review](/Users/sonmingi/.claude/commands/sc/review.md) - 로컬 리뷰 명령어
- [Anthropic Claude Code Action](https://github.com/anthropics/claude-code-action) - GitHub Actions 통합
