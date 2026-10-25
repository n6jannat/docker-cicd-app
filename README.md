# docker-cicd-app

A small Node.js (Express) API with a production Docker image and a **dynamic** GitHub Actions CI/CD pipeline. The pipeline builds and pushes the image to GitHub Container Registry (GHCR) and deploys it to **your local machine** via a self-hosted runner (or to a remote server over SSH).

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

Stages: **plan → test (matrix) → build/push → deploy (local runner or SSH) → health check**.

The server-side `deploy/deploy.sh` checks `/health` after starting the container and **rolls back** to the previous image if the check fails.

## Deploy to your local machine (default)

GitHub can't reach into your computer, so the deploy job runs on a **self-hosted GitHub Actions runner** installed on your machine. The runner connects *out* to GitHub, picks up the deploy job, and runs the container in your local Docker.

| Environment | Trigger | URL |
|---|---|---|
| staging | push to `main` / `develop` | http://localhost:3001 |
| production | tag `v*.*.*` | http://localhost:3000 |

### 1. Install Docker
- **Windows / macOS:** install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and start it. On Windows also install [Git for Windows](https://git-scm.com/download/win), which provides the `bash` the deploy script needs.
- **Linux:** `curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker $USER`, then log out and back in.

Check that it works: `docker run --rm hello-world`

### 2. Install the self-hosted runner
1. On GitHub open **Settings → Actions → Runners → New self-hosted runner** and pick your OS.
2. Run the *Download* and *Configure* commands it shows. When `config` asks for **additional labels**, enter:
   ```
   docker-cicd-app
   ```
3. Start it: `./run.sh` (Windows: `run.cmd`). To keep it running in the background, install it as a service: `sudo ./svc.sh install && sudo ./svc.sh start` (Linux/macOS) or choose "run as service" during config on Windows.

The runner should show as **Idle** on the Runners page.

### 3. Deploy
```bash
git push origin main                 # -> staging    http://localhost:3001
git tag v1.0.0 && git push --tags    # -> production http://localhost:3000
```
You can also re-run a failed run from the Actions tab, or use **Actions → CI/CD → Run workflow**.

Optional repository variable: `HOST_PORT` to override the port.

> **Security:** this repository is **public**. A self-hosted runner executes workflow code on your machine. Deploy jobs only run on pushes, tags and manual runs, never on pull requests. Still, keep the default *Settings → Actions → General → "Require approval for all outside collaborators"* turned on, or make the repository private. Stop the runner when you're not using it.

## Alternative: deploy to a remote server over SSH

Set the repository variable `DEPLOY_TARGET=ssh`. Then on the server run `sudo bash deploy/server-setup.sh`, which installs Docker, compose and curl, creates a `deploy` user in the docker group, and prints an SSH key. Add these to each environment (`staging`, `production`):

- Secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, optional `DEPLOY_PORT`, and `GHCR_PULL_TOKEN` (a PAT with `read:packages`)
- Variables: `APP_URL`, `HOST_PORT`

## Project layout

```
src/                 app.js (routes), server.js (entrypoint + graceful shutdown)
test/                node:test tests
Dockerfile           multi-stage: deps → test → runtime (non-root, healthcheck)
docker-compose.yml   local dev
deploy/              compose file, deploy script (with rollback), server-setup.sh
.github/workflows/   CI/CD pipeline
.github/dependabot.yml
```
