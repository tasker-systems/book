# Error Troubleshooting Guide

> Auto-generated troubleshooting guide. Do not edit manually.
>
> Regenerate with: `cargo make generate-error-guide`

This guide provides diagnosis and resolution steps for errors in the Tasker
workflow orchestration system. Errors are organized by subsystem, from
high-level system errors to specific execution and infrastructure errors.

**Error hierarchy**: Most specialized errors convert upward —
`ExecutionError` → `OrchestrationError` → `TaskerError`. When troubleshooting,
start with the most specific error type and work outward.

---

### TaskerError

## Troubleshooting Guide for Tasker Errors

When encountering errors in Tasker, it's crucial to identify the root cause and take appropriate action to resolve them. Below is a guide that covers some of the most significant `TaskerError` variants along with their causes, diagnosis methods, and resolutions.

| Variant | Cause | Resolution |
| --- | --- | --- |
| DatabaseError | Issues connecting to or querying the database. This could be due to network issues, incorrect credentials, or database server unavailability. | Check the database logs for connection errors or timeouts; verify that the Tasker configuration has correct database credentials and URL; ensure the database server is up and running. |
| StateTransitionError | Problems transitioning states in a workflow state machine due to invalid transitions or missing data. | Review the state machine definition for proper transition rules and check if all required input parameters are present before attempting state changes. |
| OrchestrationError | Issues related to orchestration logic such as incorrect workflow definitions, task failures, or unexpected behavior during execution. | Examine the workflow definitions for errors; review logs of individual tasks for detailed error messages; ensure that all necessary steps and dependencies are correctly configured in workflows. |
| EventError | Problems with event handling, including missing events, duplicate events, or timing issues leading to lost events. | Verify the event logging mechanisms to check if events are being captured as expected; validate the workflow's state-machine configuration for proper event trigger definitions. |
| ValidationError | Occurs when input data fails validation checks against predefined schemas or rules. This is typically due to incorrect data formats or missing required fields. | Review the validation schema and ensure that all provided inputs conform to these requirements; correct any discrepancies in the input data before retrying execution. |
| ConfigurationError | Issues arise from misconfigured settings within Tasker, such as incorrect worker configurations, event subscriptions, etc. | Check Tasker's configuration files for accuracy and completeness; refer to documentation for recommended best practices on configuring different components of Tasker. |
| InvalidConfiguration | Occurs when the system encounters a configuration file or environment variable that is malformed or contains unsupported values. | Validate all configuration settings according to documented guidelines; correct any errors in the configurations before attempting re-execution. |
| FFIError | Errors related to foreign function interface (FFI) calls, often due to incompatibilities between Tasker and external systems it interacts with. | Review the details of the error message for clues on incompatible system versions or required setup changes; ensure all necessary dependencies are correctly installed and configured. |
| MessagingError | Problems communicating through messaging services such as queues or brokers used within workflows. This could be due to network issues, broker unavailability, etc. | Verify that the messaging service is up and accessible from Tasker's environment; check configuration details for proper endpoints and authentication credentials. |
| CacheError | Errors related to caching mechanisms within Tasker where data retrieval or storage fails due to connectivity issues with cache servers or corrupted cache entries. | Investigate logs of cache management components to find any errors in communication or failures; flush and reconfigure the cache system if necessary, ensuring all configurations are up-to-date. |
| WorkerError | Errors originating from worker processes that may include code runtime issues like panics, crashes, or incorrect task execution. | Review the stack traces and logs for the specific worker to identify causes of failure; ensure correct implementation of tasks according to Tasker's guidelines; restart affected workers if necessary. |

This guide serves as a starting point for troubleshooting common errors in Tasker. For more detailed information on each error variant, refer to the full documentation or consult support channels provided by Alibaba Cloud.

---

### OrchestrationError

### Troubleshooting Guide for Tasker Orchestration Errors

This guide provides steps to diagnose and resolve common errors encountered in the Tasker workflow orchestration platform.

