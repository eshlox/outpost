# Example: a Python service (API + background workers) using uv. FROM outpost-base,
# add only system deps; the Python toolchain lives in your project's .venv (uv sync).
FROM outpost-base:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-dev postgresql-client \
  && rm -rf /var/lib/apt/lists/*
# uv (standalone), into a system path so it's on PATH for everyone.
RUN curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
USER ubuntu

# e.g. API 8000, a worker dashboard (Flower) 5555.
EXPOSE 8000 5555

# Backing services run on the HOST engine (compose.yaml here): db, redis, rabbit,
# mongo, search (Elasticsearch), minio (S3). Reach them from the container by name.
#
# After `outpost setup <name>`:
#   outpost up <name>
#   outpost sh <name>
#   git clone <your repo> /workspace && uv sync
#   uv run <your app>
