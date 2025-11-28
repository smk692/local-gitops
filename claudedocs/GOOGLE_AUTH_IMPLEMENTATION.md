# Google OAuth2 + PostgreSQL 계정 관리 시스템 구현 완료

**완료일**: 2025-10-26
**시스템**: Google OAuth2 + PostgreSQL 화이트리스트 기반 인증
**도메인**: son.duckdns.org

---

## 🎯 구현된 아키텍처

```
외부 인터넷
    ↓
son.duckdns.org (80/443)
    ↓
공유기 포트 포워딩
    ↓
Mac Mini:31599/31818 (k3s NodePort)
    ↓
k3s NGINX Ingress
    ↓
┌──────────────────────────────────────┐
│ 1단계: OAuth2 Proxy                  │
│ → Google 계정으로 로그인              │
└──────────────────────────────────────┘
    ↓
┌──────────────────────────────────────┐
│ 2단계: Auth Validator                │
│ → PostgreSQL 화이트리스트 검증        │
│ → 사용자 생성/업데이트                │
│ → 로그인 이력 기록                    │
└──────────────────────────────────────┘
    ↓
┌──────────────────────────────────────┐
│ 접근 허용: 서비스로 진입              │
│ - pgAdmin (PostgreSQL 관리)          │
│ - Kafka UI (Kafka 모니터링)          │
│ - Admin UI (계정 관리)               │
└──────────────────────────────────────┘
```

---

## 📦 생성된 파일 목록

### 인증 리소스 (k8s/auth/)

#### `oauth2-proxy.yaml`
- **역할**: Google OAuth2 인증 프록시
- **주요 설정**:
  - Provider: Google
  - Cookie 기반 세션 관리 (7일)
  - 모든 Google 계정 허용 (화이트리스트에서 검증)

#### `auth-validator.yaml`
- **역할**: 화이트리스트 검증 및 사용자 관리
- **기능**:
  - PostgreSQL 화이트리스트 조회
  - 사용자 자동 생성/업데이트
  - 로그인 이력 기록
  - 통계 API (`/stats`)

#### `admin-ui.yaml`
- **역할**: 웹 기반 관리자 인터페이스
- **기능**:
  - 화이트리스트 관리 (추가/삭제)
  - 사용자 목록 조회
  - 로그인 이력 조회
  - 대시보드 통계

#### `jwt-service.yaml`
- **역할**: JWT 토큰 발급/검증 API
- **엔드포인트**:
  - `/auth/token` - 토큰 발급
  - `/auth/verify` - 토큰 검증
  - `/auth/refresh` - 토큰 갱신

### PostgreSQL 스키마 (k8s/postgres/)

#### `init-schema.sql`
- **역할**: 데이터베이스 스키마 정의
- **테이블**:
  - `allowed_emails` - 이메일 화이트리스트
  - `users` - 등록된 사용자 정보
  - `login_history` - 로그인 이력

### 스크립트 (scripts/)

#### `init-auth-database.sh`
- **역할**: PostgreSQL 스키마 초기화
- **기능**: 관리자 이메일 입력 및 화이트리스트 추가

#### `generate-auth-secrets.sh`
- **역할**: Kubernetes Secret 생성 (Google OAuth2용)
- **생성 Secret**:
  - `oauth2-proxy-secrets` - OAuth2 Proxy 인증 정보
  - `jwt-secrets` - JWT 비밀키

#### `deploy-google-auth.sh` ⭐ 새로 생성
- **역할**: 전체 인증 시스템 배포 자동화
- **기능**:
  - 전제 조건 확인
  - PostgreSQL 스키마 초기화
  - Secrets 확인/생성
  - 모든 인증 리소스 배포
  - Pod 상태 확인
  - 헬스체크

### 업데이트된 Ingress

#### `k8s/postgres/pgadmin.yaml`
- OAuth2 Proxy + Auth Validator 2단계 인증 추가
- `pgadmin.son.duckdns.org` 도메인 설정

#### `k8s/kafka/kafka-ui.yaml`
- OAuth2 Proxy + Auth Validator 2단계 인증 추가
- `kafka-ui.son.duckdns.org` 도메인 설정

### 문서 (claudedocs/)

#### `google-oauth-setup-guide.md` ⭐ 새로 생성
- **역할**: Google Cloud Console 설정 가이드
- **내용**:
  - 프로젝트 생성
  - OAuth 동의 화면 설정
  - OAuth 2.0 클라이언트 ID 생성
  - 리디렉션 URI 설정
  - 문제 해결 가이드

#### `GOOGLE_AUTH_IMPLEMENTATION.md` ⭐ 이 파일
- **역할**: 구현 완료 요약 문서

---

## 🔐 데이터베이스 스키마

