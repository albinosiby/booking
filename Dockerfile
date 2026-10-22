# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS node-base
ENV NEXT_TELEMETRY_DISABLED=1

FROM node-base AS landing-build
WORKDIR /build/landing-page
COPY landing-page/package.json landing-page/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY landing-page/ ./
RUN npm run build

FROM node-base AS booking-build
WORKDIR /build/booking-website
COPY booking-website/package.json booking-website/package-lock.json ./
RUN npm ci --no-audit --no-fund
# Order compiler stages to avoid running three Next builds at the same time.
COPY --from=landing-build /build/landing-page/package.json /tmp/landing-build-ready.json
COPY booking-website/ ./
RUN npm run build -- --webpack

FROM node-base AS admin-build
WORKDIR /build/admin-panel
COPY admin-panel/package.json admin-panel/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY --from=booking-build /build/booking-website/package.json /tmp/booking-build-ready.json
COPY admin-panel/ ./
RUN npm run build -- --webpack

FROM debian:bookworm-slim AS flutter-sdk
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.44.1
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" \
    CI=true \
    FLUTTER_SUPPRESS_ANALYTICS=true
RUN flutter --disable-analytics && flutter config --enable-web && flutter precache --web

FROM flutter-sdk AS flutter-build
WORKDIR /build/app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY lib/ ./lib/
COPY web/ ./web/
COPY assets/ ./assets/
COPY analysis_options.yaml ./
COPY --from=admin-build /build/admin-panel/package.json /tmp/admin-build-ready.json
# These are PUBLIC client settings, also available as Railway build variables.
# Server passwords and database/service-role credentials must never be build args.
ARG SUPABASE_URL=https://scwwkaywewecspsrskft.supabase.co
ARG SUPABASE_PUBLISHABLE_KEY=sb_publishable_d6iVFApYyh41BlF9GkTsgw_h0d-chZN
ARG BOOKING_API_BASE_URL=https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api
RUN flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn \
    --base-href /app/ \
    --dart-define=AUTH_PROVIDER=supabase \
    --dart-define=USE_AUTH_EMULATOR=false \
    --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
    --dart-define="SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}" \
    --dart-define="API_URL=${BOOKING_API_BASE_URL%/}/v1"

FROM node-base AS runtime
ENV NODE_ENV=production \
    PORT=8080 \
    BOOKING_APP_URL=/app \
    BOOKING_ROUTING_MODE=path
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates nginx tini \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default
WORKDIR /srv
COPY --from=landing-build --chown=node:node /build/landing-page/out/ ./static/landing/
COPY --from=flutter-build --chown=node:node /build/app/build/web/ ./static/app/
COPY --from=booking-build --chown=node:node /build/booking-website/.next/standalone/ ./booking/
COPY --from=booking-build --chown=node:node /build/booking-website/.next/static/ ./booking/.next/static/
COPY --from=admin-build --chown=node:node /build/admin-panel/.next/standalone/ ./admin/
COPY --from=admin-build --chown=node:node /build/admin-panel/.next/static/ ./admin/.next/static/
COPY --chown=node:node deploy/start.mjs deploy/check-health.mjs deploy/nginx.conf.template deploy/proxy.conf deploy/security-headers.conf ./deploy/
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=8s --start-period=45s --retries=3 \
    CMD ["node", "deploy/check-health.mjs"]
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "deploy/start.mjs"]
