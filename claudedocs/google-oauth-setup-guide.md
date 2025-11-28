# Google OAuth2 설정 가이드

**목적**: Google 계정을 사용한 OAuth2 인증 시스템 구축
**소요 시간**: 약 15분
**완료 후**: son.duckdns.org에서 Google 계정으로 로그인 가능

---

## 📋 목차

1. [Google Cloud Console 프로젝트 생성](#1-google-cloud-console-프로젝트-생성)
2. [OAuth 동의 화면 설정](#2-oauth-동의-화면-설정)
3. [OAuth2 Client ID 생성](#3-oauth2-client-id-생성)
4. [Kubernetes Secret 생성](#4-kubernetes-secret-생성)
5. [검증 및 테스트](#5-검증-및-테스트)

---

## 1. Google Cloud Console 프로젝트 생성

### 1.1 Google Cloud Console 접속
1. https://console.cloud.google.com/ 접속
2. Google 계정으로 로그인

### 1.2 새 프로젝트 생성
1. 상단 프로젝트 선택 드롭다운 클릭
2. **"새 프로젝트"** 클릭
3. 프로젝트 정보 입력:
   - **프로젝트 이름**: `Mac Mini k3s Auth` (또는 원하는 이름)
   - **위치**: 조직 없음 (개인 계정인 경우)
4. **"만들기"** 클릭
5. 프로젝트 생성 완료 후 **선택** 버튼 클릭

---

## 2. OAuth 동의 화면 설정

### 2.1 OAuth 동의 화면으로 이동
1. 좌측 메뉴: **"API 및 서비스"** → **"OAuth 동의 화면"**
2. 또는 직접 URL: https://console.cloud.google.com/apis/credentials/consent

### 2.2 사용자 유형 선택
- **외부(External)** 선택
- **"만들기"** 클릭

> **참고**: 개인 Google 계정은 "내부" 옵션을 사용할 수 없습니다.

### 2.3 앱 정보 입력 (1/4단계)

**앱 정보**:
- **앱 이름**: `Mac Mini k3s Services`
- **사용자 지원 이메일**: 본인의 Gmail 주소 선택
- **앱 로고**: (선택사항) - 건너뛰어도 됨

**앱 도메인** (선택사항):
- **애플리케이션 홈페이지**: `https://son.duckdns.org`
- **애플리케이션 개인정보처리방침**: (선택사항)
- **애플리케이션 서비스 약관**: (선택사항)

**승인된 도메인**:
- **도메인 추가**: `duckdns.org` 입력 후 추가

**개발자 연락처 정보**:
- **이메일 주소**: 본인의 Gmail 주소 입력

**"저장 후 계속"** 클릭

### 2.4 범위 설정 (2/4단계)

**"범위 추가 또는 삭제"** 클릭

다음 범위를 선택:
- ✅ `.../auth/userinfo.email` - 이메일 주소 보기
- ✅ `.../auth/userinfo.profile` - 개인정보(공개된 것) 보기
- ✅ `openid` - Google 계정에 내 개인 정보 연결

**"업데이트"** → **"저장 후 계속"** 클릭

### 2.5 테스트 사용자 추가 (3/4단계)

> **중요**: 앱이 "테스트 중" 상태에서는 여기에 추가된 사용자만 로그인 가능합니다.

1. **"ADD USERS"** 또는 **"테스트 사용자 추가"** 클릭
2. 본인의 Gmail 주소 입력
3. 접근을 허용할 다른 Gmail 주소도 입력 (최대 100명)
4. **"저장"** 클릭
5. **"저장 후 계속"** 클릭

### 2.6 요약 확인 (4/4단계)

- 설정 내용 확인
- **"대시보드로 돌아가기"** 클릭

---

## 3. OAuth2 Client ID 생성

### 3.1 사용자 인증 정보 페이지 이동
1. 좌측 메뉴: **"API 및 서비스"** → **"사용자 인증 정보"**
2. 또는 직접 URL: https://console.cloud.google.com/apis/credentials

### 3.2 OAuth 2.0 클라이언트 ID 만들기
1. 상단 **"+ 사용자 인증 정보 만들기"** 클릭
2. **"OAuth 클라이언트 ID"** 선택

### 3.3 클라이언트 ID 정보 입력

**애플리케이션 유형**:
- **웹 애플리케이션** 선택

**이름**:
- `OAuth2 Proxy - son.duckdns.org` (또는 원하는 이름)

**승인된 자바스크립트 원본** (선택사항):
- (비워둠 - 필요 없음)

**승인된 리디렉션 URI** (중요!):

1. **"+ URI 추가"** 클릭
2. 다음 URI를 **정확히** 입력:
   ```
   https://son.duckdns.org/oauth2/callback
   ```

> ⚠️ **매우 중요**:
> - `https://` 로 시작 (http 아님!)
> - `/oauth2/callback` 정확히 입력
> - 끝에 `/` 없음
> - 오타가 있으면 OAuth2 인증이 실패합니다!

**"만들기"** 클릭

### 3.4 Client ID와 Secret 복사

생성 완료 후 팝업에 표시되는 정보:

1. **클라이언트 ID** (Client ID)
   - 예: `123456789012-abcdefghijklmnop.apps.googleusercontent.com`
   - 📋 **복사** 버튼 클릭하여 복사
   - 임시로 메모장에 저장

2. **클라이언트 보안 비밀번호** (Client Secret)
   - 예: `GOCSPX-AbCdEfGhIjKlMnOpQrStUvWxYz`
   - 📋 **복사** 버튼 클릭하여 복사
   - 임시로 메모장에 저장

> ⚠️ **주의**: Client Secret은 이 화면에서만 볼 수 있습니다!
> 복사하지 않고 닫으면 다시 생성해야 합니다.

**"확인"** 클릭하여 팝업 닫기

---

## 4. Kubernetes Secret 생성

### 4.1 Secret 생성 스크립트 실행

```bash
cd ~/Desktop/infra
./scripts/generate-auth-secrets.sh
```

### 4.2 정보 입력

스크립트가 다음 정보를 요청합니다:

1. **Google OAuth Client ID를 입력하세요**:
   - 위에서 복사한 Client ID 붙여넣기
   - 예: `123456789012-abcdefghijklmnop.apps.googleusercontent.com`

2. **Google OAuth Client Secret을 입력하세요**:
   - 위에서 복사한 Client Secret 붙여넣기
   - 예: `GOCSPX-AbCdEfGhIjKlMnOpQrStUvWxYz`

### 4.3 Secret 생성 확인

스크립트 실행 후 다음 명령어로 Secret이 생성되었는지 확인:

```bash
kubectl get secret oauth2-proxy-secrets -n infra
```

**예상 출력**:
```
NAME                    TYPE     DATA   AGE
oauth2-proxy-secrets    Opaque   3      5s
```

---

## 5. 검증 및 테스트

### 5.1 OAuth2 Proxy 배포

```bash
# OAuth2 Proxy와 관련 서비스 배포
kubectl apply -f k8s/auth/

# Pod 상태 확인 (Running이 될 때까지 대기)
kubectl get pods -n infra -l app=oauth2-proxy -w
```

**Ctrl+C**로 watch 종료

### 5.2 로컬 테스트 (선택사항)

**/etc/hosts 파일 설정** (아직 안 했다면):
```bash
sudo vi /etc/hosts
```

다음 라인 추가:
```
127.0.0.1 son.duckdns.org
127.0.0.1 admin.son.duckdns.org
127.0.0.1 pgadmin.son.duckdns.org
127.0.0.1 kafka-ui.son.duckdns.org
```

**브라우저 테스트**:
```
http://son.duckdns.org:31599
```

- Google 로그인 페이지가 표시되어야 함
- "Sign in with Google" 버튼 클릭
- Google 계정 선택
- 권한 승인
- 로그인 성공 시 서비스 페이지 표시

### 5.3 외부 접근 테스트

**전제 조건**:
- DuckDNS 설정 완료
- 공유기 포트 포워딩 완료 (80→31599, 443→31818)

**다른 네트워크에서 접속** (모바일 데이터 등):
```
http://son.duckdns.org
http://admin.son.duckdns.org
http://pgadmin.son.duckdns.org
http://kafka-ui.son.duckdns.org
```

**기대 결과**:
1. Google 로그인 페이지 표시
2. 로그인 성공
3. 서비스 접근 가능

---

## 🔧 문제 해결

### 문제 1: "redirect_uri_mismatch" 오류

**증상**:
```
Error 400: redirect_uri_mismatch
The redirect URI in the request, https://son.duckdns.org/oauth2/callback,
does not match the ones authorized for the OAuth client.
```

**원인**: Google Cloud Console의 리디렉션 URI가 잘못 설정됨

**해결 방법**:
1. Google Cloud Console → API 및 서비스 → 사용자 인증 정보
2. 생성한 OAuth 2.0 클라이언트 ID 클릭
3. **승인된 리디렉션 URI** 확인:
   - 정확히 `https://son.duckdns.org/oauth2/callback` 인지 확인
   - `https://` (s 포함!)
   - 끝에 `/` 없음
   - 오타 확인
4. 수정 후 **"저장"** 클릭

### 문제 2: "access_denied" 오류

**증상**:
```
Error: access_denied
The application is in testing mode and you are not added as a test user.
```

**원인**: OAuth 동의 화면에서 테스트 사용자로 추가되지 않음

**해결 방법**:
1. Google Cloud Console → API 및 서비스 → OAuth 동의 화면
2. **"테스트 사용자"** 섹션에서 **"ADD USERS"** 클릭
3. 로그인할 Gmail 주소 추가
4. **"저장"** 클릭

### 문제 3: OAuth2 Proxy Pod가 시작되지 않음

**증상**:
```bash
kubectl get pods -n infra
# oauth2-proxy-xxx   0/1   CrashLoopBackOff
```

**원인**: Secret이 제대로 생성되지 않았거나 잘못된 값

**해결 방법**:
```bash
# Secret 확인
kubectl get secret oauth2-proxy-secrets -n infra -o yaml

# Secret 재생성
kubectl delete secret oauth2-proxy-secrets -n infra
./scripts/generate-auth-secrets.sh

# Pod 재시작
kubectl delete pod -n infra -l app=oauth2-proxy
kubectl get pods -n infra -w
```

### 문제 4: 로그인 후 "403 Forbidden" 발생

**증상**: Google 로그인은 성공하지만 서비스 접근 시 403 에러

**원인**: 사용자가 화이트리스트에 없음

**해결 방법**:
```bash
# PostgreSQL에 화이트리스트 추가
~/Desktop/infra/scripts/init-auth-database.sh

# 또는 Admin UI에서 추가:
# http://admin.son.duckdns.org → Whitelist → Add Email
```

---

## 📊 설정 확인 체크리스트

### Google Cloud Console
- ✅ 프로젝트 생성
- ✅ OAuth 동의 화면 설정 (외부)
- ✅ 범위 설정 (email, profile, openid)
- ✅ 테스트 사용자 추가
- ✅ OAuth 클라이언트 ID 생성
- ✅ 리디렉션 URI: `https://son.duckdns.org/oauth2/callback`
- ✅ Client ID 및 Secret 복사

### Kubernetes 설정
- ✅ Secret 생성 완료 (`oauth2-proxy-secrets`)
- ✅ OAuth2 Proxy Pod Running 상태
- ✅ Auth Validator Pod Running 상태
- ✅ Admin UI Pod Running 상태

### PostgreSQL 설정
- ✅ 스키마 초기화 완료
- ✅ 관리자 이메일 화이트리스트에 추가
- ✅ 테이블 생성 확인 (allowed_emails, users, login_history)

---

## 🎯 다음 단계

1. **관리자 UI 접속**:
   ```
   http://admin.son.duckdns.org
   ```
   - 화이트리스트 관리
   - 사용자 목록 확인
   - 로그인 이력 조회

2. **서비스 접근**:
   ```
   http://pgadmin.son.duckdns.org   # PostgreSQL 관리
   http://kafka-ui.son.duckdns.org  # Kafka UI
   ```

3. **추가 사용자 등록**:
   - Admin UI에서 화이트리스트에 이메일 추가
   - 해당 사용자는 Google 계정으로 로그인 가능

---

## 📚 참고 자료

- **Google OAuth2 공식 문서**: https://developers.google.com/identity/protocols/oauth2
- **OAuth2 Proxy 문서**: https://oauth2-proxy.github.io/oauth2-proxy/
- **DuckDNS 가이드**: claudedocs/router-port-forwarding-guide.md
- **전체 설정 가이드**: claudedocs/SETUP_GUIDE.md

---

## 🔐 보안 참고사항

1. **Client Secret 보호**:
   - GitHub 등 공개 저장소에 업로드 금지
   - Kubernetes Secret으로만 관리
   - 정기적으로 변경 권장

2. **테스트 사용자 관리**:
   - 필요한 사용자만 추가
   - 정기적으로 불필요한 사용자 제거

3. **프로덕션 배포 시**:
   - OAuth 동의 화면을 "게시" 상태로 변경 고려
   - 하지만 개인/소규모 사용 시에는 "테스트" 상태 유지 권장

---

**설정 완료!** 🎉

이제 Google 계정으로 안전하게 서비스에 접근할 수 있습니다.
