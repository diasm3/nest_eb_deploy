# Elastic Beanstalk 완전 신규 설정 매뉴얼

_새로운 AWS 계정에서 NestJS Docker 프로젝트를 Elastic Beanstalk으로 배포하는 완벽 가이드_

---

## 🎯 설정 완료 후 결과

- ✅ NestJS + Docker 애플리케이션
- ✅ Elastic Beanstalk 자동 배포
- ✅ GitHub Actions CI/CD
- ✅ HTTPS 지원 (ALB 기본 포함)
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

권한 정책 (필수):
  - AWSElasticBeanstalkFullAccess
  - IAMFullAccess (중요! 서비스 롤 생성용)
  - AmazonS3FullAccess
  - AmazonEC2FullAccess
  - ElasticLoadBalancingFullAccess
  - AutoScalingFullAccess
  - AWSCertificateManagerFullAccess (HTTPS용)
  - CloudWatchFullAccess
  - CloudFormationFullAccess
```

**⚠️ 중요:** `IAMFullAccess` 정책이 없으면 Elastic Beanstalk가 필요한 서비스 롤을 생성할 수 없어 배포가 실패합니다.

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

### 1.3 필수 서비스 롤 생성 (선택사항)

IAM 권한이 충분하다면 Elastic Beanstalk가 자동으로 생성하지만, 수동으로 미리 생성할 수도 있습니다:

```bash
# EC2 인스턴스 롤 생성
aws iam create-role \
    --role-name aws-elasticbeanstalk-ec2-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "ec2.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }
        ]
    }'

# 정책 연결
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier

# 인스턴스 프로파일 생성
aws iam create-instance-profile \
    --instance-profile-name aws-elasticbeanstalk-ec2-role

aws iam add-role-to-instance-profile \
    --instance-profile-name aws-elasticbeanstalk-ec2-role \
    --role-name aws-elasticbeanstalk-ec2-role

# 서비스 롤 생성
aws iam create-role \
    --role-name aws-elasticbeanstalk-service-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "elasticbeanstalk.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }
        ]
    }'

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService
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
    IamInstanceProfile: aws-elasticbeanstalk-ec2-role
  aws:elasticbeanstalk:environment:
    EnvironmentType: LoadBalanced
    LoadBalancerType: application
    ServiceRole: aws-elasticbeanstalk-service-role
  aws:autoscaling:asg:
    MinSize: 1
    MaxSize: 3
  aws:autoscaling:updatepolicy:rollingupdate:
    RollingUpdateEnabled: true
    MinInstancesInService: 1
    MaxBatchSize: 1
    RollingUpdateType: Health
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
# 환경 생성 (HTTPS 지원을 위한 ALB 포함)
eb create production \
    --elb-type application \
    --instance_type t3.small \
    --min-instances 1 \
    --max-instances 3 \
    --envvars NODE_ENV=production,PORT=8080 \
    --service-role aws-elasticbeanstalk-service-role

# 또는 기본 환경 생성 후 설정
eb create production
```

**⚠️ 일반적인 오류 해결:**

만약 다음과 같은 오류가 발생하면:

- `"option_settings" in one of the configuration files failed validation`
- `You can't enable rolling updates for a single-instance environment`
- `Insufficient IAM privileges`

**해결방법:**

1. IAM 사용자에 `IAMFullAccess` 정책이 있는지 확인
2. 위의 1.3 단계의 서비스 롤 생성 명령어를 실행
3. 환경을 LoadBalanced 타입으로 생성 (Single Instance 대신)

### 3.4 첫 배포

```bash
# 환경 생성 완료 확인
eb status production
eb health production

# 첫 배포
eb deploy production --timeout 15

# 배포 완료 후 최종 확인
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
main (보호됨, 아카이브용)
├── rel (릴리즈 브랜치) → Production 환경 (최종 배포)
├── dev (개발 브랜치) → Development 환경
└── feature/* (기능 브랜치) → 로컬 개발
```

**워크플로우:**

```
1. feature/new-feature → dev (PR) → Development 배포
2. dev → rel (PR) → Production 배포 (최종)
```

### 4.2 브랜치 생성 및 보호 설정

```bash
# 로컬에서 브랜치 생성
git checkout -b dev
git push origin dev

git checkout -b rel
git push origin rel

# main 브랜치로 돌아가기 (아카이브용)
git checkout main
```

**GitHub에서 브랜치 보호 설정:**

```
Repository → Settings → Branches → Add rule

rel 브랜치 (최종 배포):
✅ Require pull request reviews before merging
✅ Require status checks to pass before merging
✅ Require branches to be up to date before merging
✅ Include administrators

dev 브랜치:
✅ Require pull request reviews before merging (optional)
✅ Require status checks to pass before merging (optional)

main 브랜치 (아카이브):
✅ Require pull request reviews before merging
✅ Include administrators
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

**.github/workflows/deploy-rel.yml** (rel 브랜치용 - 최종 배포):

```yaml
name: Deploy to Production
on:
  pull_request:
    branches:
      - rel
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

