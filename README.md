Elastic Beanstalk 완전 신규 설정 매뉴얼
_새로운 AWS 계정에서 NestJS Docker 프로젝트를 Elastic Beanstalk으로 배포하는 완벽 가이드_

---

## 🎯 설정 완료 후 결과

- ✅ NestJS + Docker 애플리케이션
- ✅ Elastic Beanstalk 자동 배포
- ✅ GitHub Actions CI/CD
- ✅ HTTPS 지원 (선택사항)
- ✅ 도메인 연결 (선택사항)

---

## 📋 사전 준비사항

### 필요한 정보

- [ ] **AWS 계정** (관리자 권한)
- [ ] **GitHub 계정** 및 저장소
- [ ] **도메인** (선택사항)
- [ ] **개발 환경** (Node.js, Docker, Git)

### 소프트웨어 설치

```bash
# 1. Node.js 설치 확인
node --version  # v18 이상

# 2. Docker 설치 확인
docker --version

# 3. Git 설치 확인
git --version

# 4. AWS CLI 설치
# macOS: brew install awscli
# Windows: https://aws.amazon.com/cli/
aws --version

# 5. EB CLI 설치
pip install awsebcli
eb --version
```

---

## 🔧 1단계: AWS 계정 설정

### 1.1 IAM 사용자 생성

**AWS Console → IAM → 사용자**

```yaml
사용자 이름: eb-deploy-user
액세스 유형: ✅ 액세스 키 - 프로그래매틱 액세스

권한 정책:
  - AWSElasticBeanstalkFullAccess
  - IAMReadOnlyAccess
  - AmazonS3FullAccess
  - AmazonEC2FullAccess
  - AWSCertificateManagerFullAccess (HTTPS용)
```

### 1.2 AWS 자격증명 설정

```bash
# AWS CLI 설정
aws configure

# 입력할 정보:
AWS Access Key ID: AKIA..................
AWS Secret Access Key: ......................
Default region name: ap-northeast-2
Default output format: json

# 설정 확인
aws sts get-caller-identity
```

---

## 📦 2단계: NestJS 프로젝트 설정

### 2.1 프로젝트 생성

```bash
# 새 NestJS 프로젝트 생성
npx @nestjs/cli new my-app
cd my-app

# 또는 기존 프로젝트 클론
git clone https://github.com/username/my-nestjs-app
cd my-nestjs-app
```

### 2.2 프로젝트 구조 설정

**디렉토리 구조:**

```
my-app/
├── .github/workflows/          # GitHub Actions
├── .ebextensions/             # EB 설정
├── src/
├── Dockerfile
├── .dockerignore
├── package.json
└── README.md
```

### 2.3 핵심 파일 생성

**Dockerfile:**

```dockerfile
# Multi-stage build 사용
FROM node:18-alpine AS builder

WORKDIR /app

# 패키지 파일들만 먼저 복사 (캐시 효율성)
COPY package.json yarn.lock ./

# 빌드 의존성만 설치
RUN yarn install --frozen-lockfile --production=false

# 소스 코드 복사
COPY . .

# 애플리케이션 빌드
RUN yarn build

# Production 의존성만 설치
RUN yarn install --frozen-lockfile --production=true && yarn cache clean

# Production 단계
FROM node:18-alpine AS production

# 보안을 위한 non-root 유저 생성
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nestjs -u 1001

WORKDIR /app

# 빌드된 애플리케이션과 production 의존성만 복사
COPY --from=builder --chown=nestjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nestjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nestjs:nodejs /app/package.json ./

# non-root 유저로 전환
USER nestjs

# 환경 변수 설정
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=512"
ENV PORT=8080

# 포트 노출
EXPOSE 8080

# 헬스체크 추가
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

# 애플리케이션 시작
CMD ["node", "dist/main"]
```

**.dockerignore:**

```dockerignore
node_modules
npm-debug.log
yarn-error.log
.git
.gitignore
README.md
.env
.nyc_output
coverage
.cache
.vscode
.idea
dist
*.log
.DS_Store
Thumbs.db
.ebextensions
.elasticbeanstalk
.github
```

**src/main.ts (중요!):**

```typescript
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // CORS 설정 (필요시)
  app.enableCors();

  // 포트 설정 (EB에서 환경변수로 제공)
  const port = process.env.PORT || 8080;

  // 0.0.0.0으로 바인딩 (중요!)
  await app.listen(port, '0.0.0.0');

  console.log(`🚀 Application is running on: http://0.0.0.0:${port}`);
}
bootstrap();
```

**src/app.controller.ts (헬스체크):**

```typescript
import { Controller, Get } from '@nestjs/common';

@Controller()
export class AppController {
  @Get()
  getRoot(): string {
    return 'NestJS App is running!';
  }

  @Get('health')
  healthCheck() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: process.env.NODE_ENV || 'development',
    };
  }
}
```

---

## ⚙️ 3단계: Elastic Beanstalk 설정

### 3.1 .ebextensions 폴더 생성

```bash
mkdir .ebextensions
```

**.ebextensions/01-environment.config:**

```yaml
option_settings:
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.small
  aws:elasticbeanstalk:environment:
    EnvironmentType: SingleInstance
  aws:elasticbeanstalk:application:environment:
    NODE_ENV: production
    PORT: 8080
