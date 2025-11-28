# 보안 게이트웨이 + 외부 접근 설정 가이드

**완료일**: 2025-10-26
**도메인**: son.duckdns.org
**인증 방식**: OAuth2 (GitHub) + JWT

---

## 🎯 구축된 아키텍처

```
외부 인터넷
    ↓
son.duckdns.org (80/443) ← DuckDNS 무료 도메인
    ↓
공유기 포트 포워딩
    ↓
Mac Mini:31599/31818 ← k3s NodePort
    ↓
k3s NGINX Ingress
    ↓
┌──────────────────────────────┐
│ son.duckdns.org              │ ← OAuth2 로그인 게이트웨이
│ GitHub 계정으로 인증          │
└──────────────────────────────┘
    ↓ (인증 후 접근)
├─ pgadmin.son.duckdns.org (OAuth2 보호)
├─ kafka-ui.son.duckdns.org (OAuth2 보호)
└─ api.son.duckdns.org (JWT 인증)
```

---

## 📂 생성된 파일 목록

### 인증 리소스 (k8s/auth/)
- `oauth2-proxy.yaml` - OAuth2 Proxy Deployment/Service/Ingress
- `jwt-service.yaml` - JWT 발급/검증 API 서비스

### 업데이트된 Ingress
- `k8s/test-service/deployment.yaml` - OAuth2 인증 + son.duckdns.org
- `k8s/postgres/pgadmin.yaml` - OAuth2 인증 + pgadmin.son.duckdns.org
- `k8s/kafka/kafka-ui.yaml` - OAuth2 인증 + kafka-ui.son.duckdns.org

### DuckDNS 스크립트
- `~/duckdns/duck.sh` - DuckDNS 자동 업데이트 스크립트
- `scripts/setup-duckdns-cron.sh` - Cron 작업 설정 스크립트

### 헬퍼 스크립트
- `scripts/generate-auth-secrets.sh` - k8s Secret 생성 스크립트
- `scripts/test-external-access.sh` - 외부 접근 테스트 스크립트

### 가이드 문서
- `claudedocs/github-oauth-setup-guide.md` - GitHub OAuth App 설정 가이드
- `claudedocs/router-port-forwarding-guide.md` - 공유기 포트 포워딩 가이드
- `claudedocs/SETUP_GUIDE.md` - 이 파일 (전체 설정 가이드)

---

## 🚀 설정 단계 (순서대로 진행)

### ✅ Phase 1: DuckDNS 설정 (10분)

#### 1.1 DuckDNS 계정 생성
1. https://www.duckdns.org 접속
2. GitHub, Google 등으로 로그인
3. 서브도메인 등록: `son` 입력 → **add domain**
4. **Token 복사** (나중에 필요)

#### 1.2 DuckDNS 스크립트 토큰 설정
```bash
# duck.sh 파일 열기
vi ~/duckdns/duck.sh

# YOUR_TOKEN_HERE를 복사한 토큰으로 교체
DUCKDNS_TOKEN="복사한_토큰_붙여넣기"

# 저장 후 종료 (:wq)
```

#### 1.3 Cron 작업 설정
```bash
# Cron 자동 설정 스크립트 실행
~/Desktop/infra/scripts/setup-duckdns-cron.sh
```

#### 1.4 DuckDNS 확인
```bash
# 로그 확인
cat ~/duckdns/duck.log

# DNS 조회 확인
nslookup son.duckdns.org
```

---

### ✅ Phase 2: GitHub OAuth App 생성 (15분)

**상세 가이드**: `claudedocs/github-oauth-setup-guide.md`

#### 2.1 GitHub OAuth App 등록
1. https://github.com/settings/developers 접속
2. **OAuth Apps** → **New OAuth App**
3. 정보 입력:
   - Application name: `Mac Mini k3s Gateway`
   - Homepage URL: `https://son.duckdns.org`
   - **Authorization callback URL**: `https://son.duckdns.org/oauth2/callback`
4. **Register application** 클릭

#### 2.2 Client ID/Secret 획득
1. **Client ID** 복사
2. **Generate a new client secret** 클릭
3. **Client secret** 복사 (즉시! 다시 볼 수 없음)

