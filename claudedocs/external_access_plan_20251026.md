# 외부 접근 가능한 도메인 연결 계획

**날짜**: 2025-10-26
**대상**: Mac Mini M4 with k3d cluster
**목표**: 공유기 내부 네트워크에서 외부 인터넷으로 도메인을 통한 접근 가능하게 구성

---

## 📋 요구사항 요약

- **현재 환경**: 공유기 뒤의 Mac Mini M4 (Private IP)
- **클러스터**: k3d (Kubernetes in Docker) with k3s
- **목표**: 외부에서 도메인을 통해 k3s 서비스 접근
- **보안**: HTTPS, 인증, 방화벽 설정 필요

---

## 🎯 추천 방법: Cloudflare Tunnel (최적)

### 왜 Cloudflare Tunnel인가?

1. **무료**: Free tier에서 50개 tunnel, 무제한 대역폭
2. **포트 포워딩 불필요**: Outbound 연결만 사용 (보안 향상)
3. **자동 SSL**: Cloudflare가 자동으로 HTTPS 인증서 제공
4. **DDoS 보호**: Cloudflare 네트워크 레벨 보호
5. **실제 IP 숨김**: 공유기의 공인 IP 노출 없음
6. **간단한 설정**: CLI로 빠른 구성 가능

### Cloudflare Tunnel 아키텍처

```
[Internet Users]
      ↓
[Cloudflare Network] ← HTTPS + DDoS Protection
      ↓
[Cloudflare Tunnel] ← Outbound connection (No port forwarding)
      ↓
[Mac Mini k3d cluster]
      ↓
[k3s Ingress (NGINX)]
      ↓
[Services: test-service, pgadmin, kafka-ui]
```

---

## 📝 단계별 구현 계획

### Phase 1: 도메인 준비 (15분)

**1.1 도메인 등록 또는 준비**
- 기존 도메인 있으면 사용
- 없으면 등록: Namecheap, GoDaddy, Cloudflare Registrar 등
- 예산: 무료 (기존) ~ 15,000원/년 (신규 .com)

**1.2 Cloudflare 계정 생성 및 도메인 추가**
```bash
# 1. https://dash.cloudflare.com 에서 계정 생성
# 2. "Add a Site" 클릭하여 도메인 추가
# 3. Cloudflare nameserver로 변경 (도메인 등록 업체에서)
#    - 예: amelie.ns.cloudflare.com, beau.ns.cloudflare.com
# 4. DNS 전파 대기 (5분 ~ 24시간, 보통 10분 이내)
```

### Phase 2: Cloudflare Tunnel 설치 (10분)

**2.1 cloudflared 설치 (Mac)**
```bash
# Homebrew로 설치
brew install cloudflare/cloudflare/cloudflared

# 버전 확인
cloudflared --version
```

**2.2 Cloudflare 로그인**
```bash
# 브라우저에서 인증 진행
cloudflared tunnel login
```

**2.3 Tunnel 생성**
```bash
# Tunnel 생성 (예: macmini-k3s)
cloudflared tunnel create macmini-k3s

# Tunnel ID 확인 (나중에 필요)
cloudflared tunnel list
```

### Phase 3: k3d 외부 접근 설정 (20분)

**3.1 k3d 클러스터 port mapping 확인**
```bash
# 현재 k3d 클러스터 확인
k3d cluster list

# LoadBalancer port mapping 확인
kubectl get svc -n kube-system ingress-nginx-controller
```

**3.2 LoadBalancer 외부 포트 확인**
현재 설정:
```yaml
ingress-nginx-controller   LoadBalancer   10.43.170.122   172.18.0.3    80:31599/TCP,443:31818/TCP
```
- HTTP: Port 31599 (호스트)
- HTTPS: Port 31818 (호스트)

**3.3 Mac Mini에서 접근 테스트**
```bash
# HTTP 테스트
curl -H "Host: test.local" http://localhost:31599

# HTTPS 테스트 (현재 미설정)
curl -k -H "Host: test.local" https://localhost:31818
```

### Phase 4: Cloudflare Tunnel 설정 (15분)

