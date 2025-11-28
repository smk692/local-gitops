#!/bin/bash
# Google OAuth2 + PostgreSQL 계정 관리 시스템 배포 스크립트

set -e

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "   Google OAuth2 인증 시스템 배포"
echo "========================================="
echo ""

# 1. 전제 조건 확인
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: 전제 조건 확인${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# k3s 클러스터 확인
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ k3s 클러스터에 연결할 수 없습니다${NC}"
    echo "k3s가 실행 중인지 확인하세요: sudo systemctl status k3s"
    exit 1
fi
echo -e "${GREEN}✅ k3s 클러스터 연결 확인${NC}"

# infra namespace 확인
if ! kubectl get namespace infra &> /dev/null; then
    echo -e "${YELLOW}⚠️  infra namespace가 없습니다. 생성합니다...${NC}"
    kubectl create namespace infra
fi
echo -e "${GREEN}✅ infra namespace 확인${NC}"

# PostgreSQL 확인
POSTGRES_POD=$(kubectl get pods -n infra -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$POSTGRES_POD" ]; then
    echo -e "${RED}❌ PostgreSQL Pod를 찾을 수 없습니다${NC}"
    echo "PostgreSQL을 먼저 배포하세요"
    exit 1
fi
echo -e "${GREEN}✅ PostgreSQL Pod 확인: $POSTGRES_POD${NC}"

echo ""

# 2. PostgreSQL 스키마 초기화
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: PostgreSQL 스키마 초기화${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 테이블이 이미 존재하는지 확인
TABLE_EXISTS=$(kubectl exec -n infra "$POSTGRES_POD" -- psql -U postgres -d postgres -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'allowed_emails');" 2>/dev/null || echo "f")

if [ "$TABLE_EXISTS" = "t" ]; then
    echo -e "${YELLOW}⚠️  데이터베이스 테이블이 이미 존재합니다${NC}"
    read -p "스키마를 다시 초기화하시겠습니까? (기존 데이터가 삭제될 수 있습니다) [y/N]: " REINIT
    if [[ "$REINIT" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}스키마를 재초기화합니다...${NC}"
        ./scripts/init-auth-database.sh
    else
        echo -e "${GREEN}✅ 기존 데이터베이스 사용${NC}"
    fi
else
    echo -e "${YELLOW}데이터베이스 스키마를 초기화합니다...${NC}"
    ./scripts/init-auth-database.sh
fi

echo ""

# 3. Secrets 확인/생성
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Kubernetes Secrets 확인/생성${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# oauth2-proxy-secrets 확인
if kubectl get secret oauth2-proxy-secrets -n infra &> /dev/null; then
    echo -e "${GREEN}✅ oauth2-proxy-secrets 이미 존재${NC}"
    read -p "Secret을 다시 생성하시겠습니까? [y/N]: " RECREATE
    if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
        kubectl delete secret oauth2-proxy-secrets -n infra
        echo -e "${YELLOW}Secret을 재생성합니다...${NC}"
        ./scripts/generate-auth-secrets.sh
    fi
else
    echo -e "${YELLOW}Secret을 생성합니다...${NC}"
    ./scripts/generate-auth-secrets.sh
fi

# jwt-secrets 확인
if ! kubectl get secret jwt-secrets -n infra &> /dev/null; then
    echo -e "${RED}❌ jwt-secrets이 없습니다${NC}"
    echo "generate-auth-secrets.sh 스크립트를 다시 실행하세요"
    exit 1
fi
echo -e "${GREEN}✅ jwt-secrets 확인${NC}"

echo ""

# 4. 인증 리소스 배포
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: 인증 리소스 배포${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${GREEN}OAuth2 Proxy 배포 중...${NC}"
kubectl apply -f k8s/auth/oauth2-proxy.yaml

echo -e "${GREEN}Auth Validator 배포 중...${NC}"
kubectl apply -f k8s/auth/auth-validator.yaml

echo -e "${GREEN}Admin UI 배포 중...${NC}"
kubectl apply -f k8s/auth/admin-ui.yaml

echo -e "${GREEN}JWT Service 배포 중...${NC}"
kubectl apply -f k8s/auth/jwt-service.yaml

echo ""

# 5. Ingress 업데이트
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Ingress 리소스 업데이트${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${GREEN}pgAdmin Ingress 업데이트 중...${NC}"
kubectl apply -f k8s/postgres/pgadmin.yaml

echo -e "${GREEN}Kafka UI Ingress 업데이트 중...${NC}"
kubectl apply -f k8s/kafka/kafka-ui.yaml

echo ""

# 6. Pod 상태 확인
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Pod 상태 확인 (최대 2분 대기)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TIMEOUT=120
ELAPSED=0
ALL_READY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    OAUTH_STATUS=$(kubectl get pods -n infra -l app=oauth2-proxy -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    VALIDATOR_STATUS=$(kubectl get pods -n infra -l app=auth-validator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    ADMIN_STATUS=$(kubectl get pods -n infra -l app=admin-ui -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    JWT_STATUS=$(kubectl get pods -n infra -l app=jwt-service -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")

    echo -e "OAuth2 Proxy: $OAUTH_STATUS | Auth Validator: $VALIDATOR_STATUS | Admin UI: $ADMIN_STATUS | JWT: $JWT_STATUS"

    if [ "$OAUTH_STATUS" = "Running" ] && [ "$VALIDATOR_STATUS" = "Running" ] && [ "$ADMIN_STATUS" = "Running" ] && [ "$JWT_STATUS" = "Running" ]; then
        ALL_READY=true
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""

if [ "$ALL_READY" = true ]; then
    echo -e "${GREEN}✅ 모든 Pod가 Running 상태입니다${NC}"
else
    echo -e "${YELLOW}⚠️  일부 Pod가 아직 준비되지 않았습니다${NC}"
    echo "Pod 상태를 확인하세요: kubectl get pods -n infra"
fi

echo ""

# 7. 서비스 엔드포인트 확인
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 7: 서비스 엔드포인트 확인${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "배포된 서비스 확인:"
kubectl get svc -n infra -l 'app in (oauth2-proxy,auth-validator,admin-ui,jwt-service)'

echo ""
echo "배포된 Ingress 확인:"
kubectl get ingress -n infra

echo ""

# 8. 헬스체크
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 8: 서비스 헬스체크${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# OAuth2 Proxy 헬스체크
OAUTH_HEALTH=$(kubectl exec -n infra -l app=oauth2-proxy -- wget -q -O - http://localhost:4180/ping 2>/dev/null || echo "FAILED")
if [ "$OAUTH_HEALTH" = "OK" ]; then
    echo -e "${GREEN}✅ OAuth2 Proxy 헬스체크 성공${NC}"
else
    echo -e "${RED}❌ OAuth2 Proxy 헬스체크 실패${NC}"
fi

# Auth Validator 헬스체크
VALIDATOR_HEALTH=$(kubectl exec -n infra -l app=auth-validator -- wget -q -O - http://localhost:8080/health 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
if [ "$VALIDATOR_HEALTH" = '"status":"healthy"' ]; then
    echo -e "${GREEN}✅ Auth Validator 헬스체크 성공${NC}"
else
    echo -e "${RED}❌ Auth Validator 헬스체크 실패${NC}"
fi

# Admin UI 헬스체크
ADMIN_HEALTH=$(kubectl exec -n infra -l app=admin-ui -- wget -q -O - http://localhost:8080/health 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
if [ "$ADMIN_HEALTH" = '"status":"healthy"' ]; then
    echo -e "${GREEN}✅ Admin UI 헬스체크 성공${NC}"
else
    echo -e "${RED}❌ Admin UI 헬스체크 실패${NC}"
fi

echo ""

# 9. 배포 완료 안내
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}배포 완료!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${GREEN}🎉 Google OAuth2 인증 시스템이 성공적으로 배포되었습니다!${NC}"
echo ""

echo "📱 접근 URL (로컬 테스트 - /etc/hosts 설정 필요):"
echo "  - OAuth2 로그인: http://son.duckdns.org:31599"
echo "  - 관리자 UI: http://admin.son.duckdns.org:31599"
echo "  - pgAdmin: http://pgadmin.son.duckdns.org:31599"
echo "  - Kafka UI: http://kafka-ui.son.duckdns.org:31599"
echo ""

echo "🌐 외부 접근 URL (포트 포워딩 설정 후):"
echo "  - OAuth2 로그인: http://son.duckdns.org"
echo "  - 관리자 UI: http://admin.son.duckdns.org"
echo "  - pgAdmin: http://pgadmin.son.duckdns.org"
echo "  - Kafka UI: http://kafka-ui.son.duckdns.org"
echo ""

echo "📚 다음 단계:"
echo "  1. Google Cloud Console에서 OAuth 2.0 클라이언트 ID 생성"
echo "     → 가이드: claudedocs/google-oauth-setup-guide.md"
echo ""
echo "  2. 외부 접근 설정 (DuckDNS + 포트 포워딩)"
echo "     → 가이드: claudedocs/SETUP_GUIDE.md"
echo ""
echo "  3. 외부 접근 테스트"
echo "     → 스크립트: ./scripts/test-external-access.sh"
echo ""

echo "🔍 문제 발생 시:"
echo "  - Pod 로그 확인: kubectl logs -n infra -l app=<service-name>"
echo "  - Pod 상태 확인: kubectl get pods -n infra"
echo "  - Ingress 확인: kubectl describe ingress -n infra"
echo ""