#### 2.3 k8s Secret 생성
```bash
cd ~/Desktop/infra

# Secret 생성 스크립트 실행
./scripts/generate-auth-secrets.sh

# 입력 정보:
# - GitHub OAuth Client ID: [복사한 Client ID]
# - GitHub OAuth Client Secret: [복사한 Client Secret]
# - 허용할 이메일 도메인: youremail@gmail.com 또는 gmail.com
```

---

### ✅ Phase 3: k8s 리소스 배포 (10분)

#### 3.1 인증 서비스 배포
```bash
cd ~/Desktop/infra

# OAuth2 Proxy + JWT Service 배포
kubectl apply -f k8s/auth/

# Pod 상태 확인 (Running이 될 때까지 대기)
kubectl get pods -n infra -w
# Ctrl+C로 종료
```

#### 3.2 업데이트된 Ingress 적용
```bash
# 모든 Ingress 업데이트 적용
kubectl apply -f k8s/test-service/deployment.yaml
kubectl apply -f k8s/postgres/pgadmin.yaml
kubectl apply -f k8s/kafka/kafka-ui.yaml

# Ingress 확인
kubectl get ingress -A
```

**예상 결과**:
```
NAMESPACE   NAME                   HOSTS
infra       oauth2-proxy-ingress   son.duckdns.org
infra       pgadmin-ingress        pgadmin.son.duckdns.org
infra       kafka-ui-ingress       kafka-ui.son.duckdns.org
infra       jwt-service-ingress    api.son.duckdns.org
test        test-service-ingress   son.duckdns.org
```

---

### ✅ Phase 4: 공유기 포트 포워딩 (15분)

**상세 가이드**: `claudedocs/router-port-forwarding-guide.md`

#### 4.1 공유기 관리 페이지 접속
- ipTIME: http://192.168.0.1
- KT: http://192.168.219.1
- SK: http://192.168.1.1

#### 4.2 Mac Mini IP 예약
1. **DHCP 서버 설정** 또는 **수동 IP 할당**
2. Mac Mini MAC 주소 → `192.168.45.135` 매핑

#### 4.3 포트 포워딩 규칙 추가

**규칙 1: HTTP**
- 외부 포트: `80`
- 내부 IP: `192.168.45.135`
- 내부 포트: `31599`
- 프로토콜: `TCP`

**규칙 2: HTTPS**
- 외부 포트: `443`
- 내부 IP: `192.168.45.135`
- 내부 포트: `31818`
- 프로토콜: `TCP`

#### 4.4 저장 및 재부팅
공유기 설정 저장 후 필요 시 재부팅

---

### ✅ Phase 5: 로컬 테스트 (5분)

#### 5.1 /etc/hosts 설정
```bash
sudo vi /etc/hosts
```

다음 라인 추가:
```
127.0.0.1 son.duckdns.org
127.0.0.1 pgadmin.son.duckdns.org
127.0.0.1 kafka-ui.son.duckdns.org
127.0.0.1 api.son.duckdns.org
```

#### 5.2 브라우저 접속 테스트
```
http://son.duckdns.org:31599
```

**예상 결과**: OAuth2 로그인 페이지 표시

#### 5.3 API 테스트
```bash
# JWT 토큰 발급 엔드포인트 (401 예상 - 정상)
curl http://api.son.duckdns.org:31599/auth/token

# 예상 응답: {"error":"Unauthorized - No email provided"}
```

---

### ✅ Phase 6: 외부 접근 테스트 (10분)

#### 6.1 테스트 스크립트 실행
```bash
cd ~/Desktop/infra
./scripts/test-external-access.sh
```

#### 6.2 다른 네트워크에서 접속
**모바일 데이터나 다른 WiFi에서**:
```
http://son.duckdns.org
http://pgadmin.son.duckdns.org
http://kafka-ui.son.duckdns.org
```

#### 6.3 OAuth2 로그인 테스트
1. 브라우저에서 `http://son.duckdns.org` 접속
2. **Sign in with GitHub** 클릭
3. GitHub 로그인
4. **Authorize** 클릭
5. 로그인 성공 시 test-service 페이지 표시

---

## 📱 서비스 접근 URL

