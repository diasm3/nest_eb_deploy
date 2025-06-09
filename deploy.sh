#!/bin/bash

# Elastic Beanstalk 자동 배포 스크립트
# 사용법: ./deploy.sh [environment] [version-message]

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설정값 (자동 감지 또는 사용자 설정)
DEFAULT_ENV=""
DEFAULT_APP=""
DEFAULT_REGION=""

# 함수: 색상 출력
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 함수: EB 설정 자동 감지
detect_eb_config() {
    local config_file=".elasticbeanstalk/config.yml"
    
    if [ ! -f "$config_file" ]; then
        print_error "EB 설정 파일을 찾을 수 없습니다: $config_file"
        print_info "eb init 명령어로 초기화해주세요."
        exit 1
    fi
    
    # YAML 파일에서 설정 추출
    DEFAULT_APP=$(grep "application_name:" "$config_file" | sed 's/.*application_name: *//' | tr -d '"' | tr -d "'")
    DEFAULT_ENV=$(grep "environment:" "$config_file" | head -1 | sed 's/.*environment: *//' | tr -d '"' | tr -d "'")
    DEFAULT_REGION=$(grep "default_region:" "$config_file" | sed 's/.*default_region: *//' | tr -d '"' | tr -d "'")
    
    if [ -z "$DEFAULT_APP" ] || [ -z "$DEFAULT_ENV" ] || [ -z "$DEFAULT_REGION" ]; then
        print_warning "EB 설정을 완전히 감지하지 못했습니다."
        print_info "감지된 설정:"
        print_info "  애플리케이션: ${DEFAULT_APP:-'미감지'}"
        print_info "  환경: ${DEFAULT_ENV:-'미감지'}"
        print_info "  리전: ${DEFAULT_REGION:-'미감지'}"
        echo ""
        
        # 사용자 입력으로 설정
        read -p "애플리케이션 이름을 입력하세요: " user_app
        read -p "환경 이름을 입력하세요: " user_env
        read -p "리전을 입력하세요 (예: ap-northeast-2): " user_region
        
        DEFAULT_APP=${user_app:-$DEFAULT_APP}
        DEFAULT_ENV=${user_env:-$DEFAULT_ENV}
        DEFAULT_REGION=${user_region:-$DEFAULT_REGION}
    fi
    
    print_success "EB 설정 감지 완료:"
    print_info "  애플리케이션: $DEFAULT_APP"
    print_info "  환경: $DEFAULT_ENV"
    print_info "  리전: $DEFAULT_REGION"
}

# 함수: 사용 가능한 환경 목록 표시
list_available_environments() {
    print_info "사용 가능한 환경 목록:"
    eb list 2>/dev/null || print_warning "환경 목록을 가져올 수 없습니다."
}
show_help() {
    echo "Elastic Beanstalk 자동 배포 스크립트"
    echo ""
    echo "사용법:"
    echo "  ./deploy.sh [environment] [message]"
    echo ""
    echo "옵션:"
    echo "  environment  : 배포할 환경 (기본값: Nestj-env)"
    echo "  message      : 버전 설명 메시지"
    echo ""
    echo "예시:"
    echo "  ./deploy.sh                           # 기본 환경에 배포"
    echo "  ./deploy.sh Nestj-env                 # 특정 환경에 배포"
    echo "  ./deploy.sh Nestj-env \"new feature\"  # 메시지와 함께 배포"
    echo ""
    echo "미리 정의된 배포 명령어:"
    echo "  ./deploy.sh quick                     # 빠른 배포"
    echo "  ./deploy.sh staging                   # 스테이징 배포"
    echo "  ./deploy.sh production                # 프로덕션 배포"
}

# 함수: 필수 도구 확인
check_prerequisites() {
    print_info "필수 도구 확인 중..."
    
    # EB CLI 확인
    if ! command -v eb &> /dev/null; then
        print_error "EB CLI가 설치되어 있지 않습니다."
        print_info "설치 명령어: pip install awsebcli"
        exit 1
    fi
    
    # Git 확인
    if ! command -v git &> /dev/null; then
        print_error "Git이 설치되어 있지 않습니다."
        exit 1
    fi
    
    # AWS 자격증명 확인
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS 자격증명이 설정되어 있지 않습니다."
        print_info "설정 명령어: aws configure"
        exit 1
    fi
    
    print_success "모든 필수 도구가 준비되었습니다."
}

# 함수: 프로젝트 상태 확인
check_project_status() {
    print_info "프로젝트 상태 확인 중..."
    
    # Git 저장소 확인
    if [ ! -d ".git" ]; then
        print_error "Git 저장소가 초기화되지 않았습니다."
        exit 1
    fi
    
    # EB 프로젝트 확인
    if [ ! -d ".elasticbeanstalk" ]; then
        print_error "EB 프로젝트가 초기화되지 않았습니다."
        print_info "초기화 명령어: eb init"
        exit 1
    fi
    
    # Dockerfile 확인
    if [ ! -f "Dockerfile" ]; then
        print_error "Dockerfile이 존재하지 않습니다."
        exit 1
    fi
    
    # 변경사항 확인
    if ! git diff --quiet; then
        print_warning "커밋되지 않은 변경사항이 있습니다."
        echo "변경된 파일들:"
        git status --porcelain
        echo ""
        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "배포가 취소되었습니다."
            exit 0
        fi
    fi
    
    print_success "프로젝트 상태가 정상입니다."
}

# 함수: 버전 라벨 생성
generate_version_label() {
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local commit=$(git rev-parse --short HEAD)
    echo "${branch}-${timestamp}-${commit}"
}