```

**.ebextensions/02-health.config:**

```yaml
option_settings:
  aws:elasticbeanstalk:environment:process:default:
    Port: 8080
    Protocol: HTTP
    HealthCheckPath: /health
    HealthCheckIntervalSeconds: 15
    HealthyThresholdCount: 3
    UnhealthyThresholdCount: 5
    HealthCheckTimeoutSeconds: 5
  aws:elasticbeanstalk:healthreporting:system:
    SystemType: enhanced
```

**.ebextensions/03-logging.config:**

```yaml
files:
  '/opt/elasticbeanstalk/tasks/taillogs.d/01-app.conf':
    mode: '000644'
    owner: root
    group: root
    content: |
      /var/log/eb-docker/containers/eb-current-app/eb-*-stdouterr.log

option_settings:
  aws:elasticbeanstalk:cloudwatch:logs:
    StreamLogs: true
    DeleteOnTerminate: false
    RetentionInDays: 7
```

### 3.2 EB 초기화

```bash
# EB 초기화
eb init

# 설정 입력:
# 1. 리전 선택: ap-northeast-2 (서울)
# 2. 애플리케이션 이름: my-app (원하는 이름)
# 3. 플랫폼: Docker
# 4. 플랫폼 버전: Docker running on 64bit Amazon Linux 2023 (최신)
# 5. CodeCommit: No
# 6. SSH: Yes (키페어 이름 입력 또는 새로 생성)
```

### 3.3 환경 생성

```bash
# 환경 생성
eb create production

# 또는 설정과 함께 생성
eb create production \
    --instance-type t3.small \
    --single-instance \
    --envvars NODE_ENV=production,PORT=8080
```

### 3.4 첫 배포

```bash
# 첫 배포
eb deploy production

# 상태 확인
eb status production
eb health production

