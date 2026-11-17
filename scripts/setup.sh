#!/usr/bin/env bash
# Host preparation: prerequisite checks + generation of the .env file.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v docker >/dev/null || { echo "docker is not installed" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose plugin is missing" >&2; exit 1; }

# SonarQube (Elasticsearch) needs vm.max_map_count >= 262144 on the Docker host
if [ -r /proc/sys/vm/max_map_count ]; then
  current="$(cat /proc/sys/vm/max_map_count)"
  if [ "${current}" -lt 262144 ]; then
    echo "WARNING: vm.max_map_count=${current} (< 262144). Run:"
    echo "  sudo sysctl -w vm.max_map_count=262144"
    echo "  echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-sonarqube.conf"
  fi
fi

if [ -f .env ]; then
  echo ".env already exists - left untouched"
else
  docker_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 999)"
  umask 077
  cat > .env <<ENV
DOCKER_GID=${docker_gid}
SONAR_DB_PASSWORD=$(openssl rand -hex 16)
ENV
  echo ".env created (DOCKER_GID=${docker_gid})"
fi
echo "Next: docker compose up -d --build"