| Variant | Cause | Resolution |
|---------|-------|------------|
| DatabaseError | Issues with database operations such as connection failures or query errors. | Check database logs for any signs of operational issues, ensure that all necessary connections are established, and verify that queries match expected schema changes. |
| InvalidTaskState | Attempting to perform an operation on a task when it is in a state not compatible with the action being taken. | Review the current state of the affected task via the Tasker API or database, then transition the task to one of the valid states before retrying. Ensure that all workflow transitions are correctly defined and followed. |
| WorkflowStepNotFound | Reference to a step within a workflow that does not exist in the database. | Verify that the step UUID provided is correct and exists in the current workflow definition. Correct any errors in the workflow configuration or recreate the missing step entry. |
| StepStateMachineNotFound | The state machine responsible for managing transitions of a particular workflow step cannot be found. | Confirm the existence and correctness of the state machine configuration associated with the specific step. If it is supposed to exist, ensure that the registry or database has been properly updated. |
| StateVerificationFailed | A verification process on the state of a workflow step failed due to an invalid condition or unexpected outcome. | Inspect the reason provided for failure and cross-reference it against expected states transitions in your workflow logic. Correct any discrepancies between expected and actual states, then attempt re-verification. |
| DelegationFailed | The task execution cannot be delegated properly due to issues with worker frameworks such as Rust, Python, or TypeScript. | Ensure that all necessary workers are running and accessible over the network. Check framework-specific configurations for any required environment variables or dependencies. If using a specific worker framework (e.g., Rust), confirm its proper installation and configuration in Tasker settings. |
| TaskExecutionFailed | A task execution encountered an error preventing it from completing successfully. | Examine logs from both Tasker and the relevant worker to identify the root cause of failure. Address any issues noted, such as missing dependencies or incorrect configurations. Retry the failed task once the problem is resolved. |

Understanding these critical error conditions can help you efficiently debug and maintain robust workflows in your Tasker environment.

---

### StepExecutionError

### Troubleshooting Guide for StepExecutionErrors in Tasker

StepExecutionError is a critical component of Tasker's workflow orchestration, encapsulating various types of errors that can occur during the execution of tasks within workflows. Understanding and addressing these errors efficiently ensures smooth operation of complex state-machine driven processes.

| Variant | Likely Cause | Resolution |
|------------------------|------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Permanent | A critical issue preventing task completion, often due to configuration problems or external service failures. | Review the `message` and `error_code` in logs for detailed information. Adjust configurations or fix dependencies based on error specifics. |
| Retryable | Temporal issues such as transient network errors or resource contention that might resolve with time. | Check the provided `context`, if available, for additional insights into the nature of the problem. Consider adjusting retry policies and backoff strategies. |
| Timeout | Task execution exceeds specified duration due to delays in processing or external service response times. | Examine task logs and adjust timeout durations based on observed performance metrics. Investigate slow-running tasks or services causing delays. |
| NetworkError | Issues with connectivity or service availability affecting communication between Tasker and its dependencies. | Validate network configurations, inspect `status_code` for HTTP errors, and ensure that dependent services are up and responsive. Reconfigure if necessary. |

This guide provides a structured approach to diagnosing and resolving issues categorized under StepExecutionError in the Tasker workflow orchestration system.

---

### RegistryError

### Troubleshooting Guide for `RegistryError` in Tasker

When working with the Rust-based Tasker workflow orchestration platform, encountering a `RegistryError` indicates issues with registering or managing handlers within your workflows. This guide provides troubleshooting steps for resolving the most common types of these errors.

| Variant | Likely Cause | Resolution |
| --- | --- | --- |
| **NotFound** | Handler is referenced but not registered in the system. Common when trying to invoke a handler that hasn't been added to the registry or has been deleted. | Ensure all handlers are correctly registered and available at runtime. Double-check your workflow configuration for any references to non-existent handlers. If using dynamic registrations, confirm that registration requests are being processed successfully. |
| **Conflict** | Occurs when attempting to register a handler with an existing key, violating the unique constraint or due to incompatible updates. Can happen during parallel registration attempts or conflicting updates. | Review the logs and workflow configurations for any duplicate registration attempts or concurrent modifications of the same handler. Ensure that registration requests are serialized where necessary to prevent conflicts. Adjust your workflow logic if needed to handle concurrency correctly. |
| **ValidationError** | Handler fails validation checks, such as missing required fields, incorrect data types, or failing custom validations defined in Tasker's configuration. | Examine the error details for specific reasons why the handler failed validation. Correct any issues in the handler class or configuration files that are causing the failure. If custom validation rules are involved, ensure they match expected criteria and do not impose unnecessary restrictions. |
| **ThreadSafetyError** | Handler operation violates thread safety principles of Tasker, such as attempting to modify state from an invalid context. Can happen during concurrent access issues or misuse of async operations. | Review the logs and operational details around the time of failure for indications of concurrency issues. Ensure all modifications are made in threads or contexts that comply with Tasker's threading model guidelines. Modify offending code sections to ensure thread-safe practices, using proper synchronization mechanisms where necessary. |