### allowed_emails (화이트리스트)
```sql
- id: SERIAL PRIMARY KEY
- email: VARCHAR(255) UNIQUE NOT NULL
- added_at: TIMESTAMP (자동)
- added_by: VARCHAR(255) (추가한 관리자)
- notes: TEXT (메모)
```

### users (사용자)
```sql
- id: SERIAL PRIMARY KEY
- email: VARCHAR(255) UNIQUE NOT NULL
- name: VARCHAR(255)
- picture_url: TEXT
- first_login: TIMESTAMP (자동)
- last_login: TIMESTAMP (자동 업데이트)
- login_count: INT (자동 증가)
```

### login_history (로그인 이력)
```sql
- id: SERIAL PRIMARY KEY
- user_email: VARCHAR(255) NOT NULL
- login_at: TIMESTAMP (자동)
- ip_address: VARCHAR(50)
- user_agent: TEXT
```

---

## 🚀 배포 방법

### 빠른 배포 (추천)

```bash
cd ~/Desktop/infra

# 1. 전체 배포 스크립트 실행
./scripts/deploy-google-auth.sh
```

스크립트가 다음을 자동으로 수행합니다:
1. ✅ 전제 조건 확인 (k3s, PostgreSQL)
2. ✅ PostgreSQL 스키마 초기화
3. ✅ Secrets 확인/생성 안내
4. ✅ 모든 인증 리소스 배포
5. ✅ Pod 상태 확인 (최대 2분 대기)
6. ✅ 헬스체크
7. ✅ 배포 완료 안내

### 수동 배포 (단계별)

#### 1단계: PostgreSQL 스키마 초기화
```bash
cd ~/Desktop/infra
./scripts/init-auth-database.sh

# 관리자 이메일 입력: your@gmail.com
```

#### 2단계: Secrets 생성
```bash
./scripts/generate-auth-secrets.sh

# Google OAuth Client ID 입력
# Google OAuth Client Secret 입력
```

#### 3단계: 인증 리소스 배포
```bash
kubectl apply -f k8s/auth/
```

#### 4단계: Ingress 업데이트
```bash
kubectl apply -f k8s/postgres/pgadmin.yaml
kubectl apply -f k8s/kafka/kafka-ui.yaml
```

#### 5단계: Pod 상태 확인
```bash
kubectl get pods -n infra -w
# Ctrl+C로 종료
```

---

## 🔧 Google OAuth2 설정

### Google Cloud Console 설정 필수!

배포 후 반드시 Google Cloud Console에서 OAuth 2.0 클라이언트 ID를 생성해야 합니다.

**상세 가이드**: `claudedocs/google-oauth-setup-guide.md`

#### 간단 요약:
1. https://console.cloud.google.com/ 접속
2. 프로젝트 생성
3. OAuth 동의 화면 설정 (외부)
4. OAuth 2.0 클라이언트 ID 생성
5. 리디렉션 URI: `https://son.duckdns.org/oauth2/callback`
6. Client ID와 Secret 복사
7. Kubernetes Secret 생성 (`generate-auth-secrets.sh`)

---

## 📱 서비스 접근 URL

### 로컬 테스트 (Mac Mini 내부)

**/etc/hosts 설정 필요**:
```
127.0.0.1 son.duckdns.org
127.0.0.1 admin.son.duckdns.org
127.0.0.1 pgadmin.son.duckdns.org
127.0.0.1 kafka-ui.son.duckdns.org
```

**접근 URL**:
- 관리자 UI: `http://admin.son.duckdns.org:31599`
- pgAdmin: `http://pgadmin.son.duckdns.org:31599`
- Kafka UI: `http://kafka-ui.son.duckdns.org:31599`

### 외부 접근 (포트 포워딩 설정 후)

- 관리자 UI: `http://admin.son.duckdns.org`
- pgAdmin: `http://pgadmin.son.duckdns.org`
- Kafka UI: `http://kafka-ui.son.duckdns.org`

---

## 🎨 주요 기능

### 1. 2단계 인증 시스템

#### 1단계: OAuth2 Proxy
- Google 계정 로그인
- OAuth2 표준 준수
- 자동 세션 관리

#### 2단계: Auth Validator
- 화이트리스트 검증
- 사용자 자동 등록
- 로그인 이력 기록

### 2. 관리자 UI (admin.son.duckdns.org)

#### Dashboard
- 화이트리스트 이메일 수
- 등록된 사용자 수
- 24시간 로그인 수
- 7일 로그인 수
- 최근 로그인 10개

#### Whitelist 관리
- 이메일 추가 (메모 포함)
- 이메일 삭제
- 추가자 및 추가 시각 표시

#### Users 목록
- 모든 등록 사용자 조회
- 첫 로그인 / 마지막 로그인
- 총 로그인 횟수

