# Workflows in a Zero-Trust World

*How one company transformed their workflow engine to meet enterprise security and compliance requirements*

---

## The Enterprise Deal

Two years after beginning their workflow transformation journey, GrowthCorp had become the poster child for reliable engineering. Sarah, now CTO, was confident when she walked into the biggest deal in company history.

"We love your product," said Jennifer, the CISO at MegaCorp, a Fortune 500 financial services company. "But we need to talk about security and compliance."

Jennifer slid a thick document across the table: **"MegaCorp Security Requirements v3.2"**

"We need SOC 2 Type II compliance, role-based access controls, complete audit trails, data encryption at rest and in transit, zero-trust architecture, and GDPR compliance."

"Every workflow execution needs to be auditable. We need to know who triggered what, when, with what data, and what the outcome was."

Sarah flipped through the 47-page document, realizing their beautiful workflow engine had a massive security gap.

## The Security Audit

Back at the office, Sarah called an emergency security review with Priya, their new security engineer.

Here's what they found:

```ruby
# Current workflow execution - NO security controls
task_request = Tasker::Types::TaskRequest.new(
  name: 'process_refund',
  namespace: 'customer_success',
  context: {
    customer_id: 'cust_12345',           # ❌ PII in logs
    customer_email: 'john@example.com',  # ❌ PII in logs
    refund_amount: 299.99,               # ❌ Financial data
    reason: 'Product defective',         # ❌ No data classification
    agent_notes: 'Customer very upset'   # ❌ Sensitive notes
  }
)

# Anyone can execute any workflow
task = Tasker::TaskExecutor.execute_async(task_request)  # ❌ No authentication
```

**Security gaps discovered:**
- **No authentication**: Anyone with API access could execute workflows
- **No authorization**: No role-based permissions on workflows or data
- **No audit trails**: No record of who executed what workflows
- **PII exposure**: Customer data logged in plaintext
- **No data classification**: No distinction between public and sensitive data
- **No encryption**: Workflow context stored in plaintext

"We're storing everyone's personal and financial data in plaintext logs that anyone can access," Priya summarized. "This is a GDPR nightmare waiting to happen."

## The Zero-Trust Architecture

Over the next 90 days, Sarah's team rebuilt their workflow system with enterprise security:

### Authentication and Authorization

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    # JWT-based authentication
    auth.provider = :jwt
    auth.jwt_secret = Rails.application.credentials.tasker_jwt_secret
    auth.require_authentication = Rails.env.production?

    # Integration with existing auth systems
    auth.user_resolver = ->(token) {
      AuthService.resolve_user_from_token(token)
    }

    auth.permission_resolver = ->(user, permission) {
      PermissionService.user_has_permission?(user, permission)
    }

    # Role-based access control
    auth.authorization_enabled = true
    auth.default_permissions = []  # Deny by default
  end

  # Audit and compliance
  config.audit do |audit|
    audit.enabled = true
    audit.backend = :database
    audit.retention_period = 7.years  # Compliance requirement
    audit.include_context = true
    audit.include_results = false     # Don't log sensitive results
    audit.pii_fields = ['customer_email', 'customer_phone', 'address']
  end

  # Data encryption and classification
  config.security do |security|
    security.encryption_enabled = true
    security.encryption_key = Rails.application.credentials.tasker_encryption_key
    security.encrypt_context = true
    security.encrypt_results = true

    # Data classification
    security.data_classification_enabled = true
    security.default_classification = :internal
    security.pii_detection_enabled = true
  end