By addressing these common causes and following the outlined resolutions, you should be able to mitigate `RegistryError` instances effectively within your workflows on Tasker.

---

### EventError

### Troubleshooting Guide for Tasker Event Errors

When working with Tasker workflows and encountering issues related to event handling, the following guide can help diagnose and resolve common errors quickly. This guide focuses on the most critical error variants in the `EventError` enum.

| Variant | Cause | Resolution |
|---------|-------|------------|
| **PublishingFailed** | Occurs when a task fails to publish an event, typically due to network issues or incorrect configuration parameters. | - Check Tasker logs for specific errors related to the failed event type.<br>- Ensure all required fields and configurations are correctly set in the workflow definition.<br>- Verify that the destination service is reachable and running. |
| **SerializationError** | Happens when there's a problem serializing data into an expected format, often due to mismatched types or missing required fields during serialization attempts. | - Review the application logs for detailed error messages regarding the failed event type.<br>- Validate input data against expected schemas or formats before attempting to serialize it.<br>- Adjust the workflow configuration if necessary to match the serialization requirements. |
| **FfiBridgeError** | This error occurs when there is an issue with the Foreign Function Interface (FFI) bridge, such as incorrect bindings, version mismatches, or library incompatibilities. | - Inspect Tasker logs for detailed information about the FFI error.<br>- Ensure that all dependencies and libraries used by the workflow are correctly installed and compatible with each other.<br>- Review and update FFI bindings if necessary to match changes in external systems or libraries. |

By addressing these common issues, you can enhance the reliability of your Tasker workflows and ensure smoother operation of event-driven processes.

---

### StateError

### Troubleshooting Guide for State Management Errors in Tasker

When dealing with workflow orchestration using Tasker, encountering errors related to state management is common. This guide focuses on providing quick fixes and diagnostics for critical issues derived from the `StateError` enum.

| Variant | Cause | Resolution |
|---------|-------|------------|
| InvalidTransition | Attempting an unsupported transition between two states for a specific entity type and UUID. | Verify the workflow definitions or business logic to ensure that transitions align with valid state changes. Update the workflow accordingly if necessary. Check logs for `entity_type`, `entity_uuid`, `from_state`, and `to_state` to validate the sequence of events leading up to this error. |
| StateNotFound | Requested operation on a non-existent entity type or UUID. | Confirm that the entity exists in the system prior to performing operations on it. Ensure all required entities are correctly created and initialized before proceeding with state changes. Use logs to trace whether an attempt was made to transition states for a non-existing entity. |
| DatabaseError | An unexpected issue occurred within the database layer, such as connection issues or queries failing. | Examine database logs and connection details to identify any issues like timeouts, disconnections, or query errors. Implement retries or enhanced error handling in Tasker's codebase to mitigate transient database errors. Consider scaling resources if persistent performance problems are identified. |
| ConcurrentModification | Another process modified the entity while an operation was being executed, causing a conflict. | Use optimistic concurrency control mechanisms such as versioning to prevent concurrent modifications. Ensure transactions encapsulate all operations on an entity during updates and employ locking strategies in high-concurrency environments. Monitor system metrics for spikes indicating excessive contention or transaction failures. |

By addressing these specific error variants effectively, you can maintain robust state management within Tasker workflows and ensure smooth orchestration of tasks across polyglot workers.

---

### DiscoveryError

### Troubleshooting Guide for Discovery Errors in Tasker

This guide provides steps to diagnose and resolve the most critical errors encountered during task discovery processes within Tasker.