**4.1 Tunnel 설정 파일 생성**
```bash
# 설정 디렉토리 생성
mkdir -p ~/.cloudflared

# 설정 파일 생성
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: <TUNNEL_ID>
credentials-file: /Users/sonmingi/.cloudflared/<TUNNEL_ID>.json

ingress:
  # Test service
  - hostname: test.yourdomain.com
    service: http://localhost:31599
    originRequest:
      httpHostHeader: test.local

  # pgAdmin
  - hostname: pgadmin.yourdomain.com
    service: http://localhost:31599
    originRequest:
      httpHostHeader: pgadmin.local

  # Kafka UI
  - hostname: kafka-ui.yourdomain.com
    service: http://localhost:31599
    originRequest:
      httpHostHeader: kafka-ui.local

  # Catch-all rule (필수)
  - service: http_status:404
EOF
```

**4.2 DNS CNAME 레코드 생성**
```bash
# CLI로 자동 생성
cloudflared tunnel route dns macmini-k3s test.yourdomain.com
cloudflared tunnel route dns macmini-k3s pgadmin.yourdomain.com
cloudflared tunnel route dns macmini-k3s kafka-ui.yourdomain.com

# 또는 Cloudflare Dashboard에서 수동 생성:
# Type: CNAME
# Name: test (또는 pgadmin, kafka-ui)
# Target: <TUNNEL_ID>.cfargotunnel.com
# Proxy: Enabled (주황색 구름)
```

### Phase 5: Tunnel 실행 및 테스트 (10분)

**5.1 Tunnel 실행 (테스트)**
```bash
# Foreground 실행 (테스트용)
cloudflared tunnel run macmini-k3s

# 로그 확인:
# - Connection registered
# - Serving https://test.yourdomain.com
```

**5.2 외부 접근 테스트**
```bash
# 다른 디바이스나 모바일에서
curl https://test.yourdomain.com
curl https://pgadmin.yourdomain.com
curl https://kafka-ui.yourdomain.com
```

**5.3 Background 실행 설정**
```bash
# macOS launchd로 자동 시작 설정
cloudflared service install

# 서비스 시작
sudo launchctl start com.cloudflare.cloudflared

# 서비스 상태 확인
sudo launchctl list | grep cloudflare
```

### Phase 6: Ingress 설정 업데이트 (10분)

**6.1 실제 도메인으로 Ingress 업데이트**

기존 `test.local`, `pgadmin.local`, `kafka-ui.local`을 실제 도메인으로 변경:

```bash
# test-service Ingress 수정
kubectl edit ingress test-service-ingress -n test

# pgadmin Ingress 수정
kubectl edit ingress pgadmin-ingress -n infra

# kafka-ui Ingress 수정
kubectl edit ingress kafka-ui-ingress -n infra
```

변경 예시:
```yaml
spec:
  rules:
  - host: test.yourdomain.com  # test.local → 실제 도메인
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-service
            port:
              number: 80
```

---

## 🔐 보안 설정

### 1. Cloudflare Access (무료 - 추천)

**Zero Trust 인증 추가**:
```bash
# Cloudflare Dashboard → Zero Trust → Access → Applications
# 1. Add an Application
# 2. Select "Self-hosted"
# 3. Application domain: pgadmin.yourdomain.com, kafka-ui.yourdomain.com
# 4. Identity providers: Google, GitHub, One-time PIN
# 5. Access policies: 이메일 주소 또는 그룹 지정
```

무료 플랜: 최대 50 users, 무제한 applications

### 2. k3s Network Policies

```yaml
# PostgreSQL - 내부 접근만 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-policy
  namespace: infra
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: postgresql
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: infra
    - namespaceSelector:
        matchLabels:
          name: test
```

### 3. 방화벽 규칙

```bash
# Mac 방화벽 활성화
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Incoming connections 제한
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off
```

---

## 💰 비용 분석

| 항목 | 방법 | 비용 (연간) | 장점 | 단점 |
|------|------|------------|------|------|
| **Cloudflare Tunnel** | Zero Trust Tunnel | **무료** | 포트포워딩 불필요, 자동 SSL, DDoS 보호 | 없음 |
| 도메인 | .com 등록 | 15,000원 | 전문적, SEO | 비용 발생 |
| 도메인 | .xyz, .site | 3,000-5,000원 | 저렴 | 덜 전문적 |
| DDNS (대안) | DuckDNS, No-IP | **무료** | 무료 subdomain | 불안정, SSL 어려움, 포트포워딩 필요 |
| Static IP (대안) | ISP 신청 | 20,000-50,000원/월 | 안정적 | 매우 비싸고 불필요 |

**추천 총 비용**: 3,000원 ~ 15,000원/년 (도메인만)

---

## 🔄 대안 방법 비교

### Option A: Cloudflare Tunnel (추천 ⭐)
**장점**:
- ✅ 무료
- ✅ 포트 포워딩 불필요 (보안 최상)
- ✅ 자동 HTTPS
- ✅ DDoS 보호
- ✅ 실제 IP 숨김
- ✅ 설정 간단

