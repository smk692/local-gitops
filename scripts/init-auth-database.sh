#!/bin/bash
# PostgreSQL 인증 데이터베이스 초기화 스크립트

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== PostgreSQL 인증 데이터베이스 초기화 ==="
echo ""

# PostgreSQL Pod 이름 가져오기
POSTGRES_POD=$(kubectl get pods -n infra -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POSTGRES_POD" ]; then
    echo -e "${RED}❌ PostgreSQL Pod를 찾을 수 없습니다${NC}"
    echo "PostgreSQL이 배포되어 있는지 확인하세요: kubectl get pods -n infra"
    exit 1
fi

echo -e "${GREEN}✅ PostgreSQL Pod 발견: $POSTGRES_POD${NC}"
echo ""

# 사용자 이메일 입력
echo -e "${YELLOW}초기 관리자 이메일을 입력하세요 (Google 계정):${NC}"
read -p "Email: " ADMIN_EMAIL

if [ -z "$ADMIN_EMAIL" ]; then
    echo -e "${RED}❌ 이메일이 입력되지 않았습니다${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}스키마 생성 중...${NC}"

# SQL 파일을 ConfigMap으로 생성
kubectl create configmap auth-schema-sql \
    --from-file=/Users/sonmingi/Desktop/infra/k8s/postgres/init-schema.sql \
    -n infra \
    --dry-run=client -o yaml | kubectl apply -f -

# SQL 실행
kubectl exec -n infra "$POSTGRES_POD" -- psql -U postgres -d postgres -c "
-- 스키마 생성
$(cat /Users/sonmingi/Desktop/infra/k8s/postgres/init-schema.sql | sed "s/admin@gmail.com/$ADMIN_EMAIL/g")
"

echo ""
echo -e "${GREEN}✅ 데이터베이스 초기화 완료!${NC}"
echo ""
echo "생성된 테이블:"
kubectl exec -n infra "$POSTGRES_POD" -- psql -U postgres -d postgres -c "\dt"

echo ""
echo "화이트리스트 확인:"
kubectl exec -n infra "$POSTGRES_POD" -- psql -U postgres -d postgres -c "SELECT * FROM allowed_emails;"

echo ""
echo -e "${YELLOW}📌 다음 단계:${NC}"
echo "  1. Google OAuth App 생성"
echo "  2. 인증 서비스 배포"
echo "  3. 관리자 UI 배포"
