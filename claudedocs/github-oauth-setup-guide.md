# GitHub OAuth App 설정 가이드

OAuth2 Proxy를 위한 GitHub OAuth App 등록 방법입니다.

---

## 📋 목차

1. [GitHub OAuth App 생성](#1-github-oauth-app-생성)
2. [Client ID/Secret 획득](#2-client-idsecret-획득)
3. [k8s Secret 생성](#3-k8s-secret-생성)
4. [검증 및 테스트](#4-검증-및-테스트)

---

## 1. GitHub OAuth App 생성

### 1.1 GitHub 설정 페이지 접속

1. GitHub에 로그인
2. 우측 상단 프로필 아이콘 클릭
3. **Settings** 선택
4. 좌측 메뉴에서 **Developer settings** 클릭
5. **OAuth Apps** 선택
6. **New OAuth App** 버튼 클릭

또는 다음 URL로 직접 접속:
```
https://github.com/settings/developers
```

### 1.2 OAuth App 정보 입력

다음 정보를 입력합니다:

| 필드 | 값 | 설명 |
|------|-----|------|
| **Application name** | `Mac Mini k3s Gateway` | 앱 이름 (자유) |
| **Homepage URL** | `https://son.duckdns.org` | 메인 도메인 |
| **Application description** | `OAuth2 Gateway for k3s services` | 설명 (선택사항) |
| **Authorization callback URL** | `https://son.duckdns.org/oauth2/callback` | **중요!** 정확히 입력 |

**⚠️ 중요**: Authorization callback URL은 **반드시 정확**해야 합니다!
- 프로토콜: `https://` (http 아님)
- 도메인: `son.duckdns.org` (포트 포워딩 후 접근 가능한 도메인)
- 경로: `/oauth2/callback` (OAuth2 Proxy 기본 경로)

### 1.3 OAuth App 생성 완료

**Register application** 버튼을 클릭하여 생성 완료

---

## 2. Client ID/Secret 획득

### 2.1 Client ID 복사

생성된 OAuth App 페이지에서:
1. **Client ID**가 표시됩니다
2. 클립보드에 복사 (나중에 사용)

### 2.2 Client Secret 생성

1. **Generate a new client secret** 버튼 클릭
2. **Client secret**이 생성됩니다
3. ⚠️ **즉시 복사하세요!** (다시 볼 수 없습니다)

**중요 메모**:
```
Client ID: <복사한 값 메모>
Client Secret: <복사한 값 메모>
```

---

## 3. k8s Secret 생성

### 3.1 Secret 생성 스크립트 실행

터미널에서 다음 스크립트를 실행합니다:

```bash
cd /Users/sonmingi/Desktop/infra
./scripts/generate-auth-secrets.sh
```

### 3.2 정보 입력

스크립트가 다음 정보를 요청합니다:

1. **GitHub OAuth Client ID**: 위에서 복사한 Client ID 입력
2. **GitHub OAuth Client Secret**: 위에서 복사한 Client Secret 입력
3. **허용할 이메일 도메인**:
   - 특정 이메일만 허용: `youremail@gmail.com`
   - 모든 Gmail 허용: `gmail.com`
   - 여러 도메인: `gmail.com,company.com`

### 3.3 Secret 생성 확인

```bash
# Secret 생성 확인
kubectl get secret oauth2-proxy-secrets -n infra
kubectl get secret jwt-secrets -n infra
```

---

## 4. 검증 및 테스트

### 4.1 OAuth2 Proxy 배포

```bash
# 인증 리소스 배포
kubectl apply -f k8s/auth/

# Pod 상태 확인
kubectl get pods -n infra -l app=oauth2-proxy
kubectl get pods -n infra -l app=jwt-service
```

### 4.2 Ingress 업데이트 적용

```bash
# 업데이트된 Ingress 적용
kubectl apply -f k8s/test-service/deployment.yaml
kubectl apply -f k8s/postgres/pgadmin.yaml
kubectl apply -f k8s/kafka/kafka-ui.yaml

# Ingress 확인
kubectl get ingress -A
```

### 4.3 로컬 테스트 (내부 네트워크)

**Mac Mini에서 /etc/hosts 수정**:
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

**브라우저에서 접속 테스트**:
```
http://son.duckdns.org:31599
```

OAuth2 로그인 페이지가 나타나면 성공!

---

## 🔧 문제 해결

### 문제: "OAuth callback URL mismatch" 오류

**원인**: GitHub OAuth App의 Callback URL이 잘못됨

**해결**:
1. GitHub OAuth App 설정으로 이동
2. Authorization callback URL 확인:
   - 정확히 `https://son.duckdns.org/oauth2/callback`
   - 끝에 `/` 없음
   - `https://` (http 아님)

### 문제: Secret 생성 실패

**원인**: kubectl 권한 문제 또는 namespace 없음

**해결**:
```bash
# infra namespace 확인
kubectl get namespace infra

# namespace 없으면 생성
kubectl create namespace infra

# Secret 다시 생성
./scripts/generate-auth-secrets.sh
```

### 문제: OAuth2 Proxy Pod가 시작 안 됨

**원인**: Secret 값이 잘못되었거나 누락됨

**해결**:
```bash
# Pod 로그 확인
kubectl logs -n infra -l app=oauth2-proxy

# Secret 값 확인
kubectl get secret oauth2-proxy-secrets -n infra -o yaml

# Secret 재생성
kubectl delete secret oauth2-proxy-secrets -n infra
./scripts/generate-auth-secrets.sh
```

---

## 📚 다음 단계

1. ✅ GitHub OAuth App 생성 완료
2. ✅ k8s Secret 생성 완료
3. ✅ OAuth2 Proxy 배포 완료
4. ⏭️ **다음**: 공유기 포트 포워딩 설정 (`router-port-forwarding-guide.md`)

---

## 🔗 참고 자료

- [GitHub OAuth Apps 문서](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [OAuth2 Proxy 문서](https://oauth2-proxy.github.io/oauth2-proxy/)
- [NGINX Ingress OAuth](https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/)
