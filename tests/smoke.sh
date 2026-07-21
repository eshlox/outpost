#!/usr/bin/env bash
# outpost smoke tests: drive bin/outpost with a fake engine (tests/mock-docker) and
# assert name validation, the generated docker run args, host-engine services
# (outpost up), the `outpost projects` config commands, and a clean destroy. No real
# Docker required. Run: bash tests/smoke.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OP="$HERE/../bin/outpost"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export OUTPOST_DIR="$HERE/.."                 # tool repo root (real shared/ + templates/)
export OUTPOST_PROJECTS_DIR="$TMP/projects"   # projects live OUTSIDE the tool repo now
export OUTPOST_ENGINE="$HERE/mock-docker"
export OUTPOST_STATE_DIR="$TMP/state"
export OUTPOST_CONFIG="$TMP/no-such-config"   # don't pick up a real ~/.config/outpost/config
export RUNLOG="$TMP/runlog"
export MOCK_STATE="$TMP/mockstate"; mkdir -p "$MOCK_STATE"   # mock container-existence state
export OUTPOST_SKIP_BRIDGE=1      # no live ssh agent in the test; skip the socat bridge

# A stub project (web) with a Dockerfile and a services compose.
mkdir -p "$OUTPOST_PROJECTS_DIR/web"
echo 'FROM outpost-base:latest'  > "$OUTPOST_PROJECTS_DIR/web/Dockerfile"
printf 'services:\n  db:\n    image: redis\nnetworks:\n  default:\n    name: outpost-web-net\n    external: true\n' > "$OUTPOST_PROJECTS_DIR/web/compose.yaml"

pass=0 fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }
has()    { if grep -qF -- "$2" "$1"; then ok "$3"; else no "$3 (missing: $2)"; fi; }
hasnot() { if grep -qF -- "$2" "$1"; then no "$3 (unexpected: $2)"; else ok "$3"; fi; }

# 0) version + completion (neither needs the engine)
case "$("$OP" version 2>/dev/null)" in outpost\ *) ok "version prints" ;; *) no "version prints" ;; esac
case "$("$OP" completion bash 2>/dev/null)" in *_outpost*complete\ -F*) ok "completion bash emits a script" ;; *) no "completion bash emits a script" ;; esac
if "$OP" completion fish 2>/dev/null; then no "completion rejects unsupported shell"; else ok "completion rejects unsupported shell"; fi

# 1) name validation rejects path traversal, whitespace, and uppercase
if "$OP" setup '../evil' 2>"$TMP/e"; then no "reject ../evil"; else
  grep -q "invalid project name" "$TMP/e" && ok "reject ../evil" || no "reject ../evil (wrong error)"; fi
if "$OP" setup 'bad name' 2>/dev/null; then no "reject whitespace name"; else ok "reject whitespace name"; fi
if "$OP" setup 'MyProj'   2>/dev/null; then no "reject uppercase name"; else ok "reject uppercase name (invalid Docker image)"; fi

# 2) run args: hardened, no caps, no host docker socket, never a nested device
: > "$RUNLOG"; "$OP" setup web >/dev/null 2>&1
has    "$RUNLOG" "--cap-drop ALL"                  "web: cap-drop ALL"
has    "$RUNLOG" "no-new-privileges:true"          "web: no-new-privileges"
has    "$RUNLOG" "--network outpost-web-net"       "web: per-project network"
has    "$RUNLOG" "127.0.0.1::3000/tcp"             "web: EXPOSE published to a dynamic host port"
has    "$RUNLOG" "--pids-limit"                    "web: pids-limit set"
has    "$RUNLOG" "--entrypoint sleep"              "web: entrypoint overridden (survives image ENTRYPOINT)"
hasnot "$RUNLOG" "/dev/fuse"                        "web: no nested device"
hasnot "$RUNLOG" "--cap-add"                        "web: no caps added back"
hasnot "$RUNLOG" "/var/run/docker.sock"            "web: no host docker socket mounted"
has    "$RUNLOG" ":/run/outpost:ro"                 "web: project config dir mounted read-only (tunnels.json)"
# 1.1 regression: the agent-bridge dir must EXIST (and be ours) at `run -d` time, so Docker
# never creates the -v "$AGENT_DIR:/run/agent" bind as root. --no-agent tore the bridge down;
# start_project must have recreated it before the run above.
[ -d "$OUTPOST_STATE_DIR/agents/web/run" ] && ok "web: agent dir recreated before docker run (not root-owned by Docker)" \
  || no "web: agent dir missing at run time (1.1 regression)"