end
```

### Secure Workflow Execution

```ruby
# app/tasks/customer_success/process_refund_handler.rb
module CustomerSuccess
  class ProcessRefundHandler < Tasker::TaskHandler::Base
    TASK_NAME = 'process_refund'
    NAMESPACE = 'customer_success'
    VERSION = '2.0.0'

    # Define required permissions for this workflow
    requires_permissions 'customer_success.refunds.process'

    # Data classification for compliance
    data_classification :confidential
    contains_pii true

    register_handler(TASK_NAME, namespace_name: NAMESPACE, version: VERSION)

    define_step_templates do |templates|
      templates.define(
        name: 'validate_refund_request',
        description: 'Validate refund request and permissions',
        requires_permissions: 'customer_success.refunds.validate',
        audit_level: :detailed
      )

      templates.define(
        name: 'get_manager_approval',
        description: 'Route to manager for approval',
        depends_on_step: 'validate_refund_request',
        requires_permissions: 'customer_success.refunds.approve',
        audit_level: :detailed
      )

      templates.define(
        name: 'execute_refund',
        description: 'Execute the refund transaction',
        depends_on_step: 'get_manager_approval',
        requires_permissions: 'customer_success.refunds.execute',
        audit_level: :full,  # Full audit for financial transactions
        data_classification: :restricted
      )

      templates.define(
        name: 'notify_customer',
        description: 'Send refund confirmation to customer',
        depends_on_step: 'execute_refund',
        audit_level: :standard,
        contains_pii: true
      )
    end

    def schema
      {
        type: 'object',
        required: ['customer_id', 'refund_amount', 'reason'],
        properties: {
          customer_id: {
            type: 'string',
            'x-data-classification': 'pii-identifier'
          },
          customer_email: {
            type: 'string',
            format: 'email',
            'x-data-classification': 'pii-contact'
          },
          refund_amount: {
            type: 'number',
            'x-data-classification': 'financial'
          },
          reason: {
            type: 'string',
            'x-data-classification': 'internal'
          },
          agent_notes: {
            type: 'string',
            'x-data-classification': 'confidential'
          }
        }
      }
    end

    # Override to add security context
    def initialize_task!(task_request)
      current_user = AuthContext.current_user
      raise Tasker::AuthorizationError unless current_user

      required_permission = 'customer_success.refunds.process'
      unless PermissionService.user_has_permission?(current_user, required_permission)
        SecurityAuditLogger.log_unauthorized_access(
          user: current_user,
          attempted_action: "execute_workflow:#{NAMESPACE}/#{TASK_NAME}",
          required_permission: required_permission
        )
        raise Tasker::AuthorizationError, "Missing permission: #{required_permission}"
      end

      task = super(task_request)

      # Add security context for audit trails
      task.annotations.merge!({
        executed_by_user_id: current_user.id,
        executed_by_email: current_user.email,
        user_roles: current_user.roles.map(&:name),
        ip_address: AuthContext.current_ip,
        user_agent: AuthContext.current_user_agent,
        session_id: AuthContext.current_session_id,
        data_classification: 'confidential',
        contains_pii: true
      })

      task
    end
  end
end
```

### PII-Safe Logging and Audit Trails

```ruby
# app/concerns/pii_safe_logging.rb
module PIISafeLogging
  extend ActiveSupport::Concern

  def sanitize_for_logs(data)
    case data
    when Hash
      data.transform_values { |value| sanitize_for_logs(value) }
    when Array
      data.map { |item| sanitize_for_logs(item) }
    when String
      sanitize_string(data)
    else
      data
    end
  end

  private

  def sanitize_string(string)
    return string unless contains_pii?(string)

    # Email addresses
    string = string.gsub(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, '[EMAIL_REDACTED]')

    # Phone numbers
    string = string.gsub(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/, '[PHONE_REDACTED]')

    # Credit card numbers
    string = string.gsub(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/, '[CARD_REDACTED]')

    string
  end

  def contains_pii?(string)
    pii_patterns = [
      /@/,  # Email indicator
      /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,  # Phone pattern
      /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/  # Credit card pattern
    ]

    pii_patterns.any? { |pattern| string.match?(pattern) }
  end
end

