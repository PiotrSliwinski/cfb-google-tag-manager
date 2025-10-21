#!/usr/bin/env bash

# Deploy the Server-Side Google Tag Manager container image to Cloud Run.
# Requires the gcloud CLI to be authenticated before invocation.

set -euo pipefail

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud CLI not found in PATH. Install or expose gcloud before running this script." >&2
  exit 1
fi

PROJECT_ID=${PROJECT_ID:-}
REGION=${REGION:-}
SERVICE_NAME=${SERVICE_NAME:-server-side-gtm}
CONTAINER_IMAGE=${CONTAINER_IMAGE:-gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable}
ENV_VARS_FILE=${ENV_VARS_FILE:-config/env.yaml}
MEMORY=${MEMORY:-1Gi}
CPU=${CPU:-1}
MIN_INSTANCES=${MIN_INSTANCES:-0}
MAX_INSTANCES=${MAX_INSTANCES:-3}
ALLOW_UNAUTHENTICATED=${ALLOW_UNAUTHENTICATED:-true}
PORT=${PORT:-8080}
CONCURRENCY=${CONCURRENCY:-}
TIMEOUT=${TIMEOUT:-}
MAX_REQUESTS_PER_CONTAINER=${MAX_REQUESTS_PER_CONTAINER:-}
REVISION_SUFFIX=${REVISION_SUFFIX:-}
TRAFFIC=${TRAFFIC:-}
LABELS=${LABELS:-}
EXECUTION_ENVIRONMENT=${EXECUTION_ENVIRONMENT:-}
CLOUD_RUN_FLAGS=${CLOUD_RUN_FLAGS:-}

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: PROJECT_ID is required." >&2
  exit 1
fi

if [[ -z "$REGION" ]]; then
  echo "ERROR: REGION is required." >&2
  exit 1
fi

if [[ ! -f "$ENV_VARS_FILE" ]]; then
  echo "ERROR: Environment file '$ENV_VARS_FILE' not found. Provide a valid path via ENV_VARS_FILE." >&2
  exit 1
fi

CMD_ARGS=(
  run deploy "$SERVICE_NAME"
  --image "$CONTAINER_IMAGE"
  --platform managed
  --region "$REGION"
  --project "$PROJECT_ID"
  --memory "$MEMORY"
  --cpu "$CPU"
  --min-instances "$MIN_INSTANCES"
  --max-instances "$MAX_INSTANCES"
  --port "$PORT"
  --env-vars-file "$ENV_VARS_FILE"
)

case "${ALLOW_UNAUTHENTICATED,,}" in
  true|"")
    CMD_ARGS+=(--allow-unauthenticated)
    ;;
  false)
    CMD_ARGS+=(--no-allow-unauthenticated)
    ;;
esac

if [[ -n "$CONCURRENCY" ]]; then
  CMD_ARGS+=(--concurrency "$CONCURRENCY")
fi

if [[ -n "$TIMEOUT" ]]; then
  CMD_ARGS+=(--timeout "$TIMEOUT")
fi

if [[ -n "$MAX_REQUESTS_PER_CONTAINER" ]]; then
  CMD_ARGS+=(--max-requests-per-container "$MAX_REQUESTS_PER_CONTAINER")
fi

if [[ -n "$REVISION_SUFFIX" ]]; then
  CMD_ARGS+=(--revision-suffix "$REVISION_SUFFIX")
fi

if [[ -n "$TRAFFIC" ]]; then
  CMD_ARGS+=(--traffic "$TRAFFIC")
fi

if [[ -n "$LABELS" ]]; then
  CMD_ARGS+=(--labels "$LABELS")
fi

if [[ -n "$EXECUTION_ENVIRONMENT" ]]; then
  CMD_ARGS+=(--execution-environment "$EXECUTION_ENVIRONMENT")
fi

if [[ -n "${INGRESS:-}" ]]; then
  CMD_ARGS+=(--ingress "$INGRESS")
fi

if [[ -n "${SERVICE_ACCOUNT_EMAIL:-}" ]]; then
  CMD_ARGS+=(--service-account "$SERVICE_ACCOUNT_EMAIL")
fi

if [[ -n "${VPC_CONNECTOR:-}" ]]; then
  CMD_ARGS+=(--vpc-connector "$VPC_CONNECTOR")
  if [[ -n "${VPC_EGRESS:-}" ]]; then
    CMD_ARGS+=(--vpc-egress "$VPC_EGRESS")
  fi
fi

if [[ -n "$CLOUD_RUN_FLAGS" ]]; then
  # shellcheck disable=SC2206 # Allow splitting on spaces for additional flags.
  EXTRA_ARGS=($CLOUD_RUN_FLAGS)
  CMD_ARGS+=("${EXTRA_ARGS[@]}")
fi

echo "Deploying service '$SERVICE_NAME' to Cloud Run region '$REGION' in project '$PROJECT_ID'..."
gcloud "${CMD_ARGS[@]}"

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --platform managed \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --format="value(status.url)")

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "service_url=${SERVICE_URL:-}"
  } >> "$GITHUB_OUTPUT"
fi

echo "Deployment completed."
echo "Cloud Run Service URL: ${SERVICE_URL:-Unknown}"