# 2r) read-only rootfs is opt-in: off by default, adds --read-only + tmpfs when OUTPOST_READONLY=1
hasnot "$RUNLOG" "--read-only"                     "web: no read-only rootfs by default"
: > "$RUNLOG"; rm -f "$MOCK_STATE/outpost-web"; OUTPOST_READONLY=1 "$OP" setup web >/dev/null 2>&1
has    "$RUNLOG" "--read-only"                     "web: OUTPOST_READONLY=1 sets a read-only rootfs"
has    "$RUNLOG" "--tmpfs /tmp"                    "web: OUTPOST_READONLY=1 mounts a /tmp tmpfs"

# 3) outpost up runs the project's services on the host engine, on the project network
: > "$RUNLOG"; "$OP" up web >/dev/null 2>&1
has    "$RUNLOG" "compose -p outpost-web"          "up: host-engine compose, project-scoped"
has    "$RUNLOG" "up -d"                           "up: services started detached"

# 3b) outpost up refuses a host-escalating compose (safety lint), override bypasses it
mkdir -p "$OUTPOST_PROJECTS_DIR/danger"
echo 'FROM outpost-base:latest'                                          > "$OUTPOST_PROJECTS_DIR/danger/Dockerfile"
printf 'services:\n  x:\n    image: redis\n    privileged: true\n'       > "$OUTPOST_PROJECTS_DIR/danger/compose.yaml"
if "$OP" up danger 2>"$TMP/lint"; then no "up: refuses privileged compose"; else
  grep -q "host-escalating" "$TMP/lint" && ok "up: refuses privileged compose" || no "up: refuses privileged compose (wrong error)"; fi
if OUTPOST_ALLOW_UNSAFE_COMPOSE=1 "$OP" up danger >/dev/null 2>&1; then ok "up: OUTPOST_ALLOW_UNSAFE_COMPOSE overrides the lint"; else no "up: override flag works"; fi

# 3c) the bind lint refuses a host path OUTSIDE the project dir (e.g. ~/.ssh), but
# allows a source INSIDE it (the user's own config beside the Dockerfile).
mkdir -p "$OUTPOST_PROJECTS_DIR/binder"
echo 'FROM outpost-base:latest'                                          > "$OUTPOST_PROJECTS_DIR/binder/Dockerfile"
printf 'services:\n  x:\n    image: redis\n    volumes:\n      - type: bind\n        source: /home/someone/.ssh\n        target: /keys\n' > "$OUTPOST_PROJECTS_DIR/binder/compose.yaml"
if "$OP" up binder 2>"$TMP/bind"; then no "up: refuses host bind mount outside project dir"; else
  grep -q "host path mount/secret/context: /home/someone/.ssh" "$TMP/bind" && ok "up: refuses host bind mount outside project dir" || no "up: refuses host bind (wrong error)"; fi
printf 'services:\n  x:\n    image: redis\n    volumes:\n      - type: bind\n        source: %s/seed\n        target: /seed\n' "$OUTPOST_PROJECTS_DIR/binder" > "$OUTPOST_PROJECTS_DIR/binder/compose.yaml"
if "$OP" up binder >/dev/null 2>&1; then ok "up: allows a bind whose source is inside the project dir"; else no "up: allows in-project bind"; fi
# 3c-i) a project-local SYMLINK that points at a host secret must NOT slip past the
# prefix check - realpath resolution catches it.
ln -sfn /etc "$OUTPOST_PROJECTS_DIR/binder/evil"
printf 'services:\n  x:\n    image: redis\n    volumes:\n      - type: bind\n        source: %s/evil\n        target: /x\n' "$OUTPOST_PROJECTS_DIR/binder" > "$OUTPOST_PROJECTS_DIR/binder/compose.yaml"
if "$OP" up binder >/dev/null 2>&1; then no "up: refuses in-project symlink to a host path"; else ok "up: refuses in-project symlink to a host path"; fi
# 3c-ii) a build context OUTSIDE the project dir is refused too (COPY-from-host vector).
printf 'services:\n  x:\n    build:\n      context: /etc\n' > "$OUTPOST_PROJECTS_DIR/binder/compose.yaml"
if "$OP" up binder >/dev/null 2>&1; then no "up: refuses out-of-project build context"; else ok "up: refuses out-of-project build context"; fi
# 3c-iii) an additional_contexts entry pointing at a host path is a COPY vector too.
printf 'services:\n  x:\n    build:\n      context: %s\n      additional_contexts:\n        seed: /root\n' "$OUTPOST_PROJECTS_DIR/binder" > "$OUTPOST_PROJECTS_DIR/binder/compose.yaml"
if "$OP" up binder >/dev/null 2>&1; then no "up: refuses additional_contexts host path"; else ok "up: refuses additional_contexts host path"; fi

