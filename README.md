# docker-cicd-app

A small Node.js (Express) API with a production Docker image and a **dynamic** GitHub Actions CI/CD pipeline. The pipeline builds and pushes the image to GitHub Container Registry (GHCR) and deploys it to a server over SSH with Docker Compose.

## Run locally

```bash
npm install
npm test
npm start                     # http://localhost:3000

# or with Docker
docker compose up --build     # http://localhost:3000
```

Endpoints: `GET /`, `GET /health`, `GET|POST /api/todos`.

## Pipeline (`.github/workflows/ci-cd.yml`)

A `plan` job looks at the event and decides what the rest of the run does:

| Trigger | Node test matrix | Image | Deploy |
|---|---|---|---|
| Pull request | 20, 22, 24 | built + smoke-tested, not pushed | – |
| Push to `main` / `develop` | 22 | pushed as `sha-xxxxxxx`, branch tag | **staging** |
| Tag `v1.2.3` | 20, 22, 24 | pushed as `v1.2.3`, `1.2.3`, `1.2`, `latest` (amd64 + arm64) | **production** |
| Manual (*Run workflow*) | 22 | pushed | the environment you pick |

Stages: **plan → test (matrix) → build/push → deploy → smoke test**.

The server-side `deploy/deploy.sh` checks `/health` after starting the container and **rolls back** to the previous image if the check fails.

## Setup

1. **Push this repo to GitHub.**
2. **Create environments** under *Settings → Environments*: `staging` and `production`. For `production`, add *Required reviewers* so releases need manual approval.
3. **In each environment, add these secrets:**

   | Secret | Description |
   |---|---|
   | `DEPLOY_HOST` | Server IP or hostname |
   | `DEPLOY_USER` | SSH user (must be able to run `docker`) |
   | `DEPLOY_SSH_KEY` | Private SSH key for that user |
   | `DEPLOY_PORT` | *(optional)* SSH port, default 22 |
   | `GHCR_PULL_TOKEN` | *(recommended)* PAT with `read:packages`, so the server can pull the image after the job token expires |

   **And these variables:**

   | Variable | Example |
   |---|---|
   | `APP_URL` | `http://staging.example.com:3001` (used for the smoke test and shown in the deployment) |
   | `HOST_PORT` | `3001` for staging, `80` for production |

4. **Prepare the server.** It needs Docker with the compose plugin, plus `curl`.
5. **Ship:**
   ```bash
   git push origin main             # -> staging
   git tag v1.0.0 && git push --tags  # -> production
   ```

## Project layout

```
src/                 app.js (routes), server.js (entrypoint + graceful shutdown)
test/                node:test tests
Dockerfile           multi-stage: deps → test → runtime (non-root, healthcheck)
docker-compose.yml   local dev
deploy/              compose file + deploy script used on the server
.github/workflows/   CI/CD pipeline
.github/dependabot.yml
```
