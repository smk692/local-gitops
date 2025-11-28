# CI/CD 파이프라인 가이드

Mac Mini 인프라를 위한 지속적 통합 및 배포 가이드입니다.

## 📦 CI/CD 아키텍처

```
GitHub Repository
    ↓
GitHub Actions (CI)
    ↓ (Build & Push)
Container Registry
    ↓ (Deploy)
k3d Cluster (CD)
```

## 🔧 GitHub Actions 설정

### 1. Backend CI/CD 워크플로우

`.github/workflows/backend-deploy.yml`:

```yaml
name: Backend CI/CD

on:
  push:
    branches: [ main ]
    paths:
      - 'backend/**'
  pull_request:
    branches: [ main ]
    paths:
      - 'backend/**'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/backend

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2

    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v4
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
          type=sha

    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: ./backend
        platforms: linux/arm64  # Mac Mini ARM 지원
        push: ${{ github.event_name != 'pull_request' }}
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: self-hosted  # Mac Mini에서 실행
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Update Kubernetes deployment
      run: |
        kubectl set image deployment/backend-service \
          backend=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${GITHUB_SHA::7} \
          -n backend

    - name: Wait for rollout
      run: |
        kubectl rollout status deployment/backend-service -n backend

    - name: Verify deployment
      run: |
        kubectl get pods -n backend
```

### 2. Frontend CI/CD 워크플로우

`.github/workflows/frontend-deploy.yml`:

```yaml
name: Frontend CI/CD

on:
  push:
    branches: [ main ]
    paths:
      - 'frontend/**'
  pull_request:
    branches: [ main ]
    paths:
      - 'frontend/**'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/frontend

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2

    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v4
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=semver,pattern={{version}}
          type=sha

    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: ./frontend
        platforms: linux/arm64
        push: ${{ github.event_name != 'pull_request' }}
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        build-args: |
          NEXT_PUBLIC_API_URL=http://api.local:8080/api
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: self-hosted
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Update Kubernetes deployment
      run: |
        kubectl set image deployment/frontend-service \
          frontend=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${GITHUB_SHA::7} \
          -n frontend

    - name: Wait for rollout
      run: |
        kubectl rollout status deployment/frontend-service -n frontend
```

## 🖥️ Self-Hosted Runner 설정 (Mac Mini)

### 1. GitHub Runner 설치

```bash
# Runner 다운로드
mkdir actions-runner && cd actions-runner
curl -o actions-runner-osx-arm64-2.311.0.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-osx-arm64-2.311.0.tar.gz

# 압축 해제
tar xzf ./actions-runner-osx-arm64-2.311.0.tar.gz

# 설정 (GitHub 저장소에서 토큰 생성 필요)
./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN

# 서비스로 실행
./svc.sh install
./svc.sh start
```

### 2. Runner 권한 설정

```bash
# kubectl 접근 권한 확인
kubectl cluster-info

# Docker 접근 권한 (필요시)
sudo usermod -aG docker $USER
```

### 3. 자동 시작 설정

```bash
# LaunchDaemon 생성
sudo nano /Library/LaunchDaemons/com.github.runner.plist
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.github.runner</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USER/actions-runner/run.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/runner.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/runner.err</string>
</dict>
</plist>
```

```bash
# 권한 설정
sudo chown root:wheel /Library/LaunchDaemons/com.github.runner.plist
sudo chmod 644 /Library/LaunchDaemons/com.github.runner.plist

# 로드
sudo launchctl load /Library/LaunchDaemons/com.github.runner.plist
```

## 🔐 Secrets 관리

### GitHub Secrets 설정

Repository Settings → Secrets and variables → Actions:

```
KUBE_CONFIG: <base64 encoded kubeconfig>
REGISTRY_USERNAME: <container registry username>
REGISTRY_PASSWORD: <container registry password>
DB_PASSWORD: <database password>
JWT_SECRET: <jwt secret>
```

### kubeconfig 생성

```bash
# kubeconfig를 base64로 인코딩
cat ~/.kube/config | base64 | pbcopy

# GitHub Secrets에 KUBE_CONFIG로 저장
```

### Kubernetes에서 사용

```yaml
# Deployment에서 Secret 참조
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: backend-secrets
      key: db-password
```

## 🔄 롤링 업데이트 전략

### 기본 롤링 업데이트

```yaml
# deployment.yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # 추가 생성 가능한 Pod 수
      maxUnavailable: 0  # 동시에 종료 가능한 Pod 수
```

### Blue-Green 배포

