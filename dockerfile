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

# 포트 노출
EXPOSE 8080

# 헬스체크 추가 (선택사항)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node --version || exit 1

# 애플리케이션 시작
CMD ["node", "dist/main"]