| 서비스 | URL | 인증 방식 |
|--------|-----|-----------|
| **메인 (Test Service)** | http://son.duckdns.org | OAuth2 (GitHub) |
| **pgAdmin** | http://pgadmin.son.duckdns.org | OAuth2 (GitHub) |
| **Kafka UI** | http://kafka-ui.son.duckdns.org | OAuth2 (GitHub) |
| **JWT API** | http://api.son.duckdns.org/auth/token | JWT Token |

---

## 🔐 JWT API 사용 방법

### 1. JWT 토큰 발급
```bash
# OAuth2 인증 후 토큰 발급
curl -X POST http://api.son.duckdns.org/auth/token \
  -H "X-Auth-Request-Email: your@email.com" \
  -H "Content-Type: application/json"

# 응답:
# {
#   "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
#   "expires_in": 86400,
#   "token_type": "Bearer"
# }
```

### 2. JWT 토큰 검증
```bash
# Authorization 헤더에 Bearer 토큰 포함
curl -X POST http://api.son.duckdns.org/auth/verify \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 응답:
# {
#   "valid": true,
#   "email": "your@email.com",
#   "user": "your@email.com",
#   "exp": 1729999999
# }
```

### 3. JWT 토큰 갱신
```bash
curl -X POST http://api.son.duckdns.org/auth/refresh \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

---

## 🔧 문제 해결

### 문제 1: 외부에서 접근 안 됨

**확인 사항**:
```bash
# 1. DuckDNS DNS 확인
nslookup son.duckdns.org

# 2. 공인 IP 확인
curl ifconfig.me

# 3. 포트 포워딩 확인
# 공유기 관리 페이지에서 80→192.168.45.135:31599 확인

# 4. k8s Pod 상태 확인
kubectl get pods -n infra

# 5. Ingress 확인
kubectl get ingress -A
```

### 문제 2: OAuth2 로그인 실패

**GitHub Callback URL 확인**:
- GitHub OAuth App 설정
- Authorization callback URL: `https://son.duckdns.org/oauth2/callback`
- 정확히 입력되었는지 확인 (https, 끝에 / 없음)

### 문제 3: JWT 토큰 발급 실패

**Secret 확인**:
```bash
# Secret 존재 확인
kubectl get secret jwt-secrets -n infra

# Pod 로그 확인
kubectl logs -n infra -l app=jwt-service
```

### 문제 4: DuckDNS IP 업데이트 안 됨

```bash
# 수동 업데이트
~/duckdns/duck.sh

# 로그 확인
cat ~/duckdns/duck.log

# Cron 작업 확인
crontab -l | grep duckdns
```

---

## 📊 현재 설정 상태 확인

```bash
# k8s 리소스 상태
kubectl get all -n infra
kubectl get ingress -A

# DuckDNS 상태
cat ~/duckdns/duck.log

# Cron 작업
crontab -l

# 외부 접근 테스트
~/Desktop/infra/scripts/test-external-access.sh
```

---

## 🎉 완료!

모든 설정이 완료되었습니다! 이제 다음이 가능합니다:

✅ 외부 인터넷에서 son.duckdns.org 접근
✅ GitHub 계정으로 OAuth2 인증
✅ 인증 후 pgAdmin, Kafka UI 접근
✅ JWT 토큰으로 API 호출
✅ 자동 DuckDNS IP 업데이트 (5분마다)

---

## 📚 추가 보안 설정 (선택사항)

### HTTPS 인증서 (Let's Encrypt)
```bash
# cert-manager 설치
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# ClusterIssuer 생성 (Let's Encrypt)
# 추후 필요 시 설정
```

### Rate Limiting
```yaml
# Ingress annotations 추가
nginx.ingress.kubernetes.io/limit-rps: "10"
```

### IP 화이트리스트
```yaml
# Ingress annotations 추가
nginx.ingress.kubernetes.io/whitelist-source-range: "your.ip.address/32"
```

---

## 📞 지원

- **GitHub OAuth 가이드**: claudedocs/github-oauth-setup-guide.md
- **포트 포워딩 가이드**: claudedocs/router-port-forwarding-guide.md
- **외부 접근 원본 계획**: claudedocs/external_access_plan_20251026.md
