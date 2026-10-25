#!/usr/bin/env bash
# Runs on the server. Pulls the new image, restarts, and rolls back if unhealthy.
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
: "${APP_ENV:?APP_ENV is required}"
export HOST_PORT="${HOST_PORT:-3000}"
COMPOSE="docker compose -f docker-compose.prod.yml -p docker-cicd-app-${APP_ENV}"

PREVIOUS_IMAGE="$(cat .current_image 2>/dev/null || true)"

echo "Deploying $IMAGE to $APP_ENV (port $HOST_PORT)"
export IMAGE APP_ENV
$COMPOSE pull
$COMPOSE up -d --remove-orphans

for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${HOST_PORT}/health" >/dev/null 2>&1; then
    echo "$IMAGE" > .current_image
    docker image prune -f >/dev/null
    echo "Deploy succeeded"
    exit 0
  fi
  sleep 2
done

echo "Health check failed"
if [[ -n "$PREVIOUS_IMAGE" ]]; then
  echo "Rolling back to $PREVIOUS_IMAGE"
  IMAGE="$PREVIOUS_IMAGE" $COMPOSE up -d
fi
exit 1