# Secure step handler with audit trails
module CustomerSuccess
  module StepHandlers
    class ValidateRefundRequestHandler < Tasker::StepHandler::Base
      include PIISafeLogging

      def process(task, sequence, step)
        customer_id = task.context['customer_id']
        refund_amount = task.context['refund_amount']

        # Safe logging - no PII exposed
        log_sanitized("Validating refund request", {
          task_id: task.id,
          refund_amount: refund_amount,
          customer_id_hash: Digest::SHA256.hexdigest(customer_id)[0..8],  # Hash for tracking
          step_name: step.name
        })

        # Business logic with audit trail
        validation_result = with_audit_trail(
          action: 'validate_refund_eligibility',
          subject_type: 'customer',
          subject_id: customer_id,
          metadata: {
            refund_amount: refund_amount,
            validation_rules_version: '2.1.0'
          }
        ) do
          RefundEligibilityService.validate(customer_id, refund_amount)
        end

        unless validation_result.eligible?
          SecurityAuditLogger.log_refund_denial(
            customer_id: customer_id,
            refund_amount: refund_amount,
            denial_reason: validation_result.reason,
            user_id: AuthContext.current_user.id
          )

          raise Tasker::NonRetryableError, "Refund not eligible: #{validation_result.reason}"
        end

        {
          validated: true,
          eligibility_check_id: validation_result.id,
          max_refund_amount: validation_result.max_amount,
          requires_manager_approval: validation_result.requires_approval?,
          validated_at: Time.current.iso8601
        }
      end

      private

      def log_sanitized(message, data)
        Rails.logger.info({
          message: message,
          **sanitize_for_logs(data),
          timestamp: Time.current.iso8601,
          correlation_id: AuthContext.current_correlation_id
        }.to_json)
      end

      def with_audit_trail(action:, subject_type:, subject_id:, metadata: {})
        audit_entry = SecurityAuditLogger.start_audit(
          action: action,
          subject_type: subject_type,
          subject_id: subject_id,
          user_id: AuthContext.current_user.id,
          ip_address: AuthContext.current_ip,
          metadata: metadata
        )

        begin
          result = yield

          SecurityAuditLogger.complete_audit(audit_entry, {
            outcome: 'success',
            result_summary: sanitize_for_logs(result.class.name)
          })

          result
        rescue => e
          SecurityAuditLogger.complete_audit(audit_entry, {
            outcome: 'failure',
            error: e.class.name,
            error_message: sanitize_for_logs(e.message)
          })

          raise
        end
      end
    end
  end
end
```

## GDPR Compliance and Data Rights

They implemented comprehensive data rights management:

```ruby
# app/services/gdpr_compliance_service.rb
class GDPRComplianceService
  # Right to be forgotten - remove all PII from workflow data
  def self.process_erasure_request(customer_email)
    customer_id = find_customer_id(customer_email)

    # Find all workflows containing this customer's data
    affected_tasks = Tasker::Task.joins(:workflow_steps)
                                 .where("context::text ILIKE ?", "%#{customer_email}%")
                                 .or(Tasker::Task.where("context::text ILIKE ?", "%#{customer_id}%"))

    affected_tasks.each do |task|
      anonymize_task_data(task, customer_email, customer_id)
    end

    # Update audit logs
    SecurityAuditLogger.log_data_erasure(
      customer_email: customer_email,
      tasks_affected: affected_tasks.count,
      performed_by: AuthContext.current_user.id
    )
  end

  # Right of access - export all data for a customer
  def self.generate_data_export(customer_email)
    customer_id = find_customer_id(customer_email)

    # Find all workflow data
    workflows = Tasker::Task.where("context::text ILIKE ?", "%#{customer_email}%")
                           .or(Tasker::Task.where("context::text ILIKE ?", "%#{customer_id}%"))

    export_data = {
      customer_email: customer_email,
      data_extracted_at: Time.current.iso8601,
      workflows: workflows.map { |task| sanitize_task_for_export(task) }
    }

    # Log access request
    SecurityAuditLogger.log_data_access_request(
      customer_email: customer_email,
      export_size: export_data.to_json.bytesize,
      performed_by: AuthContext.current_user.id
    )

    export_data
  end

  private

  def self.anonymize_task_data(task, customer_email, customer_id)
    # Replace PII with anonymized versions
    anonymized_context = task.context.deep_dup
    anonymized_context = replace_pii_in_hash(anonymized_context, customer_email, customer_id)

    # Update task with anonymized data
    task.update!(
      context: anonymized_context,
      annotations: task.annotations.merge({
        'gdpr_anonymized_at': Time.current.iso8601,
        'original_customer_hash': Digest::SHA256.hexdigest(customer_email)
      })
    )

    # Anonymize step results as well
    task.workflow_steps.each do |step|
      if step.result.present?
        anonymized_result = replace_pii_in_hash(step.result, customer_email, customer_id)
        step.update!(result: anonymized_result)
      end
    end
  end

  def self.replace_pii_in_hash(data, email, customer_id)
    case data
    when Hash
      data.transform_values { |value| replace_pii_in_hash(value, email, customer_id) }
    when Array
      data.map { |item| replace_pii_in_hash(item, email, customer_id) }
    when String
      data.gsub(email, '[ANONYMIZED_EMAIL]')
          .gsub(customer_id, '[ANONYMIZED_ID]')
    else
      data
    end
  end
