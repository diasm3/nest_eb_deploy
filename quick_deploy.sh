#!/bin/bash

# 빠른 배포 스크립트 (현재 설정용)
# 사용법: ./quick-deploy.sh [message]

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 현재 프로젝트 설정
APP_NAME="nestj"
ENV_NAME="Nestj-env"
REGION="ap-northeast-2"

echo -e "${BLUE}🚀 NestJS 빠른 배포 시작${NC}"
echo "=================================="

# 메시지 설정
MESSAGE=${1:-"Quick deployment $(date '+%Y-%m-%d %H:%M:%S')"}

# 현재 Git 상태 확인
echo "📋 Git 상태 확인..."
git status --porcelain

# 변경사항이 있으면 커밋 제안
if ! git diff --quiet; then
    echo -e "${YELLOW}⚠️  커밋되지 않은 변경사항이 있습니다.${NC}"
    read -p "모든 변경사항을 커밋하고 배포하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "Auto commit before deployment: $MESSAGE"
    fi
fi

# 배포 실행
echo "🔄 배포 시작..."
echo "환경: $ENV_NAME"
echo "메시지: $MESSAGE"
echo ""

eb deploy $ENV_NAME --message "$MESSAGE" --timeout 15

# 결과 확인
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ 배포 완료!${NC}"
    echo "🌐 환경 상태 확인:"
    eb health $ENV_NAME
    echo ""
    echo "📱 유용한 명령어들:"
    echo "  eb open $ENV_NAME      # 브라우저에서 열기"
    echo "  eb logs $ENV_NAME      # 로그 확인"
    echo "  eb status $ENV_NAME    # 상태 확인"
else
    echo "❌ 배포 실패"
    echo "🔍 로그 확인: eb logs $ENV_NAME"
    exit 1
fi