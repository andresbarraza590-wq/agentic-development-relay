# <ORG_NAME> Infra Nutshell

> **Template stub.** This file is an optional, firm-specific infrastructure orientation for
> agents (linked from `copilot-instructions.md`). The original organization-specific content
> has been removed. Fill in your own organization's infrastructure below, or leave it as a
> stub — the framework works either way: the architecture-doc mirror accepts it, and the
> `story-analyst` agent treats it as optional context (it falls back to other sources when the
> infrastructure knowledge it needs isn't here).

## Purpose

Give any developer — and the agents — a high-level, bird's-eye view of how a service comes to
life at <ORG_NAME>: identity onboarding and access, authentication models, source control and
CI/CD, cloud platforms and their governance, compute/data/messaging/AI-ML capabilities,
networking, service exposure, and monitoring/incident management. Use it as an orientation map
and a jumping-off point; link out to your authoritative internal documentation for detail.

## Sections to fill in

Replace each prompt with your organization's specifics — name the actual tools, portals, and
procedures. Delete any section that does not apply, and add others as needed.

- **User Setup & IAM** — how identities/accounts are provisioned; joiner/mover/leaver lifecycle; roles and entitlements.
- **Authentication** — SSO / identity provider, MFA, privileged access and secrets management, functional (service) accounts.
- **DevX / Developer Setup** — developer console/CLI, prerequisites, onboarding portals, access model, common issues and support paths.
- **Source Code Management (SCM)** — Git platform(s), org/project structure, branch and pull-request policy, secrets scanning.
- **Project Setup & Governance** — application inventory/IDs, design/permit/approval gates, control procedures and compliance.
- **CI/CD** — build/test/scan/deploy pipeline, pipeline-as-code, quality/security tollgates, change management.
- **Clouds** — private/on-prem and public cloud platforms and their governance.
- **Compute & Runtime** — PaaS, Kubernetes, VMs/containers, serverless.
- **Data & Storage** — databases; block/file/object storage; access model.
- **Messaging & Streaming** — queues, pub/sub, product-selection guidance.
- **AI/ML Platform** — data/AI platform, model training and serving, SDKs.
- **Networking & Connectivity** — egress proxies, cloud interconnect, DNS and service discovery.
- **Service Exposure to Public Internet** — DMZ patterns, WAF/DDoS, reverse proxies / API gateways, TLS and certificate management.
- **Operations: Monitoring & Alerts** — observability stack, alerting and routing, incident priorities and roles, runbooks and post-incident review.

> The original organization-specific term inventory (and suggested placeholders) is preserved
> in `copilot-infra-nutshell.INTERNAL-TERMS.md` at the repo root, in case you want to port
> specifics rather than start fresh.
