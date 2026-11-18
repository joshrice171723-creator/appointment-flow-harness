FROM node:22-slim AS frontend
WORKDIR /workspace/frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/src ./src
RUN npm run build

FROM ruby:3.4-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev pkg-config tzdata \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY backend/Gemfile* ./
RUN bundle install
RUN useradd --create-home flow && install -d -o flow -g flow tmp log public
COPY --chown=flow:flow backend/ ./
COPY --chown=flow:flow --from=frontend /workspace/backend/public/ ./public/
COPY --chown=flow:flow docs/ai-harness/quality/ /docs/ai-harness/quality/
USER flow
EXPOSE 8174
CMD ["bundle", "exec", "puma", "-t", "1:5", "-b", "tcp://0.0.0.0:8174"]