**.github/workflows/deploy-production.yml** (main 브랜치용 - 아카이브):

```yaml
# 이 워크플로우는 필요시에만 사용 (아카이브 목적)
name: Archive to Main
on:
  workflow_dispatch: # 수동 실행만 허용
    inputs:
      reason:
        description: 'Archive reason'
        required: true
        type: string

jobs:
  archive-to-main:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Create Archive Tag
        run: |
          git config --local user.email "action@github.com"
          git config --local user.name "GitHub Action"

          TAG="archive-$(date '+%Y%m%d-%H%M%S')"
          git tag -a "$TAG" -m "Archive: ${{ github.event.inputs.reason }}"
          git push origin "$TAG"

          echo "🏷️ Archive 태그 생성: $TAG"
```

### 4.5 환경별 EB 환경 생성 (HTTPS 지원)

```bash
# Development 환경 생성 (ALB 포함 - HTTPS 준비)
eb create development \
    --elb-type application \
    --instance_type t3.micro \
    --min-instances 1 \
    --max-instances 1 \
    --envvars NODE_ENV=development,PORT=8080,LOG_LEVEL=debug \
    --service-role aws-elasticbeanstalk-service-role

# Production 환경 생성 (ALB 포함 - 고가용성 + HTTPS)
eb create production \
    --elb-type application \
    --instance_type t3.medium \
    --min-instances 2 \
    --max-instances 5 \
    --envvars NODE_ENV=production,PORT=8080,LOG_LEVEL=warn \
    --keyname prod-keypair \
    --tags Environment=Production,SSL=Ready \
    --service-role aws-elasticbeanstalk-service-role

# 최소 비용 개발환경 (HTTPS 불가, 서비스 롤 필요)
eb create development-minimal \
    --single \
    --instance_type t3.micro \
    --envvars NODE_ENV=development,PORT=8080 \
    --service-role aws-elasticbeanstalk-service-role
```

**⚠️ 환경 생성 시 주의사항:**

- `--service-role` 옵션을 반드시 포함하여 IAM 권한 문제 방지
- Single Instance 환경에서는 Rolling Update 설정을 .ebextensions에서 제거해야 함
- IAMFullAccess 정책이 없으면 서비스 롤 자동 생성 실패

---

## 🔐 5단계: HTTPS 설정 (AWS 공식 문서 기반)

### 5.1 Route 53 도메인 및 ACM 인증서 준비

#### 5.1.1 도메인 확인

```bash
# Route 53에서 구매한 도메인 확인
aws route53 list-hosted-zones --query 'HostedZones[*].{Name:Name,Id:Id}'
```

#### 5.1.2 ACM 인증서 요청

```bash
# SSL 인증서 요청 (DNS 검증 방식)
aws acm request-certificate \
    --domain-name yourdomain.com \
    --subject-alternative-names "*.yourdomain.com" \
    --validation-method DNS \
    --region ap-northeast-2

# 요청된 인증서 목록 확인
aws acm list-certificates --region ap-northeast-2

# 특정 인증서의 DNS 검증 레코드 확인
aws acm describe-certificate \
    --certificate-arn arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID \
    --region ap-northeast-2
```

#### 5.1.3 Route 53에 DNS 검증 레코드 추가

```bash
# ACM에서 제공한 CNAME 레코드를 Route 53에 추가
aws route53 change-resource-record-sets \
    --hosted-zone-id Z1D633PJN98FT9 \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "_VALIDATION_RECORD_NAME.yourdomain.com",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [{"Value": "VALIDATION_RECORD_VALUE.acm-validations.aws."}]
            }
        }]
    }'

# 인증서 검증 완료까지 대기 (보통 5-10분)
aws acm wait certificate-validated \
    --certificate-arn arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID \
    --region ap-northeast-2
```

### 5.2 Elastic Beanstalk에서 HTTPS 설정 (AWS 공식 방법)

#### 5.2.1 방법 1: 기본 HTTPS 리스너만 설정

**.ebextensions/05-https-basic.config:**

```yaml
####################################################################################################
#### Basic HTTPS Configuration - AWS 공식 문서 기반
#### Application Load Balancer에서만 동작 (Classic/Network Load Balancer 지원 안함)
#### 콘솔에서 이미 443 리스너를 만들었다면 이 설정을 사용하지 마세요
####################################################################################################

option_settings:
  aws:elbv2:listener:443:
    ListenerEnabled: 'true'
    Protocol: HTTPS
    SSLCertificateArns: arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID
    SSLPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06
```

