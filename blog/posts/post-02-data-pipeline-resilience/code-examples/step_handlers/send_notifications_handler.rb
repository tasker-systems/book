module DataPipeline
  module StepHandlers
    class SendNotificationsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        insights_data = step_results(sequence, 'generate_insights')
        dashboard_data = step_results(sequence, 'update_dashboard')
        
        notification_channels = task.context['notification_channels'] || ['#data-team']
        
        notifications_sent = []
        
        begin
          # Send completion notification
          completion_notification = send_completion_notification(notification_channels, insights_data, dashboard_data)
          notifications_sent << completion_notification
          
          # Send alert notifications for critical issues
          alert_notifications = send_alert_notifications(insights_data['performance_alerts'] || [])
          notifications_sent.concat(alert_notifications)
          
          # Send recommendation notifications to relevant teams
          recommendation_notifications = send_recommendation_notifications(insights_data['business_recommendations'] || [])
          notifications_sent.concat(recommendation_notifications)
          
          # Send summary email to stakeholders
          email_notification = send_summary_email(insights_data)
          notifications_sent << email_notification
          
          update_progress_annotation(step, "Sent #{notifications_sent.length} notifications successfully")
          
          {
            status: 'success',
            notifications_sent: notifications_sent.length,
            channels_notified: notification_channels,
            alerts_escalated: alert_notifications.length,
            teams_notified: get_teams_notified(recommendation_notifications),
            sent_at: Time.current.iso8601
          }
          
        rescue StandardError => e
          Rails.logger.error "Notification sending failed: #{e.class} - #{e.message}"
          raise Tasker::RetryableError, "Notification sending failed, will retry: #{e.message}"
        end
      end
      
      private
      
      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.result || {}
      end
      
      def send_completion_notification(channels, insights_data, dashboard_data)
        executive_summary = insights_data['executive_summary'] || {}
        period_overview = executive_summary['period_overview'] || {}
        
        message = build_completion_message(period_overview, dashboard_data)
        
        channels.each do |channel|
          SlackAPI.post_message(
            channel: channel,
            text: message,
            attachments: build_completion_attachments(executive_summary)
          )
        end
        
        {
          type: 'completion',
          channels: channels,
          message: 'Analytics pipeline completed successfully',
          sent_at: Time.current.iso8601
        }
      end
      
      def build_completion_message(period_overview, dashboard_data)
        revenue = period_overview['total_revenue'] || 0
        customers = period_overview['total_customers_analyzed'] || 0
        products = period_overview['total_products_analyzed'] || 0
        dashboards_updated = dashboard_data['dashboards_updated'] || []
        
        <<~MESSAGE
          ✅ **Customer Analytics Pipeline Completed**
          
          📊 **Data Processed:**
          • #{customers} customers analyzed
          • #{products} products evaluated  
          • $#{revenue.round(2)} revenue processed
          
          🎯 **Dashboards Updated:**
          #{dashboards_updated.map { |d| "• #{d.humanize}" }.join("\n")}
          
          📈 **View Results:** [Executive Dashboard](#{dashboard_link})
        MESSAGE
      end
      
      def build_completion_attachments(executive_summary)
        customer_highlights = executive_summary['customer_highlights'] || {}
        product_highlights = executive_summary['product_highlights'] || {}
        
        [
          {
            color: 'good',
            title: 'Customer Highlights',
            fields: [
              {
                title: 'VIP Customers',
                value: "#{customer_highlights['vip_customers_count'] || 0} (#{customer_highlights['vip_customers_percentage'] || 0}%)",
                short: true
              },
              {
                title: 'Avg Customer LTV',
                value: "$#{customer_highlights['average_customer_lifetime_value'] || 0}",
                short: true
              }
            ]
          },
          {
            color: 'warning',
            title: 'Action Items',
            fields: [
              {
                title: 'Reorders Needed',
                value: "#{product_highlights['products_needing_reorder'] || 0} products",
                short: true
              },
              {
                title: 'Top Category',
                value: product_highlights['top_performing_category'] || 'N/A',
                short: true
              }
            ]
          }
        ]
      end
      
      def send_alert_notifications(alerts)
        notifications = []
        
        critical_alerts = alerts.select { |alert| alert['severity'] == 'critical' }
        warning_alerts = alerts.select { |alert| alert['severity'] == 'warning' }
        
        # Send critical alerts immediately to on-call
        critical_alerts.each do |alert|
          notification = send_critical_alert(alert)
          notifications << notification
        end
        
        # Send warning alerts to relevant teams
        warning_alerts.each do |alert|
          notification = send_warning_alert(alert)
          notifications << notification
        end
        
        notifications
      end
      
      def send_critical_alert(alert)
        case alert['type']
        when 'customer_alert'
          # Page customer success team for high-value customer issues
          PagerDutyAPI.trigger_incident(
            summary: alert['title'],
            details: {
              message: alert['message'],
              customers_affected: alert['customers_affected'],
              revenue_at_risk: alert['revenue_at_risk']
            },
            urgency: 'high'
          )
          
          SlackAPI.post_message(
            channel: '#customer-success-alerts',
            text: "🚨 **CRITICAL CUSTOMER ALERT**\n#{alert['message']}\n💰 Revenue at risk: $#{alert['revenue_at_risk']}"
          )
          
        when 'inventory_alert'
          # Alert operations team for stock issues
          SlackAPI.post_message(
            channel: '#operations-alerts',
            text: "🚨 **CRITICAL INVENTORY ALERT**\n#{alert['message']}\n📦 Products affected: #{alert['products_affected'].join(', ')}"
          )
          
          # Also send email to procurement team
          EmailService.send_alert_email(
            to: ['procurement@company.com', 'operations@company.com'],
            subject: 'URGENT: Products Out of Stock',
            body: build_inventory_alert_email(alert)
          )
        end
        
        {
          type: 'critical_alert',
          alert_type: alert['type'],
          message: alert['message'],
          escalated_to: determine_escalation_target(alert['type']),
          sent_at: Time.current.iso8601
        }
      end
      
      def send_warning_alert(alert)
        case alert['type']
        when 'profitability_alert'
          SlackAPI.post_message(
            channel: '#product-management',
            text: "⚠️ **Profitability Warning**\n#{alert['message']}\n📋 Products: #{alert['products_affected'].join(', ')}"
          )
        end
        
        {
          type: 'warning_alert',
          alert_type: alert['type'],
          message: alert['message'],
          sent_to: determine_warning_target(alert['type']),
          sent_at: Time.current.iso8601
        }
      end
      
      def send_recommendation_notifications(recommendations)
        notifications = []
        
        recommendations.each do |recommendation|
          notification = send_team_recommendation(recommendation)
          notifications << notification
        end
        
        notifications
      end
      
      def send_team_recommendation(recommendation)
        team_channel = determine_team_channel(recommendation['type'])
        
        message = build_recommendation_message(recommendation)
        
        SlackAPI.post_message(
          channel: team_channel,
          text: message,
          attachments: [
            {
              color: priority_color(recommendation['priority']),
              title: recommendation['title'],
              text: recommendation['description'],
              fields: [
                {
                  title: 'Expected Impact',
                  value: recommendation['impact'],
                  short: false
                },
                {
                  title: 'Action Items',
                  value: recommendation['action_items'].map { |item| "• #{item}" }.join("\n"),
                  short: false
                }
              ]
            }
          ]
        )
        
        {
          type: 'recommendation',
          recommendation_type: recommendation['type'],
          priority: recommendation['priority'],
          team_notified: team_channel,
          sent_at: Time.current.iso8601
        }
      end
      
      def send_summary_email(insights_data)
        executive_summary = insights_data['executive_summary'] || {}
        alerts = insights_data['performance_alerts'] || []
        recommendations = insights_data['business_recommendations'] || []
        
        EmailService.send_analytics_summary(
          to: ['executives@company.com', 'analytics-stakeholders@company.com'],
          subject: "Daily Analytics Summary - #{Date.current.strftime('%B %d, %Y')}",
          body: build_summary_email_body(executive_summary, alerts, recommendations),
          html_body: build_summary_email_html(executive_summary, alerts, recommendations)
        )
        
        {
          type: 'summary_email',
          recipients: ['executives@company.com', 'analytics-stakeholders@company.com'],
          alerts_included: alerts.length,
          recommendations_included: recommendations.length,
          sent_at: Time.current.iso8601
        }
      end
      
      def build_recommendation_message(recommendation)
        priority_emoji = case recommendation['priority']
                        when 'high' then '🔥'
                        when 'medium' then '⚠️'
                        when 'low' then '💡'
                        else '📋'
                        end
        
        "#{priority_emoji} **#{recommendation['title']}** (#{recommendation['priority']} priority)\n#{recommendation['description']}"
      end
      
      def determine_team_channel(recommendation_type)
        case recommendation_type
        when 'customer_retention', 'customer_onboarding'
          '#customer-success'
        when 'product_optimization', 'revenue_optimization'
          '#product-management'
        when 'inventory_management'
          '#operations'
        else
          '#general'
        end
      end
      
      def determine_escalation_target(alert_type)
        case alert_type
        when 'customer_alert'
          'customer_success_oncall'
        when 'inventory_alert'
          'operations_team'
        else
          'general_oncall'
        end
      end
      
      def determine_warning_target(alert_type)
        case alert_type
        when 'profitability_alert'
          'product_management'
        else
          'analytics_team'
        end
      end
      
      def priority_color(priority)
        case priority
        when 'high'
          'danger'
        when 'medium'
          'warning'
        when 'low'
          'good'
        else
          '#439FE0'
        end
      end
      
      def build_inventory_alert_email(alert)
        <<~EMAIL
          URGENT: Critical Inventory Alert
          
          #{alert['message']}
          
          Products Affected:
          #{alert['products_affected'].map { |product| "• #{product}" }.join("\n")}
          
          Immediate Actions Required:
          1. Check supplier lead times for these products
          2. Place emergency orders if possible
          3. Update website inventory status
          4. Notify customer service team of potential delays
          
          Please respond to this email when action has been taken.
          
          Analytics Team
        EMAIL
      end
      
      def build_summary_email_body(executive_summary, alerts, recommendations)
        period_overview = executive_summary['period_overview'] || {}
        customer_highlights = executive_summary['customer_highlights'] || {}
        
        <<~EMAIL
          Daily Analytics Summary - #{Date.current.strftime('%B %d, %Y')}
          
          EXECUTIVE OVERVIEW
          ==================
          Revenue: $#{period_overview['total_revenue']}
          Profit: $#{period_overview['total_profit']} (#{period_overview['profit_margin']}% margin)
          Customers Analyzed: #{period_overview['total_customers_analyzed']}
          Products Analyzed: #{period_overview['total_products_analyzed']}
          
          CUSTOMER HIGHLIGHTS
          ===================
          Average Customer LTV: $#{customer_highlights['average_customer_lifetime_value']}
          VIP Customers: #{customer_highlights['vip_customers_count']} (#{customer_highlights['vip_customers_percentage']}%)
          New Customers: #{customer_highlights['new_customers_count']}
          
          ALERTS (#{alerts.length})
          #{alerts.empty? ? 'No alerts today' : alerts.map { |a| "• #{a['title']}: #{a['message']}" }.join("\n")}
          
          RECOMMENDATIONS (#{recommendations.length})
          #{recommendations.empty? ? 'No new recommendations' : recommendations.map { |r| "• #{r['title']} (#{r['priority']} priority)" }.join("\n")}
          
          View full dashboard: #{dashboard_link}
          
          Questions? Reply to this email or contact the analytics team.
        EMAIL
      end
      
      def build_summary_email_html(executive_summary, alerts, recommendations)
        # HTML version would be more detailed with charts and formatting
        # For now, return a simple HTML wrapper
        "<html><body><pre>#{build_summary_email_body(executive_summary, alerts, recommendations)}</pre></body></html>"
      end
      
      def dashboard_link
        "https://dashboard.company.com/analytics/executive"
      end
      
      def get_teams_notified(recommendation_notifications)
        recommendation_notifications.map { |n| n[:team_notified] }.uniq
      end
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
    end
    
    # Mock services for demo purposes
    class SlackAPI
      def self.post_message(channel:, text:, attachments: nil)
        Rails.logger.info "Slack Message Sent to #{channel}: #{text}"
        Rails.logger.info "Attachments: #{attachments.to_json}" if attachments
      end
    end
    
    class PagerDutyAPI
      def self.trigger_incident(summary:, details:, urgency:)
        Rails.logger.info "PagerDuty Incident: #{summary} (#{urgency})"
        Rails.logger.info "Details: #{details.to_json}"
      end
    end
    
    class EmailService
      def self.send_alert_email(to:, subject:, body:)
        Rails.logger.info "Alert Email Sent to #{to.join(', ')}: #{subject}"
      end
      
      def self.send_analytics_summary(to:, subject:, body:, html_body:)
        Rails.logger.info "Summary Email Sent to #{to.join(', ')}: #{subject}"
      end
    end
  end
end