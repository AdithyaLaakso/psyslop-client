#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
docker build --push -t thavlik/psyslop-guide:latest .
kubectl rollout restart deployment apps-guide -n apps
k9s -n guide -c pods --headless --splashless --context do-nyc1-beebs