#### 5.2.2 방법 2: HTTPS + HTTP 리다이렉트 (완전한 설정)

**.ebextensions/05-https-full.config:**

```yaml
####################################################################################################
#### Complete HTTPS Configuration with HTTP Redirect - AWS 공식 문서 기반
#### Application Load Balancer에서만 동작 (Classic/Network Load Balancer 지원 안함)
#### 콘솔에서 이미 443 리스너를 만들었다면 이 설정을 사용하지 마세요
####################################################################################################

option_settings:
  # HTTPS 리스너 설정 (443 포트)
  aws:elbv2:listener:443:
    ListenerEnabled: 'true'
    Protocol: HTTPS
    SSLCertificateArns: arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID
    SSLPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06

Resources:
  # HTTP(80) → HTTPS(443) 리다이렉트 설정
  AWSEBV2LoadBalancerListener:
    Type: 'AWS::ElasticLoadBalancingV2::Listener'
    Properties:
      DefaultActions:
        - Type: redirect
          RedirectConfig:
            Protocol: HTTPS
            Port: '443'
            Host: '#{host}'
            Path: '/#{path}'
            Query: '#{query}'
            StatusCode: HTTP_301
      LoadBalancerArn:
        Ref: AWSEBV2LoadBalancer
      Port: 80
      Protocol: HTTP
```

#### 5.2.3 방법 3: 별도 파일로 분리 (단계별 적용)

**Step 1: .ebextensions/05-https-listener.config**

```yaml
####################################################################################################
#### HTTPS Listener Only - 단계별 적용용
#### 먼저 HTTPS 리스너만 설정하고 동작 확인 후 리다이렉트 추가
####################################################################################################

option_settings:
  aws:elbv2:listener:443:
    ListenerEnabled: 'true'
    Protocol: HTTPS
    SSLCertificateArns: arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID
    SSLPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06
```

**Step 2: .ebextensions/06-https-redirect.config**

```yaml
####################################################################################################
#### HTTP to HTTPS Redirect Only - AWS 공식 예제 기반
#### 443 리스너가 이미 존재해야 함 (위의 설정 또는 콘솔에서 생성)
####################################################################################################

Resources:
  AWSEBV2LoadBalancerListener:
    Type: 'AWS::ElasticLoadBalancingV2::Listener'
    Properties:
      DefaultActions:
        - Type: redirect
          RedirectConfig:
            Protocol: HTTPS
            Port: '443'
            Host: '#{host}'
            Path: '/#{path}'
            Query: '#{query}'
            StatusCode: HTTP_301
      LoadBalancerArn:
        Ref: AWSEBV2LoadBalancer
      Port: 80
      Protocol: HTTP
```

### 5.3 Route 53에서 도메인 연결

#### 5.3.1 Elastic Beanstalk ALB DNS 이름 확인

```bash
# EB 환경의 ALB DNS 이름 확인
eb status production | grep CNAME

# 또는 AWS CLI로 확인
aws elasticbeanstalk describe-environments \
    --environment-names production \
    --query 'Environments[0].CNAME'
```

#### 5.3.2 Route 53 A 레코드 생성 (Alias)

**⚠️ 중요: 리전별 ALB Hosted Zone ID**

```bash
# 리전별 ALB Hosted Zone ID (정확한 값 필수!)
# 서울 (ap-northeast-2): ZWKZPGTI48KDX
# 버지니아 (us-east-1): Z35SXDOTRQ7X7K
# 오하이오 (us-east-2): Z3AADJGX6KTTL2
# 아일랜드 (eu-west-1): Z32O12XQLNTSW2
```

```bash
# Route 53에 A 레코드 (Alias) 생성
aws route53 change-resource-record-sets \
    --hosted-zone-id Z1D633PJN98FT9 \
    --change-batch '{
        "Changes": [
            {
                "Action": "CREATE",
                "ResourceRecordSet": {
                    "Name": "yourdomain.com",
                    "Type": "A",
                    "AliasTarget": {
                        "DNSName": "awseb-AWSEB-XXXXXXXXXXXXXXXX-XXXXXXXXX.ap-northeast-2.elb.amazonaws.com",
                        "EvaluateTargetHealth": true,
                        "HostedZoneId": "ZWKZPGTI48KDX"
                    }
                }
            },
            {
                "Action": "CREATE",
                "ResourceRecordSet": {
                    "Name": "www.yourdomain.com",
                    "Type": "A",
                    "AliasTarget": {
                        "DNSName": "awseb-AWSEB-XXXXXXXXXXXXXXXX-XXXXXXXXX.ap-northeast-2.elb.amazonaws.com",
                        "EvaluateTargetHealth": true,
                        "HostedZoneId": "ZWKZPGTI48KDX"
                    }
                }
            }
        ]
    }'
```

### 5.4 배포 및 확인

#### 5.4.1 설정 배포

