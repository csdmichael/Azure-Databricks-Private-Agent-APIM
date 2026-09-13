# Showcase Analytics and Genie User Federation

Status: Validated

Current scope: activate the existing Showcase Node analytics/history runtime using
the dedicated IISNode entry point and automatic package rollback. User requested
continuation of pending tasks after approving rollback-protected activation.
Use -SkipInfrastructure -SkipBuild after current tests/build pass. No new
infrastructure, identity grants or network changes. Prior OBO evidence retained.

## Approval and Context

The user approved implementation, deployment, publication, and upgrading the existing
Windows Showcase plan from F1 to B1. They subsequently requested visitor analytics
and authorized a cost-efficient Cosmos DB in the same resource group if none exists.
The user explicitly authorized admin@Caldova37587778.onmicrosoft.com and requested
denied access for myaacoub@Caldova37587778.onmicrosoft.com. The target subscription,
resource group and West US 2 were reconfirmed through the approval prompt.

- Subscription: cf824570-a8ba-497a-a184-0a52f1830aa9
- Resource group: m365-myaacoub
- Region: westus2 (existing APIM remains westus)
- Recipe: Bicep and Azure CLI, preserving existing deployment conventions, no azd.
- Existing plan: caldova-showcase-plan, Windows B1 (upgrade completed).
- Existing site: caldova-databricks-showcase.

## Architecture

Analytics: existing Windows site hosts Angular plus Node 24/Express. A serverless
Cosmos NoSQL account stores visits with 90-day TTL and /day partitions. Access is
managed identity only through a private endpoint and VNet integration. Public
Showcase access stays anonymous; statistics require tenant-bound EasyAuth and an
explicit administrator object-ID allowlist. Initial admin is the current operator.
Raw IPs are never exposed through a public statistics endpoint. Local GeoIP lookup.

Genie: per-user Power Platform OAuth token -> APIM JWT validation -> private
TypeScript Azure Function on the existing plan -> Databricks RFC 8693 user token
federation -> Genie using the federated user's Unity Catalog authorization.
No service-principal fallback or tenant-wide data grants. Cutover is gated on a
Databricks account federation policy, explicit grants and real user validation.

## Execution

- [x] Broker implementation and local tests.
- [x] Dashboard, privacy notice, server implementation and local tests.
- [x] Approved B1 upgrade and Showcase system-assigned identity.
- [x] Analytics Bicep and PowerShell deployment artifacts.
- [x] Analytics preflight and infrastructure deployment.
- [ ] Analytics runtime activation (static Showcase restored after Node/IIS failure).
- [x] Private Function infrastructure and APIM policy.
- [x] Entra connector registration and Databricks account federation.
- [x] Positive administrator delegated-user tests.
- [ ] Genuine denied-user and non-admin data tests; safe cutover.
- [x] OBO docs and evidence published as e55b8c8; video fix as bb306f9.
- [ ] Live analytics/admin checks and Azure configuration screenshots.

## Private Broker Deployment Scope

Reuse `caldova-showcase-plan` (Windows B1, westus2) without modifying the Showcase
site or the existing managed-identity Genie API. Add `caldova-genie-obo-fn` with
Functions v4/Node22, system-assigned identity, Always On, 64-bit, HTTPS only and
public access disabled. Reuse `genie-obo-integration` for outbound VNet integration.
Add an inbound sites private endpoint and link `privatelink.azurewebsites.net` to
the APIM and Databricks VNets. Private SCM deployment must use an existing private
network path; do not temporarily open the Function publicly.

Add a dedicated Standard_LRS StorageV2 host account, public and shared-key access
disabled, with Blob private endpoint/DNS. Use identity-based AzureWebJobsStorage
and storage-scoped Blob Data Owner for this HTTP-only host. Any additional roles
or endpoints must be justified by host requirements before deployment. Use a local
run-from-package ZIP, not Azure Files content storage. Reuse the existing OBO
Application Insights resource and disable payload logging. New private endpoints
and storage have recurring costs; no additional plan capacity is requested.

Create separate single-tenant API and confidential connector registrations. API
tokens are v2: `aud` and `BROKER_AUDIENCE` are the API GUID, while APIM requests the
`api://<guid>` resource. Configure delegated Genie.Access and user-bound consent.
Never save client secrets or user tokens in source, output or screenshots.

Acceptance: Bicep compile, Azure validate/what-if, private host startup, anonymous
broker rejection, public access rejection and existing Showcase health. Federation
and actual allow/deny user proof remain separate gates before connector cutover.