#### Login History
- 최근 100개 로그인 기록
- IP 주소 및 User Agent 표시
- 시간순 정렬

### 3. 자동 사용자 관리

#### 최초 로그인 시:
1. Google 로그인 성공
2. 이메일이 화이트리스트에 있는지 확인
3. 있으면: `users` 테이블에 사용자 생성
4. 없으면: 403 Forbidden

#### 재로그인 시:
1. Google 로그인 성공
2. 이메일 화이트리스트 재확인
3. `users` 테이블 업데이트 (last_login, login_count)
4. `login_history` 테이블에 기록 추가

---

## 🔍 상태 확인 및 모니터링

### Pod 상태 확인
```bash
kubectl get pods -n infra
```

**예상 출력**:
```
NAME                              READY   STATUS    RESTARTS   AGE
oauth2-proxy-xxx                  1/1     Running   0          5m
auth-validator-xxx                1/1     Running   0          5m
admin-ui-xxx                      1/1     Running   0          5m
jwt-service-xxx                   1/1     Running   0          5m
postgresql-xxx                    1/1     Running   0          1h
```

### 서비스 확인
```bash
kubectl get svc -n infra
```

### Ingress 확인
```bash
kubectl get ingress -n infra
```

**예상 출력**:
```
NAME                   HOSTS                        ADDRESS   PORTS
oauth2-proxy-ingress   son.duckdns.org              ...       80
admin-ui-ingress       admin.son.duckdns.org        ...       80
pgadmin-ingress        pgadmin.son.duckdns.org      ...       80
kafka-ui-ingress       kafka-ui.son.duckdns.org     ...       80
```

### 로그 확인
```bash
# OAuth2 Proxy 로그
kubectl logs -n infra -l app=oauth2-proxy

# Auth Validator 로그
kubectl logs -n infra -l app=auth-validator

# Admin UI 로그
kubectl logs -n infra -l app=admin-ui
```

### 헬스체크 API
```bash
# Auth Validator 헬스체크
kubectl exec -n infra -l app=auth-validator -- curl http://localhost:8080/health

# 통계 조회
kubectl exec -n infra -l app=auth-validator -- curl http://localhost:8080/stats

# Admin UI 헬스체크
kubectl exec -n infra -l app=admin-ui -- curl http://localhost:8080/health
```

---

## 🐛 문제 해결

### 문제 1: Pod가 시작되지 않음

**확인 사항**:
```bash
# Pod 상태 확인
kubectl get pods -n infra

# Pod 이벤트 확인
kubectl describe pod -n infra <pod-name>

# Pod 로그 확인
kubectl logs -n infra <pod-name>
```

**일반적인 원인**:
- Secret이 없거나 잘못됨 → `kubectl get secret -n infra`
- 이미지 pull 실패 → `kubectl describe pod` 확인
- PostgreSQL 연결 실패 → PostgreSQL Pod 상태 확인

### 문제 2: "redirect_uri_mismatch" 오류

**원인**: Google Cloud Console의 리디렉션 URI가 잘못 설정됨

**해결**:
1. Google Cloud Console → OAuth 2.0 클라이언트 ID 설정
2. 리디렉션 URI 확인: `https://son.duckdns.org/oauth2/callback`
3. 정확히 입력 (https, 끝에 / 없음)

### 문제 3: "access_denied" 오류

**원인**: OAuth 동의 화면에서 테스트 사용자로 추가되지 않음

**해결**:
1. Google Cloud Console → OAuth 동의 화면
2. "테스트 사용자" 섹션에서 사용자 추가
3. 로그인할 Gmail 주소 입력

### 문제 4: 로그인 후 403 Forbidden

**원인**: 화이트리스트에 이메일이 없음

**해결**:
```bash
# 방법 1: 스크립트로 추가
./scripts/init-auth-database.sh

# 방법 2: Admin UI에서 추가
# http://admin.son.duckdns.org → Whitelist → Add Email
```

### 문제 5: PostgreSQL 연결 실패

**확인**:
```bash
# PostgreSQL Pod 상태
kubectl get pods -n infra -l app.kubernetes.io/name=postgresql

# PostgreSQL 로그
kubectl logs -n infra -l app.kubernetes.io/name=postgresql

# Secret 확인
kubectl get secret postgresql -n infra -o yaml
```

---

## 📊 시스템 동작 흐름

### 신규 사용자 첫 로그인

