#!/bin/bash
# 외부 접근 테스트 스크립트
# DuckDNS + 포트 포워딩 설정 후 외부에서 접근 가능한지 테스트

set -e

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "   외부 접근 테스트 스크립트"
echo "========================================="
echo ""

# 도메인 설정
DOMAIN="son.duckdns.org"
SUBDOMAIN_PGADMIN="pgadmin.${DOMAIN}"
SUBDOMAIN_KAFKA="kafka-ui.${DOMAIN}"
API_DOMAIN="api.${DOMAIN}"

# 테스트 결과 카운터
PASSED=0
FAILED=0

# 테스트 함수
test_endpoint() {
    local name=$1
    local url=$2
    local expected_code=$3

    echo -n "Testing $name... "

    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")

    if [ "$response" = "$expected_code" ]; then
        echo -e "${GREEN}✅ PASS${NC} (HTTP $response)"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC} (HTTP $response, expected $expected_code)"
        ((FAILED++))
        return 1
    fi
}

# 0. 공인 IP 확인
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: 공인 IP 확인${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
echo "현재 공인 IP: $PUBLIC_IP"
echo ""

# 1. DuckDNS 도메인 해석 확인
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: DuckDNS 도메인 해석 확인${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -n "DNS 조회 중... "
RESOLVED_IP=$(nslookup $DOMAIN 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "Failed")

if [ "$RESOLVED_IP" = "Failed" ] || [ -z "$RESOLVED_IP" ]; then
    echo -e "${RED}❌ FAIL${NC}"
    echo "DuckDNS 도메인이 해석되지 않습니다."
    echo ""
    echo "확인 사항:"
    echo "  1. DuckDNS에서 도메인이 등록되었는지 확인"
    echo "  2. ~/duckdns/duck.sh 스크립트 실행 확인"
    echo "  3. 로그 확인: cat ~/duckdns/duck.log"
    exit 1
else
    echo -e "${GREEN}✅ PASS${NC}"
    echo "$DOMAIN → $RESOLVED_IP"
fi

if [ "$RESOLVED_IP" != "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}⚠️  경고: DuckDNS IP와 현재 공인 IP가 다릅니다${NC}"
    echo "  DuckDNS IP: $RESOLVED_IP"
    echo "  현재 공인 IP: $PUBLIC_IP"
    echo ""
    echo "DuckDNS를 업데이트하세요:"
    echo "  ~/duckdns/duck.sh"
    echo ""
fi

echo ""

# 2. HTTP 접근 테스트
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: HTTP 접근 테스트 (포트 80)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# OAuth2 인증이 있으면 302/401/403이 예상됨
test_endpoint "메인 도메인 (OAuth2)" "http://${DOMAIN}" "302"
test_endpoint "pgAdmin (OAuth2)" "http://${SUBDOMAIN_PGADMIN}" "302"
test_endpoint "Kafka UI (OAuth2)" "http://${SUBDOMAIN_KAFKA}" "302"

echo ""

# 3. HTTPS 접근 테스트 (설정된 경우)
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: HTTPS 접근 테스트 (포트 443)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}ℹ️  HTTPS는 아직 인증서가 없으면 실패할 수 있습니다${NC}"
test_endpoint "메인 도메인 HTTPS" "https://${DOMAIN}" "302" || true
test_endpoint "pgAdmin HTTPS" "https://${SUBDOMAIN_PGADMIN}" "302" || true
test_endpoint "Kafka UI HTTPS" "https://${SUBDOMAIN_KAFKA}" "302" || true

echo ""

# 4. API 엔드포인트 테스트
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: JWT API 엔드포인트 테스트${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# API는 인증 없이 호출하면 401 예상
test_endpoint "JWT Token Endpoint" "http://${API_DOMAIN}/auth/token" "401"
test_endpoint "JWT Verify Endpoint" "http://${API_DOMAIN}/auth/verify" "401"

echo ""

# 5. k8s 내부 상태 확인
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: k8s 리소스 상태 확인${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "OAuth2 Proxy Pod 상태:"
kubectl get pods -n infra -l app=oauth2-proxy --no-headers 2>/dev/null || echo "  ❌ OAuth2 Proxy Pod가 없습니다"
echo ""

echo "JWT Service Pod 상태:"
kubectl get pods -n infra -l app=jwt-service --no-headers 2>/dev/null || echo "  ❌ JWT Service Pod가 없습니다"
echo ""

echo "Ingress 상태:"
kubectl get ingress -A --no-headers 2>/dev/null | grep -E "(son.duckdns.org|pgadmin|kafka-ui|api)" || echo "  ❌ son.duckdns.org Ingress가 없습니다"
echo ""

# 6. 최종 결과
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}테스트 결과 요약${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "통과: ${GREEN}$PASSED${NC}"
echo -e "실패: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 모든 테스트 통과!${NC}"
    echo ""
    echo "외부에서 다음 URL로 접근하세요:"
    echo "  - 메인: http://${DOMAIN}"
    echo "  - pgAdmin: http://${SUBDOMAIN_PGADMIN}"
    echo "  - Kafka UI: http://${SUBDOMAIN_KAFKA}"
    echo "  - API: http://${API_DOMAIN}/auth/token"
    echo ""
    echo "OAuth2 로그인 페이지가 나타나면 성공입니다!"
else
    echo -e "${YELLOW}⚠️  일부 테스트 실패${NC}"
    echo ""
    echo "문제 해결 가이드:"
    echo ""
    echo "1. 포트 포워딩 확인:"
    echo "   - 공유기 설정에서 80 → 192.168.45.135:31599 확인"
    echo "   - 공유기 설정에서 443 → 192.168.45.135:31818 확인"
    echo ""
    echo "2. DuckDNS 업데이트 확인:"
    echo "   ~/duckdns/duck.sh"
    echo "   cat ~/duckdns/duck.log"
    echo ""
    echo "3. k8s Pod 상태 확인:"
    echo "   kubectl get pods -n infra"
    echo "   kubectl logs -n infra -l app=oauth2-proxy"
    echo ""
    echo "4. Ingress 상태 확인:"
    echo "   kubectl get ingress -A"
    echo "   kubectl describe ingress -n infra oauth2-proxy-ingress"
fi

echo ""
echo "자세한 가이드: claudedocs/router-port-forwarding-guide.md"
