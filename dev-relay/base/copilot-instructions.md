# YOUR WORKSPACE — Copilot Instructions

Treat this file as general workspace guidance. If information in `agents/` or `skills/` conflicts with guidance in this file, follow the information in `agents/` and `skills/` instead.

When a nested agent returns a pending human checkpoint, relay that checkpoint to the developer and end the turn. Never answer it on the developer's behalf, emit any registered advancing or revision reply as assistant output, convert it into a synthetic user message, re-invoke the agent with a claimed decision, or dispatch the next specialist. Only a later top-level developer message can resolve the checkpoint.

## Table of Contents

- [Overview](./copilot-instructions.md#overview)
- [Architecture](./copilot-instructions.md#architecture)
- [Key Repositories](./copilot-instructions.md#key-repositories)
- [Tech Stack](./copilot-instructions.md#tech-stack)
- [Coding Style](./copilot-instructions.md#coding-style)
- [Conventions](./copilot-instructions.md#conventions)
- [Testing](./copilot-instructions.md#testing)
- [Data Model](./copilot-instructions.md#data-model)
- [<ORG_NAME> Infrastructure](./copilot-instructions.md#jpmc-infrastructure)
- [Notes](./copilot-instructions.md#notes)

## Overview

Instruction: Add descriptions of the project overview, architecture, and other key information such as end-to-end flow descriptions.

## Architecture

Instruction: Add descriptions of the architecture, including the overall structure, components, and their interactions. Include any relevant diagrams or visualizations that help illustrate the architecture.

## Key Repositories

Instruction: Add descriptions of the key repositories, their purpose, and how they relate to each other. Include any relevant information about the architecture, dependencies, and interactions between the repositories. If a `repo-inventory.json` file is present at `.github/artifacts/`, treat it as the authoritative source of truth for the repository inventory and scope (repository names and their `status`), and reconcile this section against it.

## Tech Stack

Instruction: Add descriptions of the tech stack, including programming languages, frameworks, libraries, and any other relevant technologies used in the project. Include information about the versions and any specific configurations or settings that are important for understanding the tech stack.

## Coding Style

Instruction: Add descriptions of the coding style guidelines, including naming conventions, formatting rules, and any other relevant information about how code should be written and organized in the project.

## Conventions

Instruction: Add descriptions of the conventions used in the project, including any specific patterns, practices, or methodologies that are followed. Include information about how these conventions help maintain consistency and quality in the codebase.

## Testing

Instruction: Add descriptions of the testing guidelines, including how tests should be written, organized, and executed. Include information about the testing framework used, any specific configurations or settings, and any best practices for writing effective tests.

## Data Model

Instruction: Add descriptions of the data model, including the key entities, relationships, and attributes. Include information about how the data model is used in the project and any relevant diagrams or visualizations that help illustrate the model.

## <ORG_NAME> Infrastructure

For a high-level, newbie-friendly orientation to <ORG_NAME>'s infrastructure — identity/IAM, authentication models, DevX and SCM setup, the toolchain and CI/CD, the cloud platforms, compute/data/messaging/AI-ML platforms, networking, service exposure, and monitoring/incident management — see [copilot-infra-nutshell.md](./copilot-infra-nutshell.md). Use it as an orientation map and jumping-off point; refer to your organization's internal engineering documentation for authoritative, up-to-date detail.

## Notes

This file may be overwritten by a matching workspace, repository, or local overlay.

This Copilot instruction assumes the standard DevShell layout under `I:\<WORKSPACE_PROJECTS_DIR>`, where each workspace resides in that directory and can contain one or more git repositories. Team/Project overlay is set up at each workspace root (via `.claude` and `.github`). Repo overlay is set up at each repository root. You can place the personal overlay at either level.

Sample hierarchy:

```text
I:\
└── ds\
    └── projects\
        ├── <workspace-a>\
        │   ├── <repo-1>\
        │   └── <repo-2>\
        └── <workspace-b>\
            ├── <repo-3>\
            └── <repo-4>\
```

When you open files from a repo, VS Code automatically attaches that repo's `instructions/<repo>.instructions.md` file. You do not need to load these instructions manually.
