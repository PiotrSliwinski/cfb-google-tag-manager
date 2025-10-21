# CI/CD for Server-Side Google Tag Manager on Cloud Run

This repository ships with a GitHub Actions workflow and helper script that deploy the official Server-Side Google Tag Manager (GTM) container image to Cloud Run. The pipeline builds no artefacts—it authenticates with Google Cloud, renders the required environment configuration, and issues a `gcloud run deploy`.

## Prerequisites

- A Google Cloud project with the Cloud Run, IAM, and Cloud Resource Manager APIs enabled:
  ```bash
  gcloud services enable run.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com
  ```
- A Cloud Run service account with permissions:
  - `roles/run.admin`
  - `roles/iam.serviceAccountUser` (if you deploy with a dedicated runtime service account)
- GitHub environment/organization secrets to hold the Google Cloud credentials and runtime configuration (detailed below).

## One-time Google Cloud setup

1. (Optional) Create a dedicated service account that the workflow uses for deployments:
   ```bash
   gcloud iam service-accounts create gtm-deployer \
     --project "${PROJECT_ID}" \
     --display-name "Server-side GTM deployer"
   ```
2. Grant the required roles:
   ```bash
   gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
     --member="serviceAccount:gtm-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/run.admin"

   gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
     --member="serviceAccount:gtm-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountUser"
   ```
3. Create and download a JSON key for the deployer service account, then store its contents in the `GCP_SA_KEY` GitHub secret.

## GitHub secrets and variables

Create the following secrets in your repository (Settings → Secrets and variables → Actions):

| Name | Required | Purpose |
| ---- | -------- | ------- |
| `GCP_PROJECT_ID` | ✅ | Google Cloud project that hosts Cloud Run. |
| `CLOUD_RUN_ENV_VARS_YAML` | ✅ | Environment configuration used during deployment (see next section). |
| `GCP_SA_KEY` | ✅ | Service account key JSON used by the workflow to authenticate with Google Cloud. |

✅ Required secrets. Optional configuration (such as region, service name, resource limits) can be supplied through GitHub repository **variables** (`vars.*`) or, for backward compatibility, secrets (`secrets.*`). Variables take precedence in the workflow.

> The workflow still accepts a legacy `GTM_ENV_VARS_YAML` secret. If both are present, `CLOUD_RUN_ENV_VARS_YAML` takes precedence.

Recommended (optional) repository variables:

- `CLOUD_RUN_REGION` (defaults to `us-central1` if unset; the workflow also falls back to a `CLOUD_RUN_REGION` secret if defined)
- `CLOUD_RUN_SERVICE_NAME` (defaults to `server-side-gtm`; likewise can fall back to a secret)
- Any additional Cloud Run settings supported by `scripts/deploy-cloud-run.sh` (for example `MEMORY`, `CPU`, `MIN_INSTANCES`, `MAX_INSTANCES`, `INGRESS`, `VPC_CONNECTOR`). Define them in GitHub Actions → Variables if you prefer not to edit the workflow file.

## Preparing the environment configuration

The deployment script feeds Cloud Run with an environment file at `config/env.yaml`. Because this file holds secrets (such as the exported container configuration), it is never committed to the repository:

1. Use `config/env.sample.yaml` as a template.
2. Replace placeholder values:
   - Generate the base64-encoded container configuration from GTM's **Admin → Container Settings → Server Container Operation → Download** page. Encode the raw JSON with `base64 -w0 config.json`.
   - Populate any optional API secrets or flags you rely on.
3. Paste the final YAML block into the `CLOUD_RUN_ENV_VARS_YAML` GitHub secret.

Example YAML content:

```yaml
CONTAINER_CONFIG: "BASE64_ENCODED_CONTAINER_CONFIG"
API_SECRET: "super-secret"
ENABLE_SECURE_ONLY_COOKIE: "true"
```

## How the workflow works

1. The workflow triggers on pushes to `main` or manually via the "Run workflow" button.
2. GitHub Actions checks out the repository.
3. Authentication to Google Cloud is established with the `GCP_SA_KEY` secret.
4. The `CLOUD_RUN_ENV_VARS_YAML` secret is written to `config/env.yaml` (falling back to `GTM_ENV_VARS_YAML` if the new secret name is absent).
5. `scripts/deploy-cloud-run.sh` wraps `gcloud run deploy` and injects parameters pulled from repository secrets/variables. The script also captures the resulting service URL for visibility inside the job summary.

## Running the deployment locally

If you would like to test deployments from your workstation:

```bash
gcloud auth login
gcloud config set project "${PROJECT_ID}"

cp config/env.sample.yaml config/env.yaml
# Edit config/env.yaml with real values (do not commit it).

PROJECT_ID="${PROJECT_ID}" \
REGION="us-central1" \
./scripts/deploy-cloud-run.sh
```

Optional overrides (for example concurrency, ingress, VPC connector) can be passed as environment variables before the script call, matching the variable names described above. This keeps the deployment pattern consistent across other services that call the same script.

Common overrides supported by `scripts/deploy-cloud-run.sh`:

- `PORT`, `ALLOW_UNAUTHENTICATED`
- `CONCURRENCY`, `TIMEOUT`, `MAX_REQUESTS_PER_CONTAINER`
- `MEMORY`, `CPU`, `MIN_INSTANCES`, `MAX_INSTANCES`
- `INGRESS`, `SERVICE_ACCOUNT_EMAIL`, `VPC_CONNECTOR`, `VPC_EGRESS`
- `TRAFFIC`, `REVISION_SUFFIX`, `LABELS`, `CLOUD_RUN_FLAGS`

## Troubleshooting

- **`CLOUD_RUN_ENV_VARS_YAML secret is empty`**: Ensure the secret is defined (or that the legacy `GTM_ENV_VARS_YAML` fallback is in place) and not scoped to a different environment in GitHub.
- **Authentication failures**: Confirm that the `GCP_SA_KEY` secret is valid and that the service account has the IAM roles listed earlier.
- **Cloud Run API errors**: Ensure the Cloud Run, IAM, and supporting APIs are enabled in the Google Cloud project and that your account has permission to deploy.

## Reusing the workflow for other services

To apply the same deployment pattern to another Cloud Run service (for example, a booking application):

1. Reuse `scripts/deploy-cloud-run.sh` and surface service-specific values through repository variables (for example `CLOUD_RUN_SERVICE_NAME`, `CLOUD_RUN_REGION`, `MEMORY`, `CPU`) or by exporting them in your workflow just before the deploy step.
2. Store that service's environment configuration in a multi-line GitHub secret (for example `CLOUD_RUN_ENV_VARS_YAML`) and materialise it into a YAML file inside the workflow, just before the deploy step.
3. Invoke the deploy script so it consumes the generated file and applies the Cloud Run update.

The secret-to-file approach keeps sensitive values out of workflow logs and avoids manually escaping complex values (such as JSON) when deploying.