```bash
# HTTPS 설정 배포
eb deploy production --timeout 20

# 배포 상태 확인
eb status production
eb health production
```

#### 5.4.2 HTTPS 동작 확인

```bash
# HTTP 접속 시 HTTPS로 리다이렉트 확인
curl -I http://yourdomain.com

# HTTPS 접속 확인
curl -I https://yourdomain.com

# SSL 인증서 정보 확인
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com

# 보안 헤더 확인 (추가 설정한 경우)
curl -I https://yourdomain.com | grep -E "(Strict-Transport|X-Frame|X-Content)"
```

#### 5.4.3 ALB 리스너 확인

```bash
# ALB 리스너 목록 확인
aws elbv2 describe-listeners \
    --load-balancer-arn $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].LoadBalancerArn' --output text)

# HTTP 리다이렉트 규칙 확인
aws elbv2 describe-rules \
    --listener-arn $(aws elbv2 describe-listeners --load-balancer-arn YOUR-ALB-ARN --query 'Listeners[?Port==`80`].ListenerArn' --output text)
```

### 5.5 고급 HTTPS 설정 (선택사항)

#### 5.5.1 보안 헤더 추가

**.ebextensions/07-security-headers.config:**

```yaml
####################################################################################################
#### Security Headers Configuration
#### HSTS, CSP 등 보안 헤더 추가 (Nginx 기반 플랫폼용)
####################################################################################################

files:
  '/etc/nginx/conf.d/security-headers.conf':
    mode: '000644'
    owner: root
    group: root
    content: |
      # Security Headers
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
      add_header X-Frame-Options DENY always;
      add_header X-Content-Type-Options nosniff always;
      add_header Referrer-Policy strict-origin-when-cross-origin always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;

container_commands:
  01_reload_nginx:
    command: 'service nginx reload'
    leader_only: true
```

#### 5.5.2 다중 도메인 지원

**.ebextensions/08-multi-domain.config:**

```yaml
####################################################################################################
#### Multi-Domain Support
#### 여러 도메인에서 동일한 애플리케이션 접근 허용
####################################################################################################

Resources:
  AWSEBV2LoadBalancerListenerRuleAdditional:
    Type: AWS::ElasticLoadBalancingV2::ListenerRule
    Properties:
      Actions:
        - Type: forward
          TargetGroupArn:
            Ref: AWSEBV2LoadBalancerTargetGroup
      Conditions:
        - Field: host-header
          Values:
            - api.yourdomain.com
            - admin.yourdomain.com
            - staging.yourdomain.com
      ListenerArn:
        Ref: AWSEBV2LoadBalancerListener443
      Priority: 10
```

### 5.6 HTTPS 설정 확인 스크립트

**check-https.sh:**

```bash
#!/bin/bash

DOMAIN="yourdomain.com"
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔐 HTTPS 설정 확인 중...${NC}"
echo "=================================="

# 1. HTTP → HTTPS 리다이렉트 확인
echo -e "\n1. HTTP → HTTPS 리다이렉트 확인"
HTTP_RESPONSE=$(curl -s -I http://$DOMAIN | head -n 1)
if [[ $HTTP_RESPONSE == *"301"* || $HTTP_RESPONSE == *"302"* ]]; then
    echo -e "${GREEN}✅ HTTP 리다이렉트 정상${NC}"
    curl -s -I http://$DOMAIN | grep -i "location:"
else
    echo -e "${RED}❌ HTTP 리다이렉트 실패${NC}"
    echo "응답: $HTTP_RESPONSE"
fi

# 2. HTTPS 연결 확인
echo -e "\n2. HTTPS 연결 확인"
if curl -s -I https://$DOMAIN > /dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTPS 연결 정상${NC}"
    curl -s -I https://$DOMAIN | head -n 1
else
    echo -e "${RED}❌ HTTPS 연결 실패${NC}"
fi

# 3. SSL 인증서 확인
echo -e "\n3. SSL 인증서 확인"
CERT_INFO=$(echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SSL 인증서 정상${NC}"
    echo "$CERT_INFO"
else
    echo -e "${RED}❌ SSL 인증서 확인 실패${NC}"
fi

# 4. ALB 리스너 확인
echo -e "\n4. ALB 리스너 확인"
ALB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].LoadBalancerArn' --output text 2>/dev/null)
if [ ! -z "$ALB_ARN" ]; then
    echo -e "${GREEN}✅ ALB 발견${NC}"
    aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[*].{Port:Port,Protocol:Protocol}' --output table
else
    echo -e "${RED}❌ ALB를 찾을 수 없음${NC}"
fi

# 5. 상세 SSL 테스트 링크
echo -e "\n5. 상세 SSL 테스트"
echo "🔗 https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"

echo -e "\n${GREEN}✅ HTTPS 설정 확인 완료!${NC}"
```

