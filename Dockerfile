FROM --platform=linux/amd64 node:20-alpine3.17 AS base

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
  
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi


# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN --mount=type=secret,id=NEXTAUTH_URL \
    --mount=type=secret,id=NEXTAUTH_SECRET \
    --mount=type=secret,id=DATABASE_URL \
    --mount=type=secret,id=NEXT_PUBLIC_SITE_URL \
    --mount=type=secret,id=GOOGLE_CLIENT_ID \
    --mount=type=secret,id=GOOGLE_CLIENT_SECRET \
    --mount=type=secret,id=MAXIMUM_PLAYERS_PER_BOARD \
    sh -c 'echo "NEXTAUTH_URL=$(cat /run/secrets/NEXTAUTH_URL)" > .env && \
           echo "NEXTAUTH_SECRET=$(cat /run/secrets/NEXTAUTH_SECRET)" >> .env && \
           echo "DATABASE_URL=$(cat /run/secrets/DATABASE_URL)" >> .env && \
           echo "NEXT_PUBLIC_SITE_URL=$(cat /run/secrets/NEXT_PUBLIC_SITE_URL)" >> .env && \
           echo "GOOGLE_CLIENT_ID=$(cat /run/secrets/GOOGLE_CLIENT_ID)" >> .env && \
           echo "GOOGLE_CLIENT_SECRET=$(cat /run/secrets/GOOGLE_CLIENT_SECRET)" >> .env && \
           echo "MAXIMUM_PLAYERS_PER_BOARD=$(cat /run/secrets/MAXIMUM_PLAYERS_PER_BOARD)" >> .env'

RUN npm run db:generate

RUN npm run build

FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT=3000

ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]