# 3d) lint holes that a text denylist missed before (regression guards for these fixes):
D="$OUTPOST_PROJECTS_DIR/danger/compose.yaml"
# cap_add: ALL grants every capability but isn't a named token like SYS_ADMIN.
printf 'services:\n  x:\n    image: redis\n    cap_add:\n      - ALL\n' > "$D"
if "$OP" up danger 2>"$TMP/l"; then no "up: refuses cap_add: ALL"; else
  grep -q "cap_add" "$TMP/l" && ok "up: refuses cap_add: ALL" || no "up: refuses cap_add: ALL (wrong error)"; fi
# cap_drop: ALL is GOOD practice and must NOT be flagged (no false positive).
printf 'services:\n  x:\n    image: redis\n    cap_drop:\n      - ALL\n' > "$D"
if "$OP" up danger >/dev/null 2>&1; then ok "up: allows cap_drop: ALL (no false positive)"; else no "up: allows cap_drop: ALL"; fi
# Joining another container's namespace (not just the host's) is an escape vector.
printf 'services:\n  x:\n    image: redis\n    pid: "container:victim"\n' > "$D"
if "$OP" up danger >/dev/null 2>&1; then no "up: refuses container-namespace join"; else ok "up: refuses container-namespace join"; fi
# volumes_from borrows another container's volumes.
printf 'services:\n  x:\n    image: redis\n    volumes_from:\n      - other\n' > "$D"
if "$OP" up danger >/dev/null 2>&1; then no "up: refuses volumes_from"; else ok "up: refuses volumes_from"; fi
# A published host port bypasses UFW (Docker's own DNAT rules) and is never needed here.
printf 'services:\n  x:\n    image: redis\n    ports:\n      - mode: ingress\n        target: 6379\n        published: "6379"\n        protocol: tcp\n' > "$D"
if "$OP" up danger >/dev/null 2>&1; then no "up: refuses published host port"; else ok "up: refuses published host port"; fi
# 1.2: raw host devices handed to a service (list form the path-scanner never matched).
printf 'services:\n  x:\n    image: redis\n    devices:\n      - /dev/mem:/dev/mem\n' > "$D"
if "$OP" up danger 2>"$TMP/l"; then no "up: refuses devices:"; else
  grep -q "devices:" "$TMP/l" && ok "up: refuses raw host devices (list form)" || no "up: refuses devices: (wrong error)"; fi
# 1.2: device_cgroup_rules is the same class.
printf 'services:\n  x:\n    image: redis\n    device_cgroup_rules:\n      - "c 1:3 rwm"\n' > "$D"
if "$OP" up danger >/dev/null 2>&1; then no "up: refuses device_cgroup_rules"; else ok "up: refuses device_cgroup_rules"; fi
# 1.2: env_file reads a HOST file into the service env; a path OUTSIDE the project dir is
# refused (compose merges env_file away, so this is scanned from the RAW file).
printf 'services:\n  x:\n    image: redis\n    env_file: /root/.env\n' > "$D"
if "$OP" up danger 2>"$TMP/l"; then no "up: refuses out-of-project env_file"; else
  grep -q "env_file host path" "$TMP/l" && ok "up: refuses env_file outside the project dir" || no "up: refuses env_file (wrong error)"; fi
# ...but an env_file INSIDE the project dir is fine (the user's own config beside the compose).
printf 'services:\n  x:\n    image: redis\n    env_file:\n      - ./service.env\n' > "$D"
if "$OP" up danger >/dev/null 2>&1; then ok "up: allows an env_file inside the project dir"; else no "up: allows in-project env_file"; fi

# 4) outpost ports shows the dynamic host port + an ssh -L (web exists from step 2)
ports_out="$("$OP" ports web 2>/dev/null || true)"
case "$ports_out" in
  *"ssh -A -L 3000:localhost:49153"*) ok "ports: shows host port + ssh -L" ;;
  *) no "ports: shows host port + ssh -L (got: $ports_out)" ;;
esac

# 5) update swap happy path: old container exists, new one comes up, exit clean
: > "$RUNLOG"
if "$OP" update web >/dev/null 2>&1; then ok "update web exits clean (swap succeeded)"; else no "update web exits clean"; fi
has "$RUNLOG" "--name outpost-web" "update: recreated the container"