# 함수: 배포 전 체크
pre_deploy_check() {
    print_info "배포 전 환경 상태 확인 중..."
    
    # 환경 상태 확인
    local env_status=$(eb status $1 --verbose | grep "Status:" | awk '{print $2}')
    
    if [ "$env_status" != "Ready" ]; then
        print_warning "환경 상태가 Ready가 아닙니다. 현재 상태: $env_status"
        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "배포가 취소되었습니다."
            exit 0
        fi
    fi
    
    print_success "환경이 배포 준비 상태입니다."
}

# 함수: 실제 배포 수행
perform_deploy() {
    local environment=$1
    local message=$2
    local version_label=$(generate_version_label)
    
    print_info "배포 시작: $environment"
    print_info "버전 라벨: $version_label"
    print_info "메시지: $message"
    
    # 배포 명령어 실행
    if [ -n "$message" ]; then
        eb deploy "$environment" \
            --label "$version_label" \
            --message "$message" \
            --timeout 15
    else
        eb deploy "$environment" \
            --label "$version_label" \
            --timeout 15
    fi
    
    if [ $? -eq 0 ]; then
        print_success "배포가 성공적으로 완료되었습니다!"
    else
        print_error "배포가 실패했습니다."
        exit 1
    fi
}

# 함수: 배포 후 확인
post_deploy_check() {
    local environment=$1
    
    print_info "배포 후 상태 확인 중..."
    
    # 환경 상태 확인
    eb health "$environment"
    
    # 애플리케이션 URL 확인
    local app_url=$(eb status "$environment" | grep "CNAME:" | awk '{print $2}')
    if [ -n "$app_url" ]; then
        print_success "애플리케이션 URL: https://$app_url"
        
        # 헬스체크 수행
        print_info "헬스체크 수행 중..."
        if curl -s -o /dev/null -w "%{http_code}" "https://$app_url/health" | grep -q "200"; then
            print_success "헬스체크 통과!"
        else
            print_warning "헬스체크 실패. 수동으로 확인해주세요."
        fi
    fi
    
    print_info "로그 확인이 필요하면: eb logs $environment"
}

# 메인 스크립트 시작
main() {
    echo "=========================================="
    echo "   Elastic Beanstalk 자동 배포 스크립트"
    echo "   (범용 버전 - 모든 EB 프로젝트 지원)"
    echo "=========================================="
    echo ""
    
    # 환경변수에서 기본값 읽기
    DEFAULT_APP=${EB_APP_NAME:-$DEFAULT_APP}
    DEFAULT_ENV=${EB_ENV_NAME:-$DEFAULT_ENV}
    DEFAULT_REGION=${EB_REGION:-$DEFAULT_REGION}
    
    # EB 설정 자동 감지
    detect_eb_config
    
    # 파라미터 처리
    local environment="$DEFAULT_ENV"
    local message=""
    local custom_app="$DEFAULT_APP"
    local custom_region="$DEFAULT_REGION"
    
    # 명령줄 인자 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help|help)
                show_help
                exit 0
                ;;
            --list)
                list_available_environments
                exit 0
                ;;
            --app)
                custom_app="$2"
                shift 2
                ;;
            --region)
                custom_region="$2"
                shift 2
                ;;
            quick)
                message="Quick deployment"
                shift
                ;;
            staging)
                # 스테이징 환경 자동 감지 시도
                if eb list | grep -q "staging\|stage\|dev"; then
                    environment=$(eb list | grep -E "staging|stage|dev" | head -1 | awk '{print $2}')
                fi
                message="Staging deployment"
                shift
                ;;
            production|prod)
                # 프로덕션 환경 자동 감지 시도
                if eb list | grep -q "production\|prod\|live"; then
                    environment=$(eb list | grep -E "production|prod|live" | head -1 | awk '{print $2}')
                fi
                message="Production deployment"
                print_warning "프로덕션 배포입니다. 신중하게 진행하세요!"
                shift
                ;;
            -*)
                print_error "알 수 없는 옵션: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$environment" ] || [ "$environment" = "$DEFAULT_ENV" ]; then
                    environment="$1"
                elif [ -z "$message" ]; then
                    message="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 환경이 여전히 비어있으면 사용자에게 선택하게 함
    if [ -z "$environment" ]; then
        print_info "사용 가능한 환경 목록:"
        eb list
        echo ""
        read -p "배포할 환경을 입력하세요: " environment
        if [ -z "$environment" ]; then
            print_error "환경을 선택해야 합니다."
            exit 1
        fi
    fi
    
    # 메시지가 없으면 기본 메시지 생성
    if [ -z "$message" ]; then
        local commit_msg=$(git log -1 --pretty=%B 2>/dev/null | head -n 1)
        if [ -n "$commit_msg" ]; then
            message="Deploy: $commit_msg"
        else
            message="Deployment $(date '+%Y-%m-%d %H:%M:%S')"
        fi
    fi
    
    print_info "배포 설정:"
    print_info "  애플리케이션: $custom_app"
    print_info "  환경: $environment"  
    print_info "  리전: $custom_region"
    print_info "  메시지: $message"
    echo ""
    
    # 배포 프로세스 실행
    check_prerequisites
    check_project_status
    pre_deploy_check "$environment"
    
    # 최종 확인
    read -p "배포를 시작하시겠습니까? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "배포가 취소되었습니다."
        exit 0
    fi
    
    perform_deploy "$environment" "$message"
    post_deploy_check "$environment"
    
    echo ""
    print_success "배포 프로세스가 완료되었습니다! 🚀"
}

# 스크립트 실행
main "$@"