end
```

## Compliance Reporting and Monitoring

```ruby
# app/controllers/admin/compliance_controller.rb
class Admin::ComplianceController < ApplicationController
  before_action :require_compliance_officer_role

  def audit_report
    @date_range = parse_date_range(params[:date_range])
    @audit_entries = SecurityAuditLog.includes(:user)
                                    .where(created_at: @date_range)
                                    .order(created_at: :desc)

    @summary = {
      total_workflow_executions: @audit_entries.where(action: 'execute_workflow').count,
      unauthorized_attempts: @audit_entries.where(outcome: 'unauthorized').count,
      data_access_requests: @audit_entries.where(action: 'data_access_request').count,
      data_erasure_requests: @audit_entries.where(action: 'data_erasure').count,
      pii_workflows: count_pii_workflows(@date_range)
    }
  end

  def data_retention_report
    @retention_policy = {
      audit_logs: '7 years',
      workflow_data_with_pii: '3 years',
      workflow_data_without_pii: '5 years',
      anonymized_data: 'indefinite'
    }

    @data_volumes = {
      total_tasks: Tasker::Task.count,
      tasks_with_pii: Tasker::Task.where("annotations->>'contains_pii' = 'true'").count,
      audit_entries: SecurityAuditLog.count,
      anonymized_tasks: Tasker::Task.where("annotations ? 'gdpr_anonymized_at'").count
    }
  end

  def security_metrics
    @metrics = {
      authentication_failures: count_auth_failures_last_30_days,
      authorization_failures: count_authz_failures_last_30_days,
      workflows_by_classification: workflows_by_data_classification,
      users_by_permissions: users_by_workflow_permissions
    }
  end

  private

  def require_compliance_officer_role
    unless current_user.has_role?('compliance_officer')
      raise Tasker::AuthorizationError, 'Compliance officer role required'
    end
  end

  def count_pii_workflows(date_range)
    Tasker::Task.where(created_at: date_range)
                .where("annotations->>'contains_pii' = 'true'")
                .count
  end
end
```

## The Results

**Before Security Implementation:**
- Zero authentication or authorization controls
- PII and sensitive data logged in plaintext
- No audit trails or compliance capabilities
- No data classification or encryption
- Enterprise deals blocked by security requirements

**After Security Implementation:**
- Complete zero-trust architecture with JWT authentication
- Role-based permissions on all workflows and operations
- Comprehensive audit trails for all workflow executions
- PII-safe logging with automatic data classification
- GDPR compliance with data erasure and export capabilities
- SOC 2 Type II certification achieved
- Enterprise deals accelerated by security capabilities

The MegaCorp deal closed on schedule. More importantly, GrowthCorp became the security-first workflow platform that enterprise customers trusted with their most sensitive operations.

## Key Takeaways

1. **Implement zero-trust from day one** - Authentication and authorization should be built-in, not bolted-on

2. **Classify data automatically** - Know what data you're processing and apply appropriate protections

3. **Build audit trails into everything** - Compliance isn't optional for enterprise customers

4. **Sanitize logs religiously** - PII in logs is a compliance violation waiting to happen

5. **Plan for data rights** - GDPR and similar regulations require data erasure and export capabilities

6. **Monitor security continuously** - Security isn't a one-time implementation, it's an ongoing process

## Want to Try This Yourself?

The complete enterprise security workflow examples are available:

```bash
# One-line setup with full security stack
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/blog-examples/enterprise-security/setup.sh | bash

# Includes JWT auth, audit logging, and compliance tools
cd enterprise-security-demo
bundle exec rails server

# Try authenticated workflow execution
curl -X POST http://localhost:3000/auth/login \
  -d '{"email": "admin@company.com", "password": "demo123"}'

# Execute workflow with proper authentication
curl -X POST http://localhost:3000/workflows/execute \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"namespace": "customer_success", "name": "process_refund", "context": {...}}'

# View audit trails
open http://localhost:3000/admin/compliance/audit_report

# Test GDPR compliance
curl -X POST http://localhost:3000/gdpr/erasure_request \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"customer_email": "test@example.com"}'
```

## The Complete Journey

From fragile Black Friday checkouts to enterprise-grade security compliance, GrowthCorp's workflow transformation journey demonstrates how to build systems that scale from startup to enterprise without compromise.

The same patterns that made their checkout reliable made their data pipelines robust, their microservices coordinated, their teams organized, their systems observable, and their enterprise customers confident.

---

*Ready to transform your own workflows from chaos to enterprise-grade reliability? The complete journey starts with a single step.*