# 5r) base content hash (drives update's base-rebuild skip) is deterministic + a 64-hex digest
# shellcheck source=/dev/null
bch() { ( source "$OP" 2>/dev/null; base_content_hash 2>/dev/null ); }
h1="$(bch)"; h2="$(bch)"
if [ -n "$h1" ] && [ "$h1" = "$h2" ] && [ "${#h1}" -eq 64 ]; then ok "base_content_hash deterministic (64-hex)"; else no "base_content_hash deterministic/hex (got '$h1' vs '$h2')"; fi

# 5b) exec runs a one-off command in the (now running) container
if "$OP" exec web echo hi >/dev/null 2>&1; then ok "exec runs a command in the container"; else no "exec runs a command in the container"; fi
if "$OP" exec web 2>/dev/null; then no "exec requires a command"; else ok "exec requires a command"; fi

# 5c) status: detailed (one project) reports the core fields; summary (no arg) lists projects
status_out="$("$OP" status web 2>/dev/null)"
case "$status_out" in *"container:"*) ok "status <project> reports container state" ;; *) no "status <project> reports container state (got: $status_out)" ;; esac
case "$status_out" in *"ports:"*)     ok "status <project> reports ports" ;;           *) no "status <project> reports ports" ;; esac
case "$("$OP" status 2>/dev/null)" in *web*) ok "status (no arg) lists projects" ;; *) no "status (no arg) lists projects" ;; esac

# 5d) restart: stop then start (web stays present + running afterwards)
if "$OP" restart web >/dev/null 2>&1 && [ -f "$MOCK_STATE/outpost-web" ]; then ok "restart web stop+starts the container"; else no "restart web stop+starts the container"; fi

# 5e) cp reverse: a ':'-prefixed source pulls OUT of the box; mixed non-':' source is rejected
if "$OP" cp web :/workspace/out.txt "$TMP/pulled" >/dev/null 2>&1; then ok "cp reverse (:/box/path -> host) works"; else no "cp reverse works"; fi
if "$OP" cp web :/workspace/a /not-a-colon-src "$TMP/d" 2>"$TMP/cpr"; then no "cp reverse rejects a non-':' source"; else
  grep -q "must be a container path" "$TMP/cpr" && ok "cp reverse rejects a non-':' source" || no "cp reverse rejects non-':' (wrong error)"; fi

# 5f) setup --new: one-shot scaffold-then-setup for a not-yet-existing project
if "$OP" setup fresh --new -t node >/dev/null 2>&1 && [ -f "$OUTPOST_PROJECTS_DIR/fresh/Dockerfile" ]; then
  ok "setup --new scaffolds a new project then sets it up"; else no "setup --new scaffolds + sets up"; fi

# 6) projects: new/edit/ls/templates/path against the real templates dir
if "$OP" projects new api -t node >/dev/null 2>&1 && [ -f "$OUTPOST_PROJECTS_DIR/api/Dockerfile" ]; then
  ok "projects new scaffolds from a template"; else no "projects new scaffolds from a template"; fi
if "$OP" projects new api 2>/dev/null; then no "projects new refuses an existing name"; else ok "projects new refuses an existing name"; fi
# projects rm validates the name BEFORE building an rm -rf path (no dir escape)
if "$OP" projects rm '../evil' 2>"$TMP/pe"; then no "projects rm rejects ../evil"; else
  grep -q "invalid project name" "$TMP/pe" && ok "projects rm rejects ../evil" || no "projects rm rejects ../evil (wrong error)"; fi
case "$("$OP" projects templates 2>/dev/null)" in *minimal*) ok "projects templates lists minimal" ;; *) no "projects templates lists minimal" ;; esac
case "$("$OP" projects path 2>/dev/null)" in "$OUTPOST_PROJECTS_DIR") ok "projects path prints the dir" ;; *) no "projects path prints the dir" ;; esac
VISUAL=true EDITOR=true "$OP" projects edit api Dockerfile >/dev/null 2>&1 && ok "projects edit opens a file" || no "projects edit opens a file"
case "$("$OP" projects ls 2>/dev/null)" in *web*) ok "projects ls lists configured projects" ;; *) no "projects ls lists configured projects" ;; esac
# a trailing '-'/'_' builds an invalid Docker image tag, so the name is rejected
if "$OP" projects new 'trail-' 2>"$TMP/tn"; then no "projects new rejects a trailing '-'"; else
  grep -q "invalid project name" "$TMP/tn" && ok "projects new rejects a trailing '-'" || no "projects new rejects a trailing '-' (wrong error)"; fi