Add the separate `databricks-genie-obo` API, its five nonsecret named values,
Application Insights logger/diagnostic and audit fragment. Reuse existing Genie
operation rewrites; do not modify the original managed-identity API. JWT failures
are 401, disallowed users 403, broker infrastructure failures 502. Body/header
capture remains disabled; traces contain correlation and verified user identity.

Approved through the Private Broker Plan prompt. The API registration is
`bdd127ff-fd4c-45f5-b553-ff77a7755161`; connector client is
`8127fb92-0641-4f6e-9d6e-f508e18e9606`. Delegated consent is Principal-scoped
to the approved admin, not AllPrincipals. No connector secret was created.
Private Function template compilation: successful, no diagnostics. Broker tests:
6 passed, including v2 GUID audience validation.

## Security and Cost Controls

Retain existing APIM/Databricks network lockdown. Do not grant all tenant users.
Cosmos serverless has request/storage charges without provisioned throughput;
private endpoints/DNS and B1 have recurring charges. No exact cost quote yet.
Stats record limits bound query work. Entra client secrets remain in App Service
settings and memory, not source, command output or deployment artifacts.

## Section 7: Validation Proof

2026-09-12 nine-video Showcase refresh:
- User added `08. Updating Agent with OBO Flow.mp4`, renamed the prior business
	case recording to episode 09, and requested commit, publication and deployment.
- Episode 08 is Git LFS object
	`sha256:9bfdeeb30f0bfada145177d6a8e4183077454adba7312f776e9d21f1e3522975`
	(60,548,904 bytes). Episode 09 retains LFS object
	`sha256:7fdef50c48522ad555dd6a532cd010c111adcf6ad51559466a6790a10c422d05`
	(13,022,994 bytes), allowing Git to preserve the business-video rename.
- Windows media metadata reports 10:14 for episode 08. Chromium decoded it at
	1920x1080 with ready state 4, no media error and advancing playback; observed
	duration was 614.95 seconds.
- `npm --prefix ui run build -- --configuration production`: passed, hash
	`565a7e9246bb4297`; the generated Showcase chunk contains episode 08 and 09.
	`npm test --prefix showcase-server`: all 12 tests passed. The nine sequential
	catalog entries exactly match the nine MP4 filenames; editor diagnostics,
	PowerShell parsing and `git diff --check` passed.
- Azure CLI authentication matches subscription
	`cf824570-a8ba-497a-a184-0a52f1830aa9` and tenant
	`12a4b86b-e64c-43f9-af05-d9130a72dfd2`; the target Showcase app is
	Running with Normal availability.
- This is a content-only package deployment. No infrastructure, RBAC, identity,
	application-setting, policy, quota, Docker or schema changes are required.
	Publish both LFS objects and source metadata before deploying with
	`deploy-showcase-analytics.ps1 -SkipInfrastructure -SkipBuild`.
- Post-deploy gates: OneDeploy status 4, health and Showcase HTTP 200, anonymous
	admin APIs 401, nine playlist rows, episodes 08 and 09 HTTP 200 and playable,
	and no horizontal overflow at a 390x844 viewport.
- OneDeploy deployment `f7d112a6fadd4947813c651b2a2dd87a` completed with status
	4 and mounted package `20260913001152.zip`; rollback package
	`20260912230035.zip` remains available. Health and Showcase returned 200, while
	the anonymous statistics and history APIs returned 401.
- The live page renders nine playlist rows. Published episodes 08 and 09 return
	HTTP 200 and both decoded at 1920x1080 with advancing playback and no media
	error; observed durations were 614.95 and 198.31 seconds. An isolated 390x844
	browser check selected episode 08 and showed no horizontal overflow.

2026-09-12 eight-video Showcase refresh:
- User requested the new OBO authentication recording as episode 07, moved the
	business-case recording to episode 08, and requested commit, publication and
	deployment.
- New episode 07 is Git LFS object
	`sha256:6a5f288c8b89a3a3ff6a823f1f7224ae28f5b7a96fa5d028b2cd9b0707270d47`
	(370,065,632 bytes). Windows media metadata reports 18:47. Chromium decoded it
	at 1920x1080, returned a nonblank video pixel and advanced playback.
- `npm --prefix ui run build -- --configuration production`: passed, hash
	`d4fdd9968ba4c141`; generated Showcase chunk contains both episode filenames.
- `npm test --prefix showcase-server`: all 12 tests passed. Deployment PowerShell
	parser and editor diagnostics passed; `git diff --check` passed.
- Azure CLI authentication matches subscription
	`cf824570-a8ba-497a-a184-0a52f1830aa9` and tenant
	`12a4b86b-e64c-43f9-af05-d9130a72dfd2`; the target Showcase app is Running.
