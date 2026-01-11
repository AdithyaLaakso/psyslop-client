#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
docker build -t adithyalaakso/psyslop-client:latest -f ./Dockerfile .
docker push adithyalaakso/psyslop-client
kubectl rollout restart deployment apps-guide -n apps
k9s -n guide -c pods --headless --splashless --context do-nyc1-beebs