### 5.7 통합 배포 스크립트 업데이트

**deploy-prod.sh (HTTPS 확인 포함):**

```bash
#!/bin/bash
set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}🎉 Production 환경 배포 (rel 브랜치)${NC}"
echo "=================================="

# Git 브랜치 확인
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "rel" ]; then
    echo -e "${RED}❌ 현재 브랜치: $CURRENT_BRANCH${NC}"
    echo "Production 배포는 rel 브랜치에서만 가능합니다."
    exit 1
fi

# 메시지 설정
MESSAGE=${1:-"Production deployment $(date '+%Y-%m-%d %H:%M:%S')"}

echo -e "${RED}🚨 PRODUCTION 환경에 배포합니다! 🚨${NC}"
echo "메시지: $MESSAGE"
echo ""
read -p "정말로 프로덕션에 배포하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "배포가 취소되었습니다."
    exit 0
fi

# 배포
echo -e "${BLUE}🚀 프로덕션 배포 시작...${NC}"
eb deploy production --message "$MESSAGE" --timeout 20

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 Production 배포 완료!${NC}"

    # HTTPS 설정 확인 추가
    echo -e "${BLUE}🔐 HTTPS 설정 확인 중...${NC}"
    if [ -f "./check-https.sh" ]; then
        chmod +x ./check-https.sh
        ./check-https.sh
    else
        echo "check-https.sh 파일이 없어 HTTPS 확인을 건너뜁니다."
    fi

    eb health production
    echo ""
    echo "🌐 Production URLs:"
    eb status production | grep CNAME
    echo "🔒 HTTPS URL: https://yourdomain.com"
    echo ""
    echo -e "${GREEN}🎊 모든 팀원에게 배포 완료를 알려주세요! 🎊${NC}"
else
    echo "❌ 배포 실패"
    exit 1
fi
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

### 6.2 Makefile (브랜치별 배포 지원)

```makefile
# Makefile (브랜치 전략 지원)
.PHONY: help deploy-dev deploy-prod status-all health-all logs-all

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
	@echo "  $(GREEN)make deploy-prod$(NC)     - Production 환경 배포 (rel 브랜치)"
	@echo ""
	@echo "HTTPS 확인:"
	@echo "  $(GREEN)make check-https$(NC)     - HTTPS 설정 확인"
	@echo ""
	@echo "모니터링 명령어:"
	@echo "  $(GREEN)make status-all$(NC)      - 모든 환경 상태 확인"
	@echo "  $(GREEN)make health-all$(NC)      - 모든 환경 헬스 체크"
	@echo "  $(GREEN)make logs-dev$(NC)        - Development 로그"
	@echo "  $(GREEN)make logs-prod$(NC)       - Production 로그"

# 배포 명령어
deploy-dev:
	@echo "$(BLUE)🚀 Development 환경 배포$(NC)"
	@./deploy-dev.sh "$(MSG)"

deploy-prod:
	@echo "$(RED)🎉 Production 환경 배포$(NC)"
	@./deploy-rel.sh "$(MSG)"

# HTTPS 확인
check-https:
	@echo "$(BLUE)🔐 HTTPS 설정 확인$(NC)"
	@./check-https.sh

# 상태 확인
status-all:
	@echo "$(BLUE)📊 모든 환경 상태 확인$(NC)"
	@eb status development 2>/dev/null || echo "Development 환경 없음"
	@eb status production 2>/dev/null || echo "Production 환경 없음"

health-all:
	@echo "$(BLUE)🏥 모든 환경 헬스 체크$(NC)"
	@eb health development 2>/dev/null || echo "Development 환경 없음"
	@eb health production 2>/dev/null || echo "Production 환경 없음"
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
    echo "3️⃣  프로덕션 배포:"
    echo "   # dev → rel PR 생성 및 머지"
    echo "   # PR 머지 후 자동으로 Production 환경에 배포됨"
    echo "   # 또는 수동 배포:"
    echo "   git checkout rel"
    echo "   make deploy-prod"
    echo ""
    echo "4️⃣  HTTPS 확인:"
    echo "   make check-https"
    echo ""
    echo -e "${YELLOW}💡 유용한 명령어:${NC}"
    echo "   make help              # 모든 명령어 보기"
    echo "   make status-all        # 모든 환경 상태 확인"
    echo "   make health-all        # 모든 환경 헬스 체크"
    echo "   make check-https       # HTTPS 설정 확인"
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
                make deploy-prod
                ;;
            *)
                echo -e "${RED}❌ 현재 브랜치($CURRENT_BRANCH)에서는 배포할 수 없습니다.${NC}"
                echo "dev(Development), rel(Production) 브랜치에서만 배포 가능합니다."
                ;;
        esac
        ;;
    "https")
        make check-https
        ;;
    *)
        echo "사용법: $0 {help|feature|deploy|https}"
        echo ""
        echo "  help     - 워크플로우 가이드 표시"
        echo "  feature  - 새 기능 브랜치 생성"
        echo "  deploy   - 현재 브랜치에 맞는 환경에 배포"
        echo "  https    - HTTPS 설정 확인"
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

