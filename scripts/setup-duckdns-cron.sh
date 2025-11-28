#!/bin/bash
# DuckDNS cron 작업 설정 스크립트

set -e

echo "=== DuckDNS Cron 설정 스크립트 ==="
echo ""

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# duck.sh 스크립트 존재 확인
if [ ! -f "$HOME/duckdns/duck.sh" ]; then
    echo -e "${RED}❌ Error: $HOME/duckdns/duck.sh 파일이 없습니다${NC}"
    echo "먼저 DuckDNS 스크립트를 설정하고 토큰을 입력하세요."
    exit 1
fi

# duck.sh 실행 권한 확인
if [ ! -x "$HOME/duckdns/duck.sh" ]; then
    echo -e "${YELLOW}⚠️  $HOME/duckdns/duck.sh에 실행 권한 추가 중...${NC}"
    chmod +x "$HOME/duckdns/duck.sh"
fi

# crontab에 이미 등록되어 있는지 확인
if crontab -l 2>/dev/null | grep -q "duckdns/duck.sh"; then
    echo -e "${YELLOW}⚠️  DuckDNS cron 작업이 이미 등록되어 있습니다${NC}"
    echo ""
    echo "현재 crontab 내용:"
    crontab -l | grep "duckdns/duck.sh"
    echo ""
    read -p "기존 작업을 삭제하고 다시 등록하시겠습니까? (y/N): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "종료합니다."
        exit 0
    fi
    # 기존 DuckDNS 작업 제거
    crontab -l | grep -v "duckdns/duck.sh" | crontab -
fi

# cron 작업 추가 (5분마다 실행)
echo -e "${GREEN}DuckDNS cron 작업 등록 중...${NC}"
(crontab -l 2>/dev/null; echo "*/5 * * * * $HOME/duckdns/duck.sh >/dev/null 2>&1") | crontab -

# 등록 확인
echo ""
echo -e "${GREEN}✅ DuckDNS cron 작업이 성공적으로 등록되었습니다!${NC}"
echo ""
echo "등록된 crontab:"
crontab -l | grep "duckdns/duck.sh"
echo ""
echo -e "${YELLOW}📌 중요 정보:${NC}"
echo "  - DuckDNS는 5분마다 자동으로 IP를 업데이트합니다"
echo "  - 로그 파일: $HOME/duckdns/duck.log"
echo ""

# 즉시 테스트 실행
echo -e "${GREEN}DuckDNS 스크립트 테스트 실행 중...${NC}"
"$HOME/duckdns/duck.sh"
echo ""

# 로그 확인
if [ -f "$HOME/duckdns/duck.log" ]; then
    echo -e "${GREEN}✅ DuckDNS 업데이트 성공!${NC}"
    echo ""
    echo "로그 내용:"
    tail -5 "$HOME/duckdns/duck.log"
else
    echo -e "${RED}❌ 로그 파일이 생성되지 않았습니다. duck.sh 스크립트를 확인하세요.${NC}"
fi

echo ""
echo -e "${GREEN}🎉 설정 완료!${NC}"
echo ""
echo "다음 단계:"
echo "  1. 공유기에서 포트 포워딩 설정"
echo "  2. k8s 인증 리소스 배포: kubectl apply -f k8s/auth/"
echo "  3. Ingress 업데이트 적용: kubectl apply -f k8s/test-service/ k8s/postgres/ k8s/kafka/"