```
1. 사용자가 http://pgadmin.son.duckdns.org 접속
   ↓
2. NGINX Ingress가 OAuth2 Proxy로 리다이렉트
   ↓
3. OAuth2 Proxy가 Google 로그인 페이지 표시
   ↓
4. 사용자가 Google 계정으로 로그인
   ↓
5. Google이 OAuth2 Proxy로 인증 결과 전달
   ↓
6. OAuth2 Proxy가 사용자 정보 헤더 추가 (X-Auth-Request-Email)
   ↓
7. NGINX Ingress가 Auth Validator에 subrequest
   ↓
8. Auth Validator가 PostgreSQL 화이트리스트 조회
   ↓
9a. 화이트리스트에 있음:
    - users 테이블에 사용자 생성
    - login_history 테이블에 기록
    - 200 OK 반환 → pgAdmin 접근 허용
   ↓
9b. 화이트리스트에 없음:
    - 403 Forbidden 반환 → 접근 거부
```

### 기존 사용자 재로그인

```
1. 사용자가 서비스 접속
   ↓
2. OAuth2 Proxy 세션 쿠키 확인
   ↓
3a. 세션 유효:
    - 바로 Auth Validator 검증
    ↓
3b. 세션 만료:
    - Google 로그인 다시 수행
    ↓
4. Auth Validator 검증:
    - 화이트리스트 재확인
    - users 테이블 업데이트 (last_login, login_count++)
    - login_history 테이블에 기록
    ↓
5. 서비스 접근 허용
```

---

## 🔐 보안 고려사항

### 1. Secret 관리
- ✅ Client Secret은 Kubernetes Secret으로만 관리
- ✅ 절대 Git 저장소에 커밋하지 말 것
- ✅ 정기적으로 Secret 변경 권장 (3-6개월)

### 2. 화이트리스트 관리
- ✅ 필요한 사용자만 추가
- ✅ 정기적으로 불필요한 사용자 제거
- ✅ Admin UI 접근도 화이트리스트로 보호

### 3. PostgreSQL 보안
- ✅ PostgreSQL 비밀번호 변경 권장
- ✅ PostgreSQL은 클러스터 내부에서만 접근 가능 (ClusterIP)
- ✅ 정기적인 백업 권장

### 4. OAuth2 설정
- ✅ Cookie는 HTTPOnly, Secure, SameSite=lax
- ✅ Cookie 유효기간: 7일
- ✅ 자동 refresh: 1시간마다

### 5. 네트워크 보안
- ✅ Ingress에서 rate limiting 고려
- ✅ IP 화이트리스트 고려 (필요시)
- ✅ DDoS 방어 고려

---

## 📚 관련 문서

### 구현 가이드
- **Google OAuth 설정**: `claudedocs/google-oauth-setup-guide.md`
- **포트 포워딩 설정**: `claudedocs/router-port-forwarding-guide.md`
- **전체 설정 가이드**: `claudedocs/SETUP_GUIDE.md` (GitHub용, 업데이트 필요)

### 스크립트
- **배포 스크립트**: `scripts/deploy-google-auth.sh`
- **DB 초기화**: `scripts/init-auth-database.sh`
- **Secret 생성**: `scripts/generate-auth-secrets.sh`
- **외부 접근 테스트**: `scripts/test-external-access.sh`

### 설정 파일
- **OAuth2 Proxy**: `k8s/auth/oauth2-proxy.yaml`
- **Auth Validator**: `k8s/auth/auth-validator.yaml`
- **Admin UI**: `k8s/auth/admin-ui.yaml`
- **DB 스키마**: `k8s/postgres/init-schema.sql`

---

## 🎉 다음 단계

### 1. Google OAuth App 생성
```bash
claudedocs/google-oauth-setup-guide.md 참조
```

### 2. 외부 접근 설정
```bash
# DuckDNS 설정
~/duckdns/duck.sh 실행 확인

# 공유기 포트 포워딩 확인
80 → 192.168.45.135:31599
443 → 192.168.45.135:31818
```

### 3. 외부 접근 테스트
```bash
./scripts/test-external-access.sh
```

### 4. 첫 로그인
1. 브라우저에서 `http://admin.son.duckdns.org` 접속
2. Google 로그인
3. 화이트리스트 관리 시작

---

## ✅ 구현 완료 체크리스트

- ✅ PostgreSQL 스키마 생성 (allowed_emails, users, login_history)
- ✅ OAuth2 Proxy를 GitHub에서 Google로 변경
- ✅ Auth Validator 서비스 생성 (화이트리스트 검증)
- ✅ Admin UI 생성 (관리자 인터페이스)
- ✅ Google OAuth App 설정 가이드 작성
- ✅ Secret 생성 스크립트 업데이트 (Google용)
- ✅ 배포 스크립트 생성 (deploy-google-auth.sh)
- ✅ 모든 Ingress에 2단계 인증 적용
- ✅ 문서화 완료

---

**구현 완료!** 🎉

이제 Google 계정으로 안전하게 서비스에 접근할 수 있습니다.
화이트리스트 기반 자동 사용자 등록으로 편리하게 계정을 관리할 수 있습니다.