- This is a content-only package deployment. No infrastructure, RBAC, identity,
	application-setting, policy, quota, Docker or schema changes are required, so
	ARM validation/what-if and static role changes are not applicable. Existing
	validated infrastructure and rollback controls remain unchanged.
- Publish the LFS object and source commit before deployment because the Showcase
	streams recordings from the repository's `main` branch. Deploy with
	`deploy-showcase-analytics.ps1 -SkipInfrastructure -SkipBuild` after push.
	Post-deploy gates: health and Showcase HTTP 200, anonymous admin APIs 401,
	eight playlist rows, both new media URLs HTTP 200, and browser playback for
	episodes 07 and 08 across desktop and mobile viewports.
- The first deployment attempt through legacy `/api/zipdeploy` reset during the
	80,487,865-byte upload and created no Kudu deployment record. Automatic rollback
	restored mounted package `20260912044416.zip`; health and Showcase returned 200,
	and Azure reported the app Running with Normal availability.
- The deployment script now uses the documented Kudu publish API with `type=zip`,
	`clean=true`, `restart=false`, HTTP/1.1 and a disabled `Expect` handshake. The
	script retains its explicit restart, deployment-status check and automatic
	rollback. All 12 server tests and PowerShell parsing passed after the change.
- OneDeploy deployment `385cc8de30bd48bc9e5b1aeb6410d069` completed with status
	4 and mounted package `20260912230035.zip`; rollback package
	`20260912044416.zip` remains available. Health and Showcase returned 200, while
	the anonymous statistics and history APIs returned 401.
- The live page renders eight playlist rows. Published episodes 07 and 08 return
	HTTP 200 and both decoded at 1920x1080 with advancing playback and no media
	error; observed durations were 1127.77 and 198.31 seconds. An isolated 390x844
	browser check showed no horizontal overflow and rendered episode 07 correctly.

2026-09-12 architecture PNG content-only refresh:
- User requested Showcase Architecture tab addition, README diagram replacement,
	sequence diagram removal, commit, publication and deployment.
- npm --prefix ui run build -- --configuration production: passed, hash
	2c29133e44842877. Bundled PNG byte-for-byte equals docs/obo source image.
- npm --prefix showcase-server test: all 12 tests passed.
- README check: exactly one PNG in Architecture; sequence diagram removed.
- Azure CLI authentication matches approved subscription and tenant. Existing
	Showcase is Running in West US 2 with unchanged managed identity.
- git diff --check passed. No infrastructure, RBAC, application settings or
	backend changes; existing role verification remains applicable. Docker,
	quota, ARM validate/what-if and resource-policy changes are not applicable.
- Deploy existing script with -SkipInfrastructure -SkipBuild; preserve mounted
	runtime package for rollback. Verify health, anonymous API denial and diagram
	rendering across desktop/mobile after deployment.

Current activation gates: Node wrapper/named-pipe test, twelve server tests,
Angular production build, deployment-script parse, approved Azure target and
existing nonsecret configuration, scoped Cosmos/Log Analytics permissions.
Post-deploy: health JSON 200, Showcase HTML 200, anonymous/forged-admin API denial,
authenticated statistics/history, actual visit persistence and request grouping.
Keep the currently mounted static package and restore it on deployment failure.
No ARM resource changes: new quota, resource what-if and Docker are not applicable.

- [x] All validation checks pass (current runtime activation)
	- [x] Core Validation (CLI, auth, Node tests/build and script syntax; resource validate/what-if not applicable to package-only deployment)
	- [x] Docker Build (not applicable: Windows IISNode, no container)
	- [x] Azure Policy Validation (no resource changes; prior infrastructure policy validation retained)

2026-09-12 current analytics activation preflight:
- npm --prefix showcase-server test: 12 passed, including IISNode named-pipe startup.
- npm --prefix ui run build -- --configuration production: passed; hash 3c72fdd591c32c09.
- PowerShell Parser.ParseFile and editor diagnostics: no errors.
- Actual deployment guard executed with isolated mock commands: success, upload
	failure, invalid health and anonymous authorization failure all passed; each
	failure restored the expected prior package. No Azure calls in these tests.
- az account show: approved subscription and tenant match. App Service Running;
	Node ~24, run-from-package 1, AlwaysOn true, 64-bit, expected integration subnet.
- ARM allowlisted configuration inspection: Cosmos/log endpoints present;
	EasyAuth enabled, tenant v2 issuer, approved admin oid, public page anonymous.
- Static and live role verification: Showcase MI has Cosmos built-in Data
	Contributor scoped to showcase-analytics DB and Log Analytics Reader scoped to
	caldova-apim-logs-westus. No additional roles required or granted.