| Variant | Cause | Resolution |
|---------|-------|------------|
| DatabaseError | Issues with database connectivity or operations, such as connection timeouts, query failures. | Check the database logs for any related exceptions or warnings. Ensure that the database is running and accessible from the server handling Tasker tasks. Verify if there are network issues preventing communication between services. |
| SqlFunctionError | SQL functions used in queries fail due to invalid usage or missing dependencies. | Review the function definitions and ensure they are correctly implemented and referenced in the query. Check for any syntax errors or logical mistakes that could be causing the issue. Validate that all required database objects (tables, views) exist and have the correct schema. |
| DependencyCycle | A circular reference is detected among tasks which prevents proper task sequencing. | Examine the workflow configuration to identify the cycle. Modify task dependencies to eliminate the circular relationship by ensuring each task has a clear starting point and no loops. Review the `cycle_steps` for specific task IDs involved in the loop and update their relationships accordingly. |
| ConfigurationError | Incorrect or missing configurations such as task templates or step definitions which are required for task execution. | Verify the existence of referenced entities like tasks, steps, etc., within the configuration files. Ensure that all necessary configurations are correctly defined without typos or inconsistencies. If the issue is due to a template not being found, recreate it based on existing examples or documentation provided by Tasker. |

These resolutions should help address common issues encountered with DiscoveryErrors in Tasker, ensuring smooth operation and efficient task processing within the platform.

---

### ExecutionError

When troubleshooting `ExecutionError` in Tasker, focus on the specific variant to diagnose and resolve issues. Each error provides insight into why a step execution failed, which can range from invalid states and concurrency control issues to timeouts and retries failing.

| Variant | Cause | Resolution |
|---------|-------|------------|
| StepExecutionFailed | The execution of a workflow step encountered an unexpected issue or failure that couldn't be automatically resolved. | Check the logs for detailed error messages related to the step UUID, including any system or application-specific errors indicated by `reason` and `error_code`. Adjust the workflow logic or configuration as needed based on these insights. |
| InvalidStepState | The state of a step was not in the expected condition when an action was attempted (e.g., trying to transition from "running" to "failed" without completing). | Review the sequence of events leading up to this error by examining logs and state transitions for the given step UUID. Ensure that all prerequisites for transitioning states are met correctly according to the workflow design before attempting another execution. |
| StateTransitionError | An unexpected issue occurred during a state transition within the execution process (e.g., database constraint violations, missing dependencies). | Examine logs surrounding the affected state transition and look for any reported reasons or constraints causing issues. Ensure that all necessary transitions are correctly specified in the workflow definitions and that there are no external factors preventing successful state changes. |
| ConcurrencyError | A concurrency control mechanism failed to manage parallel executions properly (e.g., locks, semaphores). | Investigate how concurrent tasks interact based on logs and metrics for step UUIDs involved. Ensure proper synchronization and backoff strategies are in place to handle high load or conflicting operations efficiently. Adjust configurations as necessary to prevent contention issues. |
| NoResultReturned | A workflow execution did not yield any output result despite completing all steps, indicating a failure to properly conclude an operation. | Confirm that each step is configured correctly to produce expected results and that there are no missing return values causing the error. Review and validate the logic of your workflows to ensure proper handling across all branches and edge cases. |
| ExecutionTimeout | A workflow or individual step did not complete within a set time limit, leading to automatic termination. | Increase timeout durations if tasks consistently exceed their allotted time due to high processing demands. Analyze steps for potential inefficiencies causing delays and optimize code accordingly. Ensure that timeouts are appropriately defined based on realistic execution scenarios. |
| RetryLimitExceeded | The number of allowed retries for a step or workflow has been reached without successful completion, indicating persistent issues. | Review the root causes of failures leading to retry attempts by analyzing logs and state histories. Adjust retry policies or error handling strategies as needed to address recurring issues more effectively, including increasing max attempt limits if appropriate. |
| BatchCreationFailed | An issue occurred during batch creation for ZeroMQ publishing, often related to network communication problems. | Check the status of your messaging system and ensure that all components are running smoothly without disruptions. Verify configuration settings such as message queue size and error handling mechanisms, and correct any misconfigurations or network issues impeding batch creation processes. |

These steps should help pinpoint and address common issues encountered in Tasker's workflow execution environment.

---

> Troubleshooting guidance generated with Ollama (`qwen2.5:14b`). Set `SKIP_LLM=true` for deterministic output.

---

*Generated by `generate-error-guide.sh` from tasker-core error definitions*