**Production 환경 테스트:**

```bash
# rel 브랜치에서 배포
git checkout rel
make deploy-prod

# 상태 확인
eb status production
eb health production

# HTTPS 확인
make check-https
```

### 7.3 HTTPS 설정 검증

```bash
# 1. ALB 리스너 확인
aws elbv2 describe-listeners \
    --load-balancer-arn $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].LoadBalancerArn' --output text)

# 2. HTTP → HTTPS 리다이렉트 테스트
curl -I http://yourdomain.com

# 3. HTTPS 접속 테스트
curl -I https://yourdomain.com

# 4. SSL 인증서 정보 확인
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com

# 5. 통합 확인 스크립트
./check-https.sh
```

### 7.4 GitHub Actions 워크플로우 테스트

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
# 2. PR 머지 시 자동으로 Production 환경에 배포됨
# 3. 프로덕션 테스트 및 HTTPS 확인
make check-https
```

---

## 🎯 8단계: 최종 설정 완료

### 8.1 브랜치별 환경 매핑

**환경 구성:**

```yaml
Branches → Environments:
  feature/* → 로컬 개발 (Docker)
  dev       → Development (EB: development + ALB)
  rel       → Production (EB: production + ALB + HTTPS) ← 최종 배포
  main      → Archive (아카이브용)

Deployment Triggers:
  PR → dev: Development 자동 배포
  PR → rel: Production 자동 배포 + Release 생성 + HTTPS (최종)
  main: 아카이브용 (수동 실행만)

HTTPS 지원:
  모든 환경에 Application Load Balancer 포함
  Production 환경에 HTTPS 완전 적용
  SSL 인증서 자동 갱신 (ACM)
```

### 8.2 환경별 설정 차이점

**Development (.ebextensions/dev-specific.config):**

```yaml
option_settings:
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.micro
  aws:elasticbeanstalk:environment:
    EnvironmentType: LoadBalanced
    LoadBalancerType: application
  aws:autoscaling:asg:
    MinSize: 1
    MaxSize: 1
  aws:elasticbeanstalk:application:environment:
    NODE_ENV: development
    LOG_LEVEL: debug
```

**Production (.ebextensions/prod-specific.config):**

```yaml
option_settings:
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.medium
  aws:elasticbeanstalk:environment:
    EnvironmentType: LoadBalanced
    LoadBalancerType: application
  aws:autoscaling:asg:
    MinSize: 2
    MaxSize: 5
  aws:elasticbeanstalk:application:environment:
    NODE_ENV: production
    LOG_LEVEL: warn
  aws:elbv2:listener:443:
    ListenerEnabled: 'true'
    Protocol: HTTPS
    SSLCertificateArns: arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID
    SSLPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06
```

---

## 📋 완료 체크리스트

### 기본 설정

- [ ] AWS 계정 및 IAM 사용자 생성
- [ ] **IAMFullAccess 정책 추가** (중요!)
- [ ] AWS CLI 및 EB CLI 설치
- [ ] 필수 서비스 롤 생성 (선택사항)
- [ ] NestJS 프로젝트 생성
- [ ] Dockerfile 및 .dockerignore 작성
- [ ] .ebextensions 폴더 설정 (ALB + 서비스 롤 포함)

### 브랜치 및 환경 설정

- [ ] dev, rel, main 브랜치 생성
- [ ] GitHub 브랜치 보호 규칙 설정
- [ ] Development 환경 생성 (ALB 포함)
- [ ] Production 환경 생성 (ALB 포함)

### HTTPS 설정 (AWS 공식 문서 기반)

- [ ] Route 53 도메인 확인
- [ ] ACM SSL 인증서 요청
- [ ] DNS 검증 레코드 추가
- [ ] 인증서 검증 완료 확인
- [ ] `.ebextensions/05-https-*.config` 파일 생성 (올바른 방법)
- [ ] HTTPS 리스너 설정 (443 포트)
- [ ] HTTP → HTTPS 리다이렉트 설정
- [ ] Route 53 A 레코드 (Alias) 생성
- [ ] 올바른 ALB Hosted Zone ID 사용

### CI/CD 파이프라인

- [ ] GitHub Secrets 설정
- [ ] deploy-dev.yml 워크플로우 설정
- [ ] deploy-rel.yml 워크플로우 설정 (Production 배포용)
- [ ] deploy-production.yml 워크플로우 설정 (아카이브용)

### 배포 스크립트 및 도구

- [ ] deploy-dev.sh 스크립트 생성
- [ ] deploy-rel.sh 스크립트 생성 (HTTPS 확인 포함)
- [ ] check-https.sh 스크립트 생성
- [ ] Makefile 설정 (브랜치별 명령어)
- [ ] workflow.sh 헬퍼 스크립트 생성

### 최종 확인

- [ ] 모든 환경 정상 배포 확인
- [ ] 헬스체크 응답 확인 (/health)
- [ ] GitHub PR 워크플로우 테스트
- [ ] **HTTP → HTTPS 리다이렉트 동작 확인**
- [ ] **HTTPS 접속 정상 확인**
- [ ] **SSL 인증서 정보 확인**
- [ ] ALB 리스너 정상 동작 확인
- [ ] 브랜치별 자동 배포 확인

---

## 🚨 트러블슈팅 (HTTPS 관련 추가)

### HTTPS 관련 문제

#### 1. HTTPS 리스너 생성 실패

```bash
# 오류: "A listener with port 443 already exists"
# 해결: 콘솔에서 생성된 리스너와 충돌

# 기존 리스너 확인
aws elbv2 describe-listeners \
    --load-balancer-arn $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].LoadBalancerArn' --output text)

# 해결방법 1: option_settings만 사용 (리스너가 이미 있는 경우)
# .ebextensions/05-https-existing.config
option_settings:
  aws:elbv2:listener:443:
    ListenerEnabled: 'true'
    Protocol: HTTPS
    SSLCertificateArns: arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID

# 해결방법 2: 기존 리스너 삭제 후 재생성
aws elbv2 delete-listener --listener-arn EXISTING-LISTENER-ARN
```

#### 2. SSL 인증서 오류

```bash
# 오류: "Certificate not found" 또는 "Invalid certificate ARN"

# 인증서 ARN 재확인
aws acm list-certificates --region ap-northeast-2 \
    --query 'CertificateSummaryList[*].{Domain:DomainName,Arn:CertificateArn,Status:Status}'

# 인증서 상태 확인 (ISSUED 여야 함)
aws acm describe-certificate \
    --certificate-arn arn:aws:acm:ap-northeast-2:YOUR-ACCOUNT:certificate/YOUR-CERT-ID

# 다른 리전에 인증서가 있는지 확인
aws acm list-certificates --region us-east-1
```

#### 3. HTTP 리다이렉트가 작동하지 않음

```bash
# 원인: Classic Load Balancer 사용 중
# 확인방법
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].Type'

# 해결: Application Load Balancer로 환경 재생성
eb create production-new \
    --elb-type application \
    --instance_type t3.medium
```

#### 4. Route 53 도메인 연결 실패

```bash
# 오류: "InvalidChangeBatch" 또는 "Alias target does not exist"

# ALB DNS 이름 정확히 확인
ALB_DNS=$(eb status production | grep CNAME | awk '{print $2}')
echo "ALB DNS: $ALB_DNS"

# 올바른 Hosted Zone ID 사용 (리전별)
# 서울(ap-northeast-2): ZWKZPGTI48KDX
# 확인 방법:
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].CanonicalHostedZoneId'
```

#### 5. Mixed Content 오류 (HTTPS에서 HTTP 리소스 로드)

```bash
# 해결: 애플리케이션에서 HTTPS 감지 설정
# src/main.ts에 추가
app.set('trust proxy', 1); // ALB 뒤에서 실행되므로

# 또는 Express.js의 경우
app.use((req, res, next) => {
  if (req.header('x-forwarded-proto') !== 'https') {
    res.redirect(`https://${req.header('host')}${req.url}`);
  } else {
    next();
  }
});
```

### ALB 및 HTTPS 관련

#### 1. ALB 생성 확인

```bash
# ALB 목록 확인
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].{Name:LoadBalancerName,DNS:DNSName,State:State,Type:Type}'

# ALB 타겟 그룹 상태 확인
aws elbv2 describe-target-health \
    --target-group-arn $(aws elbv2 describe-target-groups --query 'TargetGroups[0].TargetGroupArn' --output text)
```

#### 2. SSL Policy 업데이트

```bash
# 최신 SSL 정책으로 업데이트
# .ebextensions/ssl-policy-update.config
option_settings:
  aws:elbv2:listener:443:
    SSLPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06

# 또는 CLI로 직접 업데이트
aws elbv2 modify-listener \
    --listener-arn YOUR-LISTENER-ARN \
    --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06
```

#### 3. HTTPS 헬스체크 설정

```bash
# HTTPS 엔드포인트로 헬스체크 변경
# .ebextensions/https-health.config
option_settings:
  aws:elasticbeanstalk:environment:process:default:
    Port: 8080
    Protocol: HTTP
    HealthCheckPath: /health
    # ALB는 백엔드와 HTTP로 통신하므로 Protocol은 HTTP 유지
```

### 브랜치 전략 관련

#### 1. PR 자동 배포가 안되는 경우

```bash
# GitHub Actions 워크플로우 파일 확인
ls -la .github/workflows/

# 워크플로우 실행 로그 확인 (GitHub Actions 탭에서)
# 일반적인 원인:
# - AWS 자격증명 오류
# - 브랜치 보호 규칙 충돌
# - EB 환경 이름 불일치

# Secrets 재설정
# GitHub Repository → Settings → Secrets and variables → Actions
```

#### 2. 잘못된 브랜치에서 배포 시도

```bash
# 현재 브랜치 확인
git branch --show-current

# 올바른 브랜치로 전환
make switch-dev    # dev 브랜치로
make switch-rel    # rel 브랜치로
make switch-main   # main 브랜치로

# 브랜치 보호 설정으로 강제 차단
```

#### 3. 환경별 설정 차이로 인한 오류

```bash
# 환경별 환경변수 확인
eb printenv development
eb printenv production

# 환경별 설정 파일 분리
# .ebextensions/dev-specific.config (Development용)
# .ebextensions/prod-specific.config (Production용)
```

### 성능 및 모니터링

#### 1. ALB 접속 로그 활성화

```bash
# .ebextensions/alb-logs.config
option_settings:
  aws:elbv2:loadbalancer:
    AccessLogsS3Enabled: true
    AccessLogsS3Bucket: my-app-alb-logs
    AccessLogsS3Prefix: production

# S3 버킷 생성
aws s3 mb s3://my-app-alb-logs
```

#### 2. CloudWatch 메트릭 설정

```bash
# ALB 메트릭 확인
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB \
    --metric-name RequestCount \
    --dimensions Name=LoadBalancer,Value=app/awseb-AWSEB-XXX/XXX \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Sum
```

---

## 🎉 완료!

이제 **AWS 공식 문서 기반의 완전한 브랜치 전략 + NestJS + Docker + Elastic Beanstalk + ALB + HTTPS 지원 + CI/CD** 환경이 구축되었습니다!

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
# PR 머지 시 자동 배포됨 (ALB 포함)
# 또는 수동: make deploy-dev
```

**3. 프로덕션 배포:**

```bash
# dev → rel PR 생성 및 머지
# PR 머지 시 자동 배포됨 + Release 생성 + HTTPS 활성화
# 또는 수동: make deploy-prod
```

**4. HTTPS 확인:**

```bash
make check-https
./workflow.sh https
```

### 📱 유용한 명령어들

```bash
# 전체 상황 파악
make help
make status-all
make health-all

# HTTPS 관련
make check-https
curl -I https://yourdomain.com

# 브랜치별 배포
make deploy-dev MSG="새 기능 테스트"
make deploy-prod MSG="v1.2.0 릴리즈"

# 워크플로우 도움말
./workflow.sh help

# ALB 및 HTTPS 상태 확인
aws elbv2 describe-listeners --load-balancer-arn $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `awseb`)].LoadBalancerArn' --output text)
```

### 🔒 HTTPS 완전 활성화 확인

```bash
# 1. HTTP → HTTPS 리다이렉트 확인
curl -I http://yourdomain.com
# Expected: 301 Moved Permanently, Location: https://yourdomain.com

# 2. HTTPS 접속 확인
curl -I https://yourdomain.com
# Expected: 200 OK

# 3. SSL 등급 확인
# https://www.ssllabs.com/ssltest/analyze.html?d=yourdomain.com

# 4. 통합 확인
./check-https.sh
```

### 🎯 핵심 개선사항 (AWS 공식 문서 기반)

**✅ 올바른 HTTPS 설정:**

- AWS 공식 권장 방법 사용
- `option_settings`와 `Resources` 올바른 조합
- Classic LB 대신 ALB 전용 설정
- 최신 TLS 1.3 보안 정책

**✅ 완전한 브랜치 전략:**

- feature → dev → rel 플로우
- 자동화된 배포 파이프라인
- 환경별 설정 분리
- HTTPS 배포 후 자동 검증

**✅ 엔터프라이즈급 설정:**

- 고가용성 Production 환경
- 포괄적인 모니터링
- 보안 헤더 설정
- 자동 SSL 인증서 갱신

완벽한 엔터프라이즈급 개발 환경이 완성되었습니다! 🎊

**주요 특징:**

- ✅ AWS 공식 문서 기반 HTTPS 설정
- ✅ 모든 환경에 ALB 포함
- ✅ 자동 HTTP → HTTPS 리다이렉트
- ✅ 브랜치 전략 기반 자동 배포
- ✅ 고가용성 프로덕션 환경
- ✅ 완전 자동화된 CI/CD 파이프라인
- ✅ 포괄적인 모니터링 및 알람
