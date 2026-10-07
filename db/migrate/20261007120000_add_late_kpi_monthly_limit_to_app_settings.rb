class AddLateKpiMonthlyLimitToAppSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :app_settings, :late_kpi_monthly_limit, :integer, default: 3, null: false
  end
end
