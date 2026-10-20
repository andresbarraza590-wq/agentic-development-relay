---
name: mocking-patterns
description: 'Properly isolate code under test by mocking external dependencies. Use when creating unit tests that require mocked network calls, data stores, configuration providers, cloud services, or infrastructure tooling interactions.'
---

# Mocking Patterns

> Public base skill — keep it generic. Team-specific names, repos, frameworks, and commands belong in the private overlay, not here.

## Purpose

Enforce correct dependency isolation for unit tests so behavior is validated without external-system coupling.

## Operating Contract

1. Mock only external boundaries.
2. Keep mocks contract-aware and deterministic.
3. Validate both outcome and interaction behavior.
4. Include realistic failure-path simulation.

## When to Use

- Unit test creation for code with external dependencies.
- Test hardening for unstable or flaky dependency calls.
- Verification of boundary contracts.

## Core Rules

1. Mock at boundary adapters/clients, not internal logic.
2. Use contract-aware mocks to detect interface drift.
3. Assert expected interactions when behavior depends on them.
4. Never mock the code under test itself (guardrail TQ-2 in `.github/config/guardrails.yaml`).
5. Use deterministic fixtures and explicit scenario inputs.
6. Include failure scenarios (timeout, auth, throttling, malformed responses).

## Procedure

### Step 1: Identify Boundaries

- Enumerate network, storage, config, queue, and cloud Software Development Kit (SDK) dependencies.

### Step 2: Define Mock Contracts

- Mirror expected request/response schema and error modes.

### Step 3: Implement Scenario Fixtures

- Build stable fixtures for success and failure variants.

### Step 4: Assert Behavior

- Assert result correctness and dependency-call expectations.

### Step 5: Validate Isolation

- Confirm tests run without real external system access.

## Common Patterns

### Service API Calls

```text
TEST "fetches data from service"
    mockApiClient <- CREATE_MOCK(ServiceApiClient, contract=ServiceApiContract)
    WHEN mockApiClient.GET("/resource") RETURNS { status: 200, body: { data: "value" } }

    service <- NEW ServiceUnderTest(apiClient=mockApiClient)
    result <- CALL service.fetchData("example.com")

    ASSERT result.data == "value"
    ASSERT mockApiClient.GET CALLED_ONCE_WITH("/resource", { timeout: 30 })
END
```

### Data Store Access

```text
TEST "reads records from repository"
    mockRepository <- CREATE_MOCK(Repository, contract=RepositoryContract)
    WHEN mockRepository.query("SELECT ...") RETURNS [{ id: 1, name: "test" }]

    component <- NEW Component(repository=mockRepository)
    records <- CALL component.loadRecords()

    ASSERT LENGTH(records) == 1
    ASSERT mockRepository.query CALLED_WITH_MATCHING_SQL()
END
```

### Configuration and Secrets

```text
TEST "uses configuration provider values"
    mockConfig <- CREATE_MOCK(ConfigurationProvider)
    WHEN mockConfig.get("API_KEY") RETURNS "test-key"
    WHEN mockConfig.get("ENV") RETURNS "test"

    app <- NEW App(config=mockConfig)
    CALL app.start()

    ASSERT app.environment == "test"
    ASSERT mockConfig.get CALLED_WITH("API_KEY")
END
```

### Cloud SDK and Infrastructure Tooling

```text
TEST "uploads object through cloud storage client"
    mockStorageClient <- CREATE_MOCK(ObjectStorageClient, contract=ObjectStorageContract)

    uploader <- NEW ArtifactUploader(storageClient=mockStorageClient)
    CALL uploader.upload("bucket", "key", BYTES("data"))

    ASSERT mockStorageClient.putObject CALLED_ONCE_WITH({ bucket: "bucket", key: "key" })
END

TEST "handles infrastructure plan failure"
    mockIaCTool <- CREATE_MOCK(InfrastructureTool)
    WHEN mockIaCTool.plan() THROWS PlanFailedError("Invalid variable")

    deployer <- NEW InfrastructureDeployer(tool=mockIaCTool)

    ASSERT_THROWS ValidationFailureError, CALL deployer.previewChanges()
    ASSERT mockIaCTool.apply NOT_CALLED
END
```

## Constraints

- Do not use broad, behaviorless mocks that hide contract changes.
- Do not couple tests to unstable live endpoints.
- Do not omit negative-path dependency simulations for critical flows.

## Skill Continuity Protocol

Use this protocol to avoid losing execution state during long user interaction.

1. Keep a live step ledger with active step, status (`waiting`, `ready`, `blocked`), pending input, and next action.
2. After each user response, first reconcile whether pending input is resolved, then restate the active step.
3. If conversation drifts, answer the side question and explicitly return to the pending skill step.
4. Do not advance to the next step until required input for the current step is explicit.
5. If context becomes unclear, recover from the latest confirmed step and summarize complete versus pending work.