**단점**:
- ⚠️ Cloudflare 의존성

### Option B: DDNS + Port Forwarding
**장점**:
- ✅ 완전한 제어

**단점**:
- ❌ 공유기 포트 포워딩 필요 (보안 위험)
- ❌ 실제 공인 IP 노출
- ❌ Let's Encrypt 수동 설정
- ❌ DDoS 취약
- ❌ 동적 IP 주기적 업데이트 필요

### Option C: VPN (Tailscale, Wireguard)
**장점**:
- ✅ 매우 안전

**단점**:
- ❌ 공개 웹 서비스 불가능
- ❌ 모든 사용자가 VPN 클라이언트 필요
- ❌ 복잡한 설정

---

## 📅 구현 타임라인

| Phase | 작업 | 예상 시간 | 의존성 |
|-------|------|----------|--------|
| 1 | 도메인 준비 | 15분 | 없음 |
| 2 | Cloudflare Tunnel 설치 | 10분 | Phase 1 |
| 3 | k3d 외부 접근 설정 | 20분 | 없음 (병렬 가능) |
| 4 | Tunnel 설정 | 15분 | Phase 2, 3 |
| 5 | 테스트 및 실행 | 10분 | Phase 4 |
| 6 | Ingress 업데이트 | 10분 | Phase 5 |
| **총계** | **1시간 20분** | | |

---

## ✅ 검증 체크리스트

### 기본 기능
- [ ] 외부에서 `https://test.yourdomain.com` 접근 가능
- [ ] 외부에서 `https://pgadmin.yourdomain.com` 접근 가능
- [ ] 외부에서 `https://kafka-ui.yourdomain.com` 접근 가능
- [ ] HTTPS 자동 인증서 작동
- [ ] 모바일/다른 네트워크에서 접근 확인

### 보안
- [ ] Cloudflare Access 인증 작동 (pgadmin, kafka-ui)
- [ ] 실제 공인 IP 숨김 확인
- [ ] k3s Network Policy 적용
- [ ] Mac 방화벽 활성화

### 안정성
- [ ] cloudflared 서비스 자동 시작 설정
- [ ] 재부팅 후 자동 복구 확인
- [ ] Tunnel 로그 모니터링 설정

---

## 🚀 다음 단계 (Phase 7+)

### 모니터링 (선택)
```bash
# Cloudflare Analytics 사용 (무료)
# Dashboard → Analytics → Traffic
```

### 백업 도메인 (선택)
```bash
# 여러 도메인으로 같은 서비스 접근
cloudflared tunnel route dns macmini-k3s backup.yourdomain.com
```

### 로드 밸런싱 (선택)
```yaml
# config.yml에 여러 origin 추가
ingress:
  - hostname: api.yourdomain.com
    service: http://localhost:31599
    originRequest:
      httpHostHeader: api.local
      loadBalancer:
        pool:
          - http://localhost:31599
          - http://backup-server:8080
```

---

## 📚 참고 자료

### Cloudflare Tunnel
- [Cloudflare Tunnel 공식 문서](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Cloudflare Zero Trust](https://www.cloudflare.com/products/zero-trust/)

### k3s/k3d
- [K3s Networking Services](https://docs.k3s.io/networking/networking-services)
- [k3d Ingress Guide](https://k3d.io/v5.7.5/usage/exposing_services/)

### 보안
- [Cloudflare Access Setup](https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

## 🎯 최종 권장사항

**Cloudflare Tunnel 방식을 강력히 추천합니다:**

1. **비용**: 무료 (도메인 비용만)
2. **보안**: 포트 포워딩 불필요, DDoS 보호, 자동 HTTPS
3. **간편성**: 1시간 20분이면 완료
4. **확장성**: 추가 서비스 쉽게 추가 가능
5. **안정성**: Cloudflare 인프라 활용

**즉시 시작 가능한 명령어 요약**:
```bash
# 1. cloudflared 설치
brew install cloudflare/cloudflare/cloudflared

# 2. 로그인
cloudflared tunnel login

# 3. Tunnel 생성
cloudflared tunnel create macmini-k3s

# 4. DNS 라우팅
cloudflared tunnel route dns macmini-k3s test.yourdomain.com

# 5. Tunnel 실행
cloudflared tunnel run macmini-k3s
```

**다음 작업**: 도메인 준비되면 바로 구현 가능합니다!
