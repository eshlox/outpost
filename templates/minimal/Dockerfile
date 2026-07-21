# Minimal outpost project: the base image + one exposed port.
#
# A project is just this Dockerfile (FROM outpost-base). Declare everything you need
# here - extra packages, EXPOSE <port>. outpost builds it and starts an EMPTY
# workspace container; you `outpost sh`, then clone your repo and run things inside.
#
# Optional, beside this file (NOT in the workspace): tunnels.json, compose.yaml,
# ports.pin - see the examples/ dir in the outpost repo.
FROM outpost-base:latest

# Your dev server's port. outpost publishes it to a 127.0.0.1 host port
# (`outpost ports <name>` shows it + an ssh -L). EXPOSE several if you need to.
EXPOSE 3000