```bash
# 1. 새 버전 배포 (green)
kubectl apply -f k8s/backend/deployment-green.yaml

# 2. 테스트
kubectl port-forward -n backend svc/backend-service-green 3001:3000

# 3. 서비스 전환
kubectl patch service backend-service -n backend \
  -p '{"spec":{"selector":{"version":"green"}}}'

# 4. 이전 버전 정리
kubectl delete -f k8s/backend/deployment-blue.yaml
```

### Canary 배포

```yaml
# 기존 버전 (90%)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: backend
      version: stable

---
# 새 버전 (10%)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
      version: canary
```

## 📊 배포 모니터링

### 배포 상태 확인

```bash
# 롤아웃 상태
kubectl rollout status deployment/backend-service -n backend

# 롤아웃 히스토리
kubectl rollout history deployment/backend-service -n backend

# 특정 리비전 정보
kubectl rollout history deployment/backend-service -n backend --revision=2
```

### 롤백

```bash
# 이전 버전으로 롤백
kubectl rollout undo deployment/backend-service -n backend

# 특정 리비전으로 롤백
kubectl rollout undo deployment/backend-service -n backend --to-revision=2
```

### 자동 롤백 (Healthcheck 실패 시)

```yaml
spec:
  template:
    spec:
      containers:
      - name: backend
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3  # 3번 실패 시 Pod 재시작
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 3  # 3번 실패 시 트래픽 제거
```

## 🧪 테스트 자동화

### E2E 테스트 워크플로우

```yaml
name: E2E Tests

on:
  pull_request:
    branches: [ main ]

jobs:
  e2e-tests:
    runs-on: self-hosted

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Deploy to test namespace
      run: |
        kubectl apply -f k8s/backend/ -n test
        kubectl apply -f k8s/frontend/ -n test

    - name: Wait for deployment
      run: |
        kubectl wait --for=condition=ready pod \
          -l app=backend-service \
          -n test \
          --timeout=300s

    - name: Run E2E tests
      run: |
        npm run test:e2e

    - name: Cleanup
      if: always()
      run: |
        kubectl delete namespace test
```

## 📈 배포 메트릭

### Grafana 대시보드 설정

배포 관련 주요 메트릭:
- 배포 빈도 (Deployment Frequency)
- 변경 실패율 (Change Failure Rate)
- 평균 복구 시간 (Mean Time to Recover)
- 리드 타임 (Lead Time for Changes)

### Slack 알림 설정

```yaml
# .github/workflows/backend-deploy.yml에 추가
- name: Slack notification on success
  if: success()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'Backend deployment succeeded!'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}

- name: Slack notification on failure
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'Backend deployment failed!'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

## 🔧 로컬 개발 워크플로우

### 1. Docker Compose로 로컬 개발

```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  backend:
    build: ./backend
    ports:
      - "3000:3000"
    environment:
      - DB_HOST=postgres
      - KAFKA_BROKERS=kafka:9092
    volumes:
      - ./backend:/app
    depends_on:
      - postgres
      - kafka

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=dev123
      - POSTGRES_DB=appdb

  kafka:
    image: bitnami/kafka:latest
    environment:
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
    depends_on:
      - zookeeper

  zookeeper:
    image: bitnami/zookeeper:latest
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes
```

### 2. Skaffold로 반복 개발

```yaml
# skaffold.yaml
apiVersion: skaffold/v4beta1
kind: Config
build:
  artifacts:
  - image: backend
    context: backend
    docker:
      dockerfile: Dockerfile
  - image: frontend
    context: frontend
    docker:
      dockerfile: Dockerfile
  local:
    push: false

deploy:
  kubectl:
    manifests:
    - k8s/backend/*.yaml
    - k8s/frontend/*.yaml

portForward:
- resourceType: service
  resourceName: backend-service
  namespace: backend
  port: 3000
  localPort: 3000
```

실행:
```bash
skaffold dev
```

## 📝 체크리스트

### 배포 전

- [ ] 모든 테스트 통과
- [ ] 코드 리뷰 완료
- [ ] 버전 태그 생성
- [ ] 데이터베이스 마이그레이션 확인
- [ ] 환경 변수 및 Secret 업데이트
- [ ] 리소스 제한 검토

### 배포 중

- [ ] 배포 프로세스 모니터링
- [ ] Pod 상태 확인
- [ ] 로그 모니터링
- [ ] 헬스체크 통과 확인

### 배포 후

- [ ] E2E 테스트 실행
- [ ] 성능 메트릭 확인
- [ ] 에러율 모니터링
- [ ] 롤백 계획 준비
- [ ] 문서 업데이트
