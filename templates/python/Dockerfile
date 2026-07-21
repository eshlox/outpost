# Python project, using uv for envs/deps (fast, reproducible).
#
# outpost starts an EMPTY workspace; you clone your repo and `uv sync` inside.
# Add SYSTEM packages here; Python toolchains live in your project's .venv.
FROM outpost-base:latest

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-dev
# uv (standalone installer); lands in /usr/local/bin so it's on PATH for everyone.
RUN curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
USER ubuntu

# Common dev/server ports (Django 8000, FastAPI/uvicorn 8000, Flower 5555, ...).
EXPOSE 8000

# Backing services run on the HOST engine via `outpost up` - see examples/.
