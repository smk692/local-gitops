#!/bin/bash
# OAuth2 Proxy 및 JWT Secret 생성 스크립트 (Google OAuth2)

set -e

echo "=== 인증 Secret 생성 스크립트 (Google OAuth2) ==="
echo ""

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Google OAuth App 정보 입력 받기
echo -e "${YELLOW}Google OAuth2 Client 정보를 입력하세요:${NC}"
echo "Google Cloud Console에서 OAuth 2.0 클라이언트 ID 생성 방법:"
echo "  → claudedocs/google-oauth-setup-guide.md 참조"
echo ""

read -p "Google OAuth Client ID: " GOOGLE_CLIENT_ID
read -sp "Google OAuth Client Secret: " GOOGLE_CLIENT_SECRET
echo ""
echo ""

echo -e "${YELLOW}ℹ️  참고: 사용자 화이트리스트는 PostgreSQL 데이터베이스에서 관리됩니다${NC}"
echo "  화이트리스트 관리: http://admin.son.duckdns.org"
echo ""

# Cookie Secret 생성 (32바이트 랜덤)
echo -e "${GREEN}Cookie Secret 자동 생성 중...${NC}"
COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n')

# JWT Secret 생성 (64바이트 랜덤)
echo -e "${GREEN}JWT Secret 자동 생성 중...${NC}"
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')

# OAuth2 Proxy Secret 생성
echo -e "${GREEN}OAuth2 Proxy Secret 생성 중...${NC}"
kubectl create secret generic oauth2-proxy-secrets \
  --from-literal=cookie-secret="$COOKIE_SECRET" \
  --from-literal=client-id="$GOOGLE_CLIENT_ID" \
  --from-literal=client-secret="$GOOGLE_CLIENT_SECRET" \
  -n infra \
  --dry-run=client -o yaml | kubectl apply -f -

# JWT Secret 생성
echo -e "${GREEN}JWT Secret 생성 중...${NC}"
kubectl create secret generic jwt-secrets \
  --from-literal=jwt-secret="$JWT_SECRET" \
  -n infra \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo -e "${GREEN}✅ Secret 생성 완료!${NC}"
echo ""
echo "생성된 Secret:"
echo "  - oauth2-proxy-secrets (infra namespace)"
echo "  - jwt-secrets (infra namespace)"
echo ""
echo -e "${YELLOW}⚠️  보안 주의사항:${NC}"
echo "  - 이 스크립트는 실행 후 자동으로 삭제하거나 안전하게 보관하세요"
echo "  - Secret 값들은 절대 Git에 커밋하지 마세요"
echo ""
echo "다음 단계: OAuth2 Proxy와 JWT 서비스를 배포하세요"
echo "  kubectl apply -f k8s/auth/"