# 6b) projects rm safety. Set up a project that still has a (mock) container.
mkdir -p "$OUTPOST_PROJECTS_DIR/orphan"; echo 'FROM outpost-base:latest' > "$OUTPOST_PROJECTS_DIR/orphan/Dockerfile"
: > "$MOCK_STATE/outpost-orphan"     # pretend a container exists
# Removing just the config would orphan that container (unmanageable afterward): refuse.
if "$OP" projects rm orphan -y 2>"$TMP/orph"; then no "projects rm refuses to orphan a live container"; else
  grep -q "still has a container" "$TMP/orph" && ok "projects rm refuses to orphan a live container" || no "projects rm orphan-guard (wrong error)"; fi
# --destroy must confirm BEFORE destroying: answering 'n' leaves container AND config intact.
printf 'n\n' | "$OP" projects rm orphan --destroy >/dev/null 2>&1
if [ -f "$MOCK_STATE/outpost-orphan" ] && [ -d "$OUTPOST_PROJECTS_DIR/orphan" ]; then
  ok "projects rm --destroy confirms before destroying ('n' keeps everything)"; else
  no "projects rm --destroy destroyed before the prompt"; fi
# --destroy -y removes both the container and the config.
if "$OP" projects rm orphan --destroy -y >/dev/null 2>&1 \
   && [ ! -d "$OUTPOST_PROJECTS_DIR/orphan" ] && [ ! -f "$MOCK_STATE/outpost-orphan" ]; then
  ok "projects rm --destroy -y removes container + config"; else no "projects rm --destroy -y removes both"; fi

# 7) destroy runs cleanly (removes container, volumes, network) and drops the project's
#    compose service volumes too (`down --volumes`), so no service data survives.
: > "$RUNLOG"
if "$OP" destroy web >/dev/null 2>&1; then ok "destroy web exits clean"; else no "destroy web exits clean"; fi
has "$RUNLOG" "down --volumes" "destroy: compose down removes service volumes"

# 8) git safety (real git; identity via env so it's hermetic). These drive `projects
#    sync`, which is independent of the docker engine.
if command -v git >/dev/null 2>&1; then
  export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.com \
         GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.com
  # 8a) A PROJECTS_DIR NESTED inside a parent repo must not be treated as the repo -
  #     `git add -A` would otherwise stage and push the parent's unrelated files.
  PARENT="$TMP/parent"; mkdir -p "$PARENT/sub"; git -C "$PARENT" init -q
  echo outside > "$PARENT/outside.txt"
  echo 'FROM outpost-base:latest' > "$PARENT/sub/Dockerfile"   # PROJECTS_DIR = $PARENT/sub
  if OUTPOST_PROJECTS_DIR="$PARENT/sub" "$OP" projects sync 2>"$TMP/gs"; then
    no "sync refuses a PROJECTS_DIR nested in a parent repo"; else
    grep -q "not a git repo" "$TMP/gs" && ok "sync refuses a PROJECTS_DIR nested in a parent repo" \
      || no "sync nested-repo (wrong error)"; fi
  git -C "$PARENT" diff --cached --quiet && ok "nested sync staged nothing in the parent repo" \
    || no "nested sync staged parent files"

  # 8b) First sync of a fresh repo with a remote must not fail on a premature `git pull`
  #     (no upstream yet); it should commit and establish upstream via `push -u`.
  REMOTE="$TMP/remote.git"; git init -q --bare "$REMOTE"
  PDIR9="$TMP/proj9"; mkdir -p "$PDIR9"
  OUTPOST_PROJECTS_DIR="$PDIR9" "$OP" projects init --remote "$REMOTE" >/dev/null 2>&1
  if OUTPOST_PROJECTS_DIR="$PDIR9" "$OP" projects sync -m first >"$TMP/s9" 2>&1; then
    ok "first sync (no upstream) succeeds"; else no "first sync (no upstream) succeeds ($(cat "$TMP/s9"))"; fi
  grep -q pushed "$TMP/s9" && ok "first sync pushes and sets upstream" || no "first sync pushes"
  # A second sync now has an upstream and still succeeds (the normal pull path).
  mkdir -p "$PDIR9/two"; echo 'FROM outpost-base:latest' > "$PDIR9/two/Dockerfile"
  if OUTPOST_PROJECTS_DIR="$PDIR9" "$OP" projects sync -m second >"$TMP/s9b" 2>&1; then
    ok "second sync (with upstream) succeeds"; else no "second sync succeeds ($(cat "$TMP/s9b"))"; fi
else
  echo "SKIP: git not available - skipping git safety tests"
fi

echo "----"
echo "smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