# 애플리케이션 열기
eb open production
```

---

## 🚀 4단계: GitHub 브랜치 전략 및 CI/CD 설정

### 4.1 브랜치 전략 설정

**브랜치 구조:**

```
main (보호됨)
├── rel (릴리즈 브랜치) → Production 환경
├── dev (개발 브랜치) → Development 환경
└── feature/* (기능 브랜치) → 로컬 개발
```

**워크플로우:**

```
1. feature/new-feature → dev (PR) → Development 배포
2. dev → rel (PR) → Release(Staging) 배포
3. rel → main (PR) → Production 배포
```

### 4.2 브랜치 생성 및 보호 설정

```bash
# 로컬에서 브랜치 생성
git checkout -b dev
git push origin dev

git checkout -b rel
git push origin rel

# main 브랜치로 돌아가기
git checkout main
```

**GitHub에서 브랜치 보호 설정:**

```
Repository → Settings → Branches → Add rule

main 브랜치:
✅ Require pull request reviews before merging
✅ Require status checks to pass before merging
✅ Require branches to be up to date before merging
✅ Include administrators

rel 브랜치:
✅ Require pull request reviews before merging
✅ Require status checks to pass before merging

dev 브랜치:
✅ Require status checks to pass before merging (optional)
```

### 4.3 GitHub Secrets 설정

**GitHub Repository → Settings → Secrets and variables → Actions**

```yaml
Secrets 추가:
  - AWS_ACCESS_KEY: (IAM 사용자의 Access Key ID)
  - AWS_ACCESS_SECRET_KEY: (IAM 사용자의 Secret Access Key)

  # 환경별 설정 (선택사항)
  - DEV_APP_NAME: my-app
  - DEV_ENV_NAME: development
  - REL_APP_NAME: my-app
  - REL_ENV_NAME: staging
  - PROD_APP_NAME: my-app
  - PROD_ENV_NAME: production
```

### 4.4 GitHub Actions 워크플로우 파일 생성

**.github/workflows/deploy-dev.yml** (dev 브랜치용):

```yaml
name: Deploy to Development
on:
  pull_request:
    branches:
      - dev
    types:
      - closed

jobs:
  deploy-dev:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Get Timestamp
        uses: gerred/actions/current-time@master
        id: current-time

      - name: Run String Replace
        uses: frabert/replace-string-action@master
        id: format-time
        with:
          pattern: '[:\.]+'
          string: '${{ steps.current-time.outputs.time }}'
          replace-with: '-'
          flags: 'g'

      - name: Generate Deployment Package
        run: zip -r deploy.zip . -x "**node_modules**" "**.git**" "**.github**"

      - name: Deploy to Development
        uses: einaregilsson/beanstalk-deploy@v21
        with:
          aws_access_key: ${{ secrets.AWS_ACCESS_KEY }}
          aws_secret_key: ${{ secrets.AWS_ACCESS_SECRET_KEY }}
          application_name: ${{ secrets.DEV_APP_NAME || 'my-app' }}
          environment_name: ${{ secrets.DEV_ENV_NAME || 'development' }}
          version_label: 'dev-${{ steps.format-time.outputs.replaced }}'
          region: ap-northeast-2
          deployment_package: deploy.zip
          wait_for_environment_recovery: 300
          version_description: 'Dev: ${{ github.event.pull_request.title }}'

      - name: Comment PR
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '🚀 Development 환경에 배포 완료!\n배포 버전: dev-${{ steps.format-time.outputs.replaced }}'
            })
```

**.github/workflows/deploy-rel.yml** (rel 브랜치용):

```yaml
name: Deploy to Release/Staging
on:
  pull_request:
    branches:
      - rel
    types:
      - closed

jobs:
  deploy-staging:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Get Timestamp
        uses: gerred/actions/current-time@master
        id: current-time

      - name: Run String Replace
        uses: frabert/replace-string-action@master
        id: format-time
        with:
          pattern: '[:\.]+'
          string: '${{ steps.current-time.outputs.time }}'
          replace-with: '-'
          flags: 'g'

      - name: Generate Deployment Package
        run: zip -r deploy.zip . -x "**node_modules**" "**.git**" "**.github**"

      - name: Deploy to Staging
        uses: einaregilsson/beanstalk-deploy@v21
        with:
          aws_access_key: ${{ secrets.AWS_ACCESS_KEY }}
          aws_secret_key: ${{ secrets.AWS_ACCESS_SECRET_KEY }}
          application_name: ${{ secrets.REL_APP_NAME || 'my-app' }}
          environment_name: ${{ secrets.REL_ENV_NAME || 'staging' }}
          version_label: 'rel-${{ steps.format-time.outputs.replaced }}'
          region: ap-northeast-2
          deployment_package: deploy.zip
          wait_for_environment_recovery: 300
          version_description: 'Release: ${{ github.event.pull_request.title }}'

      - name: Comment PR
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '🎯 Staging 환경에 배포 완료!\n배포 버전: rel-${{ steps.format-time.outputs.replaced }}\n\n✅ QA 테스트 후 Production 배포를 진행해주세요.'
            })
```

**.github/workflows/deploy-production.yml** (main 브랜치용):

```yaml
name: Deploy to Production
on:
  pull_request:
    branches:
      - main
    types:
      - closed

jobs:
  deploy-production:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Get Timestamp
        uses: gerred/actions/current-time@master
        id: current-time

      - name: Run String Replace
        uses: frabert/replace-string-action@master
        id: format-time
        with:
          pattern: '[:\.]+'
          string: '${{ steps.current-time.outputs.time }}'
          replace-with: '-'
          flags: 'g'

      - name: Generate Deployment Package
        run: zip -r deploy.zip . -x "**node_modules**" "**.git**" "**.github**"

      - name: Deploy to Production
        uses: einaregilsson/beanstalk-deploy@v21
        with:
          aws_access_key: ${{ secrets.AWS_ACCESS_KEY }}
          aws_secret_key: ${{ secrets.AWS_ACCESS_SECRET_KEY }}
          application_name: ${{ secrets.PROD_APP_NAME || 'my-app' }}
          environment_name: ${{ secrets.PROD_ENV_NAME || 'production' }}
          version_label: 'prod-${{ steps.format-time.outputs.replaced }}'
          region: ap-northeast-2
          deployment_package: deploy.zip
          wait_for_environment_recovery: 300
          version_description: 'Production: ${{ github.event.pull_request.title }}'

      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: v${{ steps.format-time.outputs.replaced }}
          release_name: Release v${{ steps.format-time.outputs.replaced }}
          body: |
            🎉 Production 배포 완료!

            **배포 내용:** ${{ github.event.pull_request.title }}
            **배포 버전:** prod-${{ steps.format-time.outputs.replaced }}
            **배포 시간:** ${{ steps.current-time.outputs.time }}
          draft: false
          prerelease: false

      - name: Notify Team
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '🎉 **Production 배포 완료!**\n\n배포 버전: prod-${{ steps.format-time.outputs.replaced }}\n릴리즈: v${{ steps.format-time.outputs.replaced }}\n\n모든 팀원에게 배포 완료를 알려주세요! 🚀'
            })
```

### 4.5 환경별 EB 환경 생성

```bash
# Development 환경 생성
eb create development \
    --instance-type t3.micro \
    --single-instance \
    --envvars NODE_ENV=development,PORT=8080

# Staging 환경 생성
eb create staging \
    --instance-type t3.small \
    --single-instance \
    --envvars NODE_ENV=staging,PORT=8080

# Production 환경 생성
eb create production \
    --elb-type application \
    --instance-type t3.small \
    --min-instances 1 \
    --max-instances 3 \
    --envvars NODE_ENV=production,PORT=8080
```

---

## 🔐 5단계: HTTPS 설정 (선택사항)

### 5.1 Load Balanced 환경으로 변경

**.ebextensions/04-load-balancer.config:**

```yaml
option_settings:
  aws:elasticbeanstalk:environment:
    EnvironmentType: LoadBalanced
    LoadBalancerType: application
  aws:autoscaling:asg:
    MinSize: 1
    MaxSize: 2
  aws:elbv2:loadbalancer:
    IdleTimeout: 60
```

### 5.2 SSL 인증서 발급

```bash
# AWS Certificate Manager에서 인증서 요청
aws acm request-certificate \
    --domain-name yourdomain.com \
    --subject-alternative-names "*.yourdomain.com" \
    --validation-method DNS \
    --region ap-northeast-2

# 인증서 ARN 확인
aws acm list-certificates --region ap-northeast-2
```

### 5.3 HTTPS 리스너 설정

**.ebextensions/05-https.config:**

```yaml
option_settings:
  aws:elbv2:listener:443:
    Protocol: HTTPS
    SSLCertificateArns: arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID

  aws:elbv2:listener:80:
    Protocol: HTTP
    Rules: |
      [
        {
          "Priority": 1,
          "Conditions": [{"Field": "host-header", "Values": ["yourdomain.com"]}],
          "Actions": [{"Type": "redirect", "RedirectConfig": {"Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}]
        }
      ]
```

---

## 📱 6단계: 브랜치 전략별 배포 스크립트 설정

### 6.1 환경별 배포 스크립트

**deploy-dev.sh (Development 환경용):**

```bash
#!/bin/bash
set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Development 환경 배포${NC}"
echo "=================================="

# Git 브랜치 확인
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "dev" ]; then
    echo -e "${YELLOW}⚠️ 현재 브랜치: $CURRENT_BRANCH${NC}"
    echo "Development 배포는 dev 브랜치에서 진행하는 것을 권장합니다."
    read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 메시지 설정
MESSAGE=${1:-"Dev deployment $(date '+%Y-%m-%d %H:%M:%S')"}

# 배포
eb deploy development --message "$MESSAGE" --timeout 15

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Development 배포 완료!${NC}"
    eb health development
    echo ""
    echo "🌐 Development URL:"
    eb status development | grep CNAME
else
    echo "❌ 배포 실패"
    exit 1
fi
```

**deploy-rel.sh (Staging 환경용):**

```bash
#!/bin/bash
set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🎯 Staging 환경 배포${NC}"
echo "=================================="

# Git 브랜치 확인
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "rel" ]; then
    echo -e "${RED}❌ 현재 브랜치: $CURRENT_BRANCH${NC}"
    echo "Staging 배포는 rel 브랜치에서만 가능합니다."
    exit 1
fi

# dev 브랜치와 동기화 확인
echo "📋 dev 브랜치와의 동기화 확인..."
git fetch origin dev
BEHIND=$(git rev-list --count HEAD..origin/dev)
if [ $BEHIND -gt 0 ]; then
    echo -e "${YELLOW}⚠️ rel 브랜치가 dev 브랜치보다 $BEHIND 커밋 뒤에 있습니다.${NC}"
    echo "dev 브랜치를 rel에 머지해주세요."
    exit 1
fi

# 메시지 설정
MESSAGE=${1:-"Staging deployment $(date '+%Y-%m-%d %H:%M:%S')"}

echo -e "${YELLOW}🔔 Staging 환경에 배포합니다.${NC}"
echo "메시지: $MESSAGE"
read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# 배포
eb deploy staging --message "$MESSAGE" --timeout 15

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Staging 배포 완료!${NC}"
    eb health staging
    echo ""
    echo "🌐 Staging URL:"
    eb status staging | grep CNAME
    echo ""
    echo -e "${YELLOW}📝 QA 테스트 후 Production 배포를 진행해주세요.${NC}"
else
    echo "❌ 배포 실패"
    exit 1
fi
```

**deploy-prod.sh (Production 환경용):**

```bash
#!/bin/bash
set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}🎉 Production 환경 배포${NC}"
echo "=================================="

# Git 브랜치 확인
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}❌ 현재 브랜치: $CURRENT_BRANCH${NC}"
    echo "Production 배포는 main 브랜치에서만 가능합니다."
    exit 1
fi

# rel 브랜치와 동기화 확인
echo "📋 rel 브랜치와의 동기화 확인..."
git fetch origin rel
BEHIND=$(git rev-list --count HEAD..origin/rel)
if [ $BEHIND -gt 0 ]; then
    echo -e "${YELLOW}⚠️ main 브랜치가 rel 브랜치보다 $BEHIND 커밋 뒤에 있습니다.${NC}"
    echo "rel 브랜치를 main에 머지해주세요."
    exit 1
fi

# 메시지 설정
MESSAGE=${1:-"Production deployment $(date '+%Y-%m-%d %H:%M:%S')"}

echo -e "${RED}🚨 PRODUCTION 환경에 배포합니다! 🚨${NC}"
echo "메시지: $MESSAGE"
echo ""
echo "⚠️  프로덕션 배포는 매우 신중하게 진행해야 합니다!"
echo "⚠️  QA 테스트가 완료되었는지 확인해주세요!"
echo ""
read -p "정말로 프로덕션에 배포하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "배포가 취소되었습니다."
    exit 0
fi

echo "마지막 확인입니다..."
read -p "프로덕션 배포를 최종 확인합니다. (YES 입력): " confirmation
if [ "$confirmation" != "YES" ]; then
    echo "배포가 취소되었습니다."
    exit 0
fi

# 배포
echo -e "${BLUE}🚀 프로덕션 배포 시작...${NC}"
eb deploy production --message "$MESSAGE" --timeout 20

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 Production 배포 완료!${NC}"
    eb health production
    echo ""
    echo "🌐 Production URL:"
    eb status production | grep CNAME
    echo ""
    echo -e "${GREEN}🎊 모든 팀원에게 배포 완료를 알려주세요! 🎊${NC}"

    # Git 태그 생성
    TAG="v$(date '+%Y%m%d-%H%M%S')"
    git tag -a "$TAG" -m "Production release: $MESSAGE"
    git push origin "$TAG"
    echo "🏷️  Git 태그 생성: $TAG"
else
    echo "❌ 배포 실패"
    exit 1
fi
```

### 6.2 Makefile (브랜치별 배포 지원)

```makefile
# Makefile (브랜치 전략 지원)
.PHONY: help deploy-dev deploy-rel deploy-prod status-all health-all logs-all

# 색상 정의
BLUE = \033[0;34m
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m

# 현재 브랜치 확인
CURRENT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# 기본 명령어
all: help

help:
	@echo "$(BLUE)🚀 브랜치 전략 기반 배포 명령어$(NC)"
	@echo "================================================"
	@echo ""
	@echo "현재 브랜치: $(YELLOW)$(CURRENT_BRANCH)$(NC)"
	@echo ""
	@echo "배포 명령어:"
	@echo "  $(GREEN)make deploy-dev$(NC)      - Development 환경 배포 (dev 브랜치)"
	@echo "  $(GREEN)make deploy-rel$(NC)      - Staging 환경 배포 (rel 브랜치)"
	@echo "  $(GREEN)make deploy-prod$(NC)     - Production 환경 배포 (main 브랜치)"
	@echo ""
	@echo "모니터링 명령어:"
	@echo "  $(GREEN)make status-all$(NC)      - 모든 환경 상태 확인"
	@echo "  $(GREEN)make health-all$(NC)      - 모든 환경 헬스 체크"
	@echo "  $(GREEN)make logs-dev$(NC)        - Development 로그"
	@echo "  $(GREEN)make logs-rel$(NC)        - Staging 로그"
	@echo "  $(GREEN)make logs-prod$(NC)       - Production 로그"
	@echo ""
	@echo "개별 환경 명령어:"
	@echo "  $(GREEN)make dev-status$(NC)      - Development 상태"
	@echo "  $(GREEN)make rel-status$(NC)      - Staging 상태"
	@echo "  $(GREEN)make prod-status$(NC)     - Production 상태"
	@echo ""
	@echo "브랜치 관리:"
	@echo "  $(GREEN)make switch-dev$(NC)      - dev 브랜치로 전환"
	@echo "  $(GREEN)make switch-rel$(NC)      - rel 브랜치로 전환"
	@echo "  $(GREEN)make switch-main$(NC)     - main 브랜치로 전환"

# 배포 명령어
deploy-dev:
	@echo "$(BLUE)🚀 Development 환경 배포$(NC)"
	@./deploy-dev.sh "$(MSG)"

deploy-rel:
	@echo "$(BLUE)🎯 Staging 환경 배포$(NC)"
	@./deploy-rel.sh "$(MSG)"

deploy-prod:
	@echo "$(RED)🎉 Production 환경 배포$(NC)"
	@./deploy-prod.sh "$(MSG)"

# 상태 확인
dev-status:
	@echo "$(BLUE)📊 Development 상태$(NC)"
	@eb status development

rel-status:
	@echo "$(BLUE)📊 Staging 상태$(NC)"
	@eb status staging

prod-status:
	@echo "$(BLUE)📊 Production 상태$(NC)"
	@eb status production

status-all: dev-status rel-status prod-status

# 헬스 체크
dev-health:
	@echo "$(BLUE)🏥 Development 헬스$(NC)"
	@eb health development

rel-health:
	@echo "$(BLUE)🏥 Staging 헬스$(NC)"
	@eb health staging

prod-health:
	@echo "$(BLUE)🏥 Production 헬스$(NC)"
	@eb health production

health-all: dev-health rel-health prod-health

# 로그 확인
logs-dev:
	@eb logs development

logs-rel:
	@eb logs staging

logs-prod:
	@eb logs production

# 브랜치 전환
switch-dev:
	@git checkout dev
	@git pull origin dev

switch-rel:
	@git checkout rel
	@git pull origin rel

switch-main:
	@git checkout main
	@git pull origin main

# 브랜치 동기화
sync-dev-to-rel:
	@echo "$(YELLOW)🔄 dev → rel 동기화$(NC)"
	@git checkout rel
	@git pull origin rel
	@git merge origin/dev
	@git push origin rel

sync-rel-to-main:
	@echo "$(YELLOW)🔄 rel → main 동기화$(NC)"
	@git checkout main
	@git pull origin main
	@git merge origin/rel
	@git push origin main

# 환경 정보
info:
	@echo "$(BLUE)📄 환경 정보$(NC)"
	@echo "=================================="
	@echo "현재 브랜치: $(CURRENT_BRANCH)"
	@echo "마지막 커밋: $(shell git log -1 --oneline 2>/dev/null || echo '알 수 없음')"
	@echo ""
	@echo "EB 환경:"
	@echo "  Development: development"
	@echo "  Staging: staging"
	@echo "  Production: production"
```

### 6.3 개발 워크플로우 스크립트

**workflow.sh (전체 워크플로우 도움):**

```bash
#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_workflow_help() {
    echo -e "${BLUE}🔄 개발 워크플로우 가이드${NC}"
    echo "=================================="
    echo ""
    echo "1️⃣  새 기능 개발:"
    echo "   git checkout dev"
    echo "   git pull origin dev"
    echo "   git checkout -b feature/new-feature"
    echo "   # 개발 작업..."
    echo "   git add . && git commit -m 'feat: 새 기능 추가'"
    echo "   git push origin feature/new-feature"
    echo "   # GitHub에서 feature/new-feature → dev PR 생성"
    echo ""
    echo "2️⃣  개발 환경 테스트:"
    echo "   # PR 머지 후 자동으로 Development 환경에 배포됨"
    echo "   # 또는 수동 배포:"
    echo "   git checkout dev"
    echo "   make deploy-dev"
    echo ""
    echo "3️⃣  스테이징 배포:"
    echo "   # dev → rel PR 생성 및 머지"
    echo "   # PR 머지 후 자동으로 Staging 환경에 배포됨"
    echo "   # 또는 수동 배포:"
    echo "   git checkout rel"
    echo "   make deploy-rel"
    echo ""
    echo "4️⃣  프로덕션 배포:"
    echo "   # QA 테스트 완료 후"
    echo "   # rel → main PR 생성 및 머지"
    echo "   # PR 머지 후 자동으로 Production 환경에 배포됨"
    echo "   # 또는 수동 배포:"
    echo "   git checkout main"
    echo "   make deploy-prod"
    echo ""
    echo -e "${YELLOW}💡 유용한 명령어:${NC}"
    echo "   make help              # 모든 명령어 보기"
    echo "   make status-all        # 모든 환경 상태 확인"
    echo "   make health-all        # 모든 환경 헬스 체크"
    echo "   make info              # 현재 상태 정보"
}

case "$1" in
    "help"|""|"-h"|"--help")
        show_workflow_help
        ;;
    "feature")
        FEATURE_NAME="$2"
        if [ -z "$FEATURE_NAME" ]; then
            read -p "기능 이름을 입력하세요: " FEATURE_NAME
        fi
        echo -e "${BLUE}🚀 새 기능 브랜치 생성: feature/$FEATURE_NAME${NC}"
        git checkout dev
        git pull origin dev
        git checkout -b "feature/$FEATURE_NAME"
        echo -e "${GREEN}✅ feature/$FEATURE_NAME 브랜치에서 개발을 시작하세요!${NC}"
        ;;
    "deploy")
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        case "$CURRENT_BRANCH" in
            "dev")
                make deploy-dev
                ;;
            "rel")
                make deploy-rel
                ;;
            "main")
                make deploy-prod
                ;;
            *)
                echo -e "${RED}❌ 현재 브랜치($CURRENT_BRANCH)에서는 배포할 수 없습니다.${NC}"
                echo "dev, rel, main 브랜치에서만 배포 가능합니다."
                ;;
        esac
        ;;
    *)
        echo "사용법: $0 {help|feature|deploy}"
        echo ""
        echo "  help     - 워크플로우 가이드 표시"
        echo "  feature  - 새 기능 브랜치 생성"
        echo "  deploy   - 현재 브랜치에 맞는 환경에 배포"
        ;;
esac
```

---

## ✅ 7단계: 테스트 및 검증

### 7.1 로컬 테스트

```bash
# Docker 빌드 테스트
docker build -t my-app .

# 로컬 실행 테스트
docker run -p 3000:8080 my-app

# 헬스체크 테스트
curl http://localhost:3000/health
```

### 7.2 브랜치별 배포 테스트

**Development 환경 테스트:**

```bash
# dev 브랜치에서 배포
git checkout dev
make deploy-dev

# 또는 스크립트로
./deploy-dev.sh "개발 환경 테스트"

# 상태 확인
eb status development
eb health development
```

**Staging 환경 테스트:**

```bash
# rel 브랜치에서 배포
git checkout rel
make deploy-rel

# 상태 확인
eb status staging
eb health staging
```

**Production 환경 테스트:**

```bash
# main 브랜치에서 배포 (신중하게!)
git checkout main
make deploy-prod

# 상태 확인
eb status production
eb health production
```

### 7.3 GitHub Actions 워크플로우 테스트

**Feature → Dev 워크플로우:**

```bash
# 1. 새 기능 브랜치 생성
./workflow.sh feature new-login

# 2. 개발 작업 후 커밋
git add .
git commit -m "feat: 새로운 로그인 기능 추가"
git push origin feature/new-login

# 3. GitHub에서 feature/new-login → dev PR 생성
# 4. PR 머지 시 자동으로 Development 환경에 배포됨
```

**Dev → Rel 워크플로우:**

```bash
# 1. dev → rel PR 생성 (GitHub에서)
# 2. PR 머지 시 자동으로 Staging 환경에 배포됨
# 3. QA 테스트 진행
```

**Rel → Main 워크플로우:**

```bash
# 1. QA 완료 후 rel → main PR 생성
# 2. PR 머지 시 자동으로 Production 환경에 배포됨
# 3. 자동으로 Release 태그 생성됨
```

### 7.4 전체 환경 모니터링

```bash
# 모든 환경 상태 확인
make status-all

# 모든 환경 헬스 체크
make health-all

# 환경별 URL 확인
echo "Development: $(eb status development | grep CNAME | awk '{print $2}')"
echo "Staging: $(eb status staging | grep CNAME | awk '{print $2}')"
echo "Production: $(eb status production | grep CNAME | awk '{print $2}')"
```

---

## 🎯 8단계: 최종 설정 완료

### 8.1 브랜치별 환경 매핑

**환경 구성:**

```yaml
Branches → Environments:
  feature/* → 로컬 개발 (Docker)
  dev       → Development (EB: development)
  rel       → Staging (EB: staging)
  main      → Production (EB: production)

Deployment Triggers:
  PR → dev: Development 자동 배포
  PR → rel: Staging 자동 배포
  PR → main: Production 자동 배포 + Release 생성
```

### 8.2 환경별 설정 차이점

**Development (.ebextensions/dev-specific.config):**

```yaml
option_settings:
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.micro # 최소 비용
  aws:elasticbeanstalk:environment:
    EnvironmentType: SingleInstance
  aws:elasticbeanstalk:application:environment:
    NODE_ENV: development
    LOG_LEVEL: debug
```

**Staging (.ebextensions/staging-specific.config):**

```yaml
option_settings:
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.small
  aws:elasticbeanstalk:environment:
    EnvironmentType: SingleInstance
  aws:elasticbeanstalk:application:environment:
    NODE_ENV: staging
    LOG_LEVEL: info
```

**Production (.ebextensions/prod-specific.config):**

```yaml
option_settings:
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.small
  aws:elasticbeanstalk:environment:
    EnvironmentType: LoadBalanced
    LoadBalancerType: application
  aws:autoscaling:asg:
    MinSize: 1
    MaxSize: 3
  aws:elasticbeanstalk:application:environment:
    NODE_ENV: production
    LOG_LEVEL: warn
```

### 8.3 팀 개발 가이드라인

**브랜치 네이밍 규칙:**

```
feature/JIRA-123-login-improvement
feature/user-dashboard
hotfix/critical-security-fix
release/v1.2.0
```

**커밋 메시지 규칙:**

```
feat: 새로운 기능 추가
fix: 버그 수정
docs: 문서 수정
style: 코드 포맷팅
refactor: 코드 리팩토링
test: 테스트 코드 추가
chore: 빌드 과정 또는 보조 기능 수정
```

**PR 템플릿 (.github/pull_request_template.md):**

```markdown
## 변경 내용

- [ ] 새로운 기능
- [ ] 버그 수정
- [ ] 성능 개선
- [ ] 문서 업데이트

## 설명

<!-- 변경 내용에 대한 간단한 설명 -->

## 테스트

- [ ] 로컬 테스트 완료
- [ ] Unit 테스트 추가/수정
- [ ] Integration 테스트 확인

## 체크리스트

- [ ] 코드 리뷰 요청
- [ ] 관련 이슈 연결
- [ ] 문서 업데이트 (필요시)

## 배포 후 확인사항

- [ ] 헬스체크 정상
- [ ] 주요 기능 동작 확인
- [ ] 로그 에러 없음
```

### 8.4 모니터링 및 알람 설정

**CloudWatch 대시보드 생성:**

```bash
# CloudWatch 대시보드 JSON 파일 생성
cat > cloudwatch-dashboard.json << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/ElasticBeanstalk", "ApplicationLatency", "EnvironmentName", "development"],
                    [".", ".", ".", "staging"],
                    [".", ".", ".", "production"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "ap-northeast-2",
                "title": "Application Latency"
            }
        }
    ]
}
EOF

# 대시보드 생성
aws cloudwatch put-dashboard \
    --dashboard-name "MyApp-EB-Dashboard" \
    --dashboard-body file://cloudwatch-dashboard.json
```

**알람 설정:**

```bash
# High Latency 알람
aws cloudwatch put-metric-alarm \
    --alarm-name "Production-HighLatency" \
    --alarm-description "Production High Latency" \
    --metric-name ApplicationLatency \
    --namespace AWS/ElasticBeanstalk \
    --statistic Average \
    --period 300 \
    --threshold 2.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=EnvironmentName,Value=production

# Application Requests 알람
aws cloudwatch put-metric-alarm \
    --alarm-name "Production-LowRequests" \
    --alarm-description "Production Low Request Count" \
    --metric-name ApplicationRequests \
    --namespace AWS/ElasticBeanstalk \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator LessThanThreshold \
    --dimensions Name=EnvironmentName,Value=production
```

---

## 📋 완료 체크리스트

### 브랜치 전략 설정

- [ ] AWS 계정 및 IAM 사용자 생성
- [ ] AWS CLI 및 EB CLI 설치
- [ ] NestJS 프로젝트 생성
- [ ] Dockerfile 및 .dockerignore 작성
- [ ] .ebextensions 폴더 설정

### 브랜치 및 환경 설정

- [ ] dev, rel, main 브랜치 생성
- [ ] GitHub 브랜치 보호 규칙 설정
- [ ] Development 환경 생성 (development)
- [ ] Staging 환경 생성 (staging)
- [ ] Production 환경 생성 (production)

### CI/CD 파이프라인

- [ ] GitHub Secrets 설정 (AWS_ACCESS_KEY, AWS_ACCESS_SECRET_KEY)
- [ ] deploy-dev.yml 워크플로우 설정
- [ ] deploy-rel.yml 워크플로우 설정
- [ ] deploy-production.yml 워크플로우 설정
- [ ] PR 템플릿 생성

### 배포 스크립트

- [ ] deploy-dev.sh 스크립트 생성
- [ ] deploy-rel.sh 스크립트 생성
- [ ] deploy-prod.sh 스크립트 생성
- [ ] Makefile 설정 (브랜치별 명령어)
- [ ] workflow.sh 헬퍼 스크립트 생성

### 선택 설정

- [ ] HTTPS 인증서 설정
- [ ] 도메인 연결
- [ ] CloudWatch 모니터링
- [ ] 알람 설정

### 최종 확인

- [ ] 모든 환경 정상 배포 확인
- [ ] 헬스체크 응답 확인 (/health)
- [ ] GitHub PR 워크플로우 테스트
- [ ] 브랜치별 자동 배포 확인
- [ ] 로그 정상 출력 확인

---

## 🚨 트러블슈팅

### 브랜치 전략 관련

#### 1. PR 자동 배포가 안되는 경우

```bash
# GitHub Actions 워크플로우 파일 확인
ls -la .github/workflows/

# Secrets 설정 확인
# GitHub Repository → Settings → Secrets and variables → Actions

# 브랜치 보호 규칙 확인
# GitHub Repository → Settings → Branches
```

#### 2. 잘못된 브랜치에서 배포 시도

```bash
# 현재 브랜치 확인
git branch --show-current

# 올바른 브랜치로 전환
make switch-dev    # dev 브랜치로
make switch-rel    # rel 브랜치로
make switch-main   # main 브랜치로
```

#### 3. 브랜치 동기화 문제

```bash
# dev → rel 동기화
make sync-dev-to-rel

# rel → main 동기화
make sync-rel-to-main

# 수동 동기화
git checkout rel
git pull origin rel
git merge origin/dev
git push origin rel
```

### 환경별 배포 문제

#### 1. 환경별 설정 차이로 인한 오류

```bash
# 환경별 환경변수 확인
eb printenv development
eb printenv staging
eb printenv production

# 설정 파일 확인
cat .ebextensions/01-environment.config
```

#### 2. 특정 환경에서만 발생하는 오류

```bash
# 환경별 로그 확인
make logs-dev
make logs-rel
make logs-prod

# 환경별 상태 비교
make status-all
make health-all
```

---

## 🎉 완료!

이제 완전한 **브랜치 전략 기반 NestJS + Docker + Elastic Beanstalk + CI/CD** 환경이 구축되었습니다!

### 🚀 일반적인 개발 워크플로우

**1. 새 기능 개발:**

```bash
./workflow.sh feature login-improvement
# 개발 작업...
git add . && git commit -m "feat: 로그인 개선"
git push origin feature/login-improvement
# GitHub에서 feature → dev PR 생성
```

**2. 개발 환경 테스트:**

```bash
# PR 머지 시 자동 배포됨
# 또는 수동: make deploy-dev
```

**3. 스테이징 배포:**

```bash
# dev → rel PR 생성 및 머지
# PR 머지 시 자동 배포됨
# 또는 수동: make deploy-rel
```

**4. 프로덕션 배포:**

```bash
# QA 완료 후 rel → main PR 생성 및 머지
# PR 머지 시 자동 배포됨 + Release 생성
# 또는 수동: make deploy-prod
```

### 📱 유용한 명령어들

```bash
# 전체 상황 파악
make info
make status-all
make health-all

# 브랜치별 배포
make deploy-dev MSG="새 기능 테스트"
make deploy-rel MSG="QA 요청"
make deploy-prod MSG="v1.2.0 릴리즈"

# 워크플로우 도움말
./workflow.sh help

# 빠른 개발 시작
./workflow.sh feature my-new-feature
```

완벽한 엔터프라이즈급 개발 환경이 완성되었습니다! 🎊