- Runtime deployment downloads and inspects the mounted rollback ZIP before
	upload; validates unique portable archive entries. Public health/SPA and
	anonymous API denial are required after restart or the package is restored.

2026-09-12 static Showcase refresh: user requested redeployment after live browser
inspection found an old six-video bundle referencing a missing MP4 (404).
Angular production build passed. All seven current media URLs returned HTTP 200.
The 3,087,414-byte static ZIP contains index.html, the current hashed bundles and
the retained working IIS SPA web.config; archive paths use forward slashes.
Current live page HTTP 200. Mounted package 20260912024014.zip downloaded and
validated (1,175,994 bytes, 1,373 entries) for rollback. Azure CLI authentication
and Kudu package access succeeded. No ARM or RBAC changes: infrastructure
validate/what-if and Docker build are not applicable to this content-only refresh.
Post-deploy gate: HTTP 200, seven visible playlist items, playable media frames
for each item and responsive desktop/mobile checks. Analytics stays inactive.

- [x] All validation checks pass (private broker scope)
	- [x] Core Validation (CLI, auth, build, validate, what-if)
	- [x] Local compilation, tests and Bicep linting
	- [x] Azure Policy Validation

2026-09-12 private broker: azure-validate validate-deployment.ps1 -Scope group
-ResourceGroup m365-myaacoub -Template bicep/genie-obo/main.bicep
-Parameters bicep/genie-obo/reference.bicepparam -Subscription
cf824570-a8ba-497a-a184-0a52f1830aa9: OVERALL PASS. CLI/auth/build/ARM validation
passed. What-if: Create 17, Modify 0, Delete 0. Existing Showcase and APIM unchanged.
Azure MCP and ARM atScope policy queries confirmed inherited assignments. Deny
definitions reviewed: classic resources, blocked VM/service SKUs and West Europe
do not match this HTTP Function, LRS storage and private-network deployment.
ARM validation found no blocking policy conflict. This is deployment preflight,
not a claim that all subscription-wide security recommendations are satisfied.

2026-09-12 APIM follow-up: same validate-deployment.ps1 recipe with
-Template apim/obo.bicep -Parameters apim/obo.reference.bicepparam:
OVERALL PASS. Create 19, Modify 0, Delete 0. XML/status-mapping checks passed.
Inherited policy review above remains applicable; no new RBAC grant introduced.
APIM policy expressions still require server-side compilation during deployment.

Private infrastructure deployment `genie-obo-private`: Succeeded. Function
principal `551aeb1a-3359-4daa-ae02-ba4e5e3eadf0` verified with storage-scoped Blob
Data Owner. Private SCM ZIP deployment `5c1229bc2f4941628d5e37a43374f830` succeeded.
After restart/cold start, host reports Running and private anonymous POST returns
401. Public Function and SCM return 403; Showcase /showcase returns 200.
User approved temporary start of caldova-jump for private deployment/testing;
deallocate it when this verification work finishes. Token passed through Managed
Run Command protectedParameters only; remote package staging is deleted afterward.

Role review: Function system-assigned identity has Storage Blob Data Owner on
its dedicated host-storage account. HTTP-only trigger, no Durable/Blob/Queue
bindings. No resource-group or subscription data-access role is introduced.
APIM caller authorization is pinned to its managed-identity object ID in code.

### Historical Analytics Validation

2026-09-12: azure-validate validate-deployment.ps1 -Scope group
-ResourceGroup m365-myaacoub -Template bicep/showcase-analytics/main.bicep
-Parameters bicep/showcase-analytics/main.parameters.json: OVERALL PASS.
ResourceIdOnly what-if reviewed: analytics resources created, site auth updated,
unrelated resources ignored, no resources deleted. Inherited policy assignment
list using Azure CLI originally appeared empty. Superseded by the private broker
ARM atScope check above, which correctly includes inherited policy assignments.
Cosmos built-in data contributor role is assigned to the actual Showcase managed
identity, scoped to /dbs/showcase-analytics, with local/key auth disabled.
Windows Node24 availability confirmed. Latest analytics tests: 8/8 passing.

2026-09-12: broker npm test: 5 passed; analytics npm test: 7 passed;
Angular production build passed; analytics Bicep compilation passed with one
cloud-specific issuer warning; PowerShell syntax passed; Windows Node24 supported.
No live user federation or analytics validation yet.

## Rollback

Keep the existing Genie managed-identity API policy active until user federation
is validated. Retain prior Showcase deployment package for application rollback;
disable collection by rolling back the hosting package. Do not delete data,
registrations, networking or reduce the shared plan without explicit approval.