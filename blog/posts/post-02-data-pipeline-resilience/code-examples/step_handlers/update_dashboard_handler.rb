module DataPipeline
  module StepHandlers
    class UpdateDashboardHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        insights_data = step_results(sequence, 'generate_insights')
        
        # Update the executive dashboard with new insights
        dashboard_update = {
          last_updated: Time.current.iso8601,
          data_freshness: 'current',
          executive_summary: insights_data['executive_summary'],
          key_metrics: extract_key_metrics(insights_data),
          alerts: insights_data['performance_alerts'] || [],
          recommendations: insights_data['business_recommendations'] || []
        }
        
        begin
          # Simulate dashboard API update
          update_executive_dashboard(dashboard_update)
          update_operational_dashboards(insights_data)
          update_team_dashboards(insights_data)
          
          update_progress_annotation(step, "Successfully updated all dashboards")
          
          {
            status: 'success',
            dashboards_updated: ['executive', 'operations', 'customer_success', 'product_management'],
            update_timestamp: Time.current.iso8601,
            data_points_updated: count_data_points(insights_data),
            alert_count: (insights_data['performance_alerts'] || []).length,
            recommendation_count: (insights_data['business_recommendations'] || []).length
          }
          
        rescue StandardError => e
          Rails.logger.error "Dashboard update failed: #{e.class} - #{e.message}"
          raise Tasker::RetryableError, "Dashboard update failed, will retry: #{e.message}"
        end
      end
      
      private
      
      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.result || {}
      end
      
      def extract_key_metrics(insights_data)
        executive_summary = insights_data['executive_summary'] || {}
        customer_insights = insights_data['customer_insights'] || {}
        product_insights = insights_data['product_insights'] || {}
        
        {
          revenue: {
            total: executive_summary.dig('period_overview', 'total_revenue') || 0,
            profit: executive_summary.dig('period_overview', 'total_profit') || 0,
            margin: executive_summary.dig('period_overview', 'profit_margin') || 0
          },
          customers: {
            total_analyzed: executive_summary.dig('period_overview', 'total_customers_analyzed') || 0,
            vip_count: executive_summary.dig('customer_highlights', 'vip_customers_count') || 0,
            avg_lifetime_value: executive_summary.dig('customer_highlights', 'average_customer_lifetime_value') || 0,
            at_risk_count: customer_insights.dig('churn_risk', 'customers_at_risk') || 0
          },
          products: {
            total_analyzed: executive_summary.dig('period_overview', 'total_products_analyzed') || 0,
            reorder_needed: executive_summary.dig('product_highlights', 'products_needing_reorder') || 0,
            high_margin_count: executive_summary.dig('product_highlights', 'high_margin_products') || 0,
            top_category: executive_summary.dig('product_highlights', 'top_performing_category')
          },
          alerts: {
            critical_count: (insights_data['performance_alerts'] || []).count { |a| a['severity'] == 'critical' },
            warning_count: (insights_data['performance_alerts'] || []).count { |a| a['severity'] == 'warning' }
          }
        }
      end
      
      def update_executive_dashboard(dashboard_data)
        # Simulate updating executive dashboard
        # In real implementation, this would call dashboard API
        
        Rails.logger.info "Updating executive dashboard with latest analytics"
        
        # Update main KPI widgets
        DashboardAPI.update_widget('revenue_overview', {
          total_revenue: dashboard_data[:key_metrics][:revenue][:total],
          profit_margin: dashboard_data[:key_metrics][:revenue][:margin],
          last_updated: dashboard_data[:last_updated]
        })
        
        DashboardAPI.update_widget('customer_metrics', {
          total_customers: dashboard_data[:key_metrics][:customers][:total_analyzed],
          vip_customers: dashboard_data[:key_metrics][:customers][:vip_count],
          avg_clv: dashboard_data[:key_metrics][:customers][:avg_lifetime_value],
          last_updated: dashboard_data[:last_updated]
        })
        
        DashboardAPI.update_widget('product_performance', {
          products_analyzed: dashboard_data[:key_metrics][:products][:total_analyzed],
          reorder_alerts: dashboard_data[:key_metrics][:products][:reorder_needed],
          top_category: dashboard_data[:key_metrics][:products][:top_category],
          last_updated: dashboard_data[:last_updated]
        })
        
        # Update alerts section
        DashboardAPI.update_alerts(dashboard_data[:alerts])
        
        # Update recommendations
        DashboardAPI.update_recommendations(dashboard_data[:recommendations])
        
        Rails.logger.info "Executive dashboard updated successfully"
      end
      
      def update_operational_dashboards(insights_data)
        # Update operations team dashboard with inventory and fulfillment metrics
        product_insights = insights_data['product_insights'] || {}
        
        inventory_data = {
          reorder_needed: product_insights.dig('inventory', 'reorder_needed_products') || [],
          fast_movers: product_insights.dig('inventory', 'fast_movers_count') || 0,
          slow_movers: product_insights.dig('inventory', 'slow_movers_count') || 0,
          last_updated: Time.current.iso8601
        }
        
        DashboardAPI.update_dashboard('operations', 'inventory_management', inventory_data)
        
        Rails.logger.info "Operations dashboard updated with inventory metrics"
      end
      
      def update_team_dashboards(insights_data)
        customer_insights = insights_data['customer_insights'] || {}
        product_insights = insights_data['product_insights'] || {}
        
        # Customer Success team dashboard
        customer_success_data = {
          at_risk_customers: customer_insights.dig('churn_risk', 'customers_at_risk') || 0,
          high_value_customers: customer_insights.dig('high_value_analysis', 'high_value_customer_count') || 0,
          engagement_opportunities: customer_insights.dig('marketing_insights', 'recent_customers_needing_engagement') || 0,
          last_updated: Time.current.iso8601
        }
        
        DashboardAPI.update_dashboard('customer_success', 'retention_metrics', customer_success_data)
        
        # Product Management team dashboard
        product_management_data = {
          top_performers: product_insights.dig('performance', 'top_performers') || [],
          underperformers: product_insights.dig('performance', 'underperformers_count') || 0,
          category_performance: product_insights['category_performance'] || {},
          last_updated: Time.current.iso8601
        }
        
        DashboardAPI.update_dashboard('product_management', 'product_metrics', product_management_data)
        
        Rails.logger.info "Team dashboards updated successfully"
      end
      
      def count_data_points(insights_data)
        count = 0
        
        # Count metrics in each section
        count += count_nested_values(insights_data['executive_summary'])
        count += count_nested_values(insights_data['customer_insights'])
        count += count_nested_values(insights_data['product_insights'])
        count += (insights_data['performance_alerts'] || []).length
        count += (insights_data['business_recommendations'] || []).length
        
        count
      end
      
      def count_nested_values(hash, depth = 0)
        return 0 unless hash.is_a?(Hash)
        return 0 if depth > 3  # Prevent infinite recursion
        
        count = 0
        hash.each_value do |value|
          if value.is_a?(Hash)
            count += count_nested_values(value, depth + 1)
          elsif value.is_a?(Array)
            count += value.length
          else
            count += 1
          end
        end
        count
      end
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
    end
    
    # Mock Dashboard API for demo purposes
    class DashboardAPI
      def self.update_widget(widget_name, data)
        Rails.logger.info "Dashboard Widget Updated: #{widget_name} - #{data.to_json}"
      end
      
      def self.update_alerts(alerts)
        Rails.logger.info "Dashboard Alerts Updated: #{alerts.length} alerts"
      end
      
      def self.update_recommendations(recommendations)
        Rails.logger.info "Dashboard Recommendations Updated: #{recommendations.length} recommendations"
      end
      
      def self.update_dashboard(team, section, data)
        Rails.logger.info "Team Dashboard Updated: #{team}/#{section} - #{data.keys.join(', ')}"
      end
    end
  end
end