ActiveAdmin.register TimeClock do
  belongs_to :user, optional: true

  permit_params :user_id, :clock_in, :clock_out, :total_duration, :status, :break_duration

  actions :all, except: [:new, :create]


  # Add filters so Ransack knows about them
  filter :user_id, as: :numeric
  filter :user_email, as: :string  # works if you want to filter by user email
  filter :clock_in
  filter :clock_out
  filter :status

  index do
    selectable_column
    column :user
    column :clock_in
    column :clock_out
    column "Total Duration" do |time_clock|
      time_clock.formatted_duration(time_clock.total_duration)
    end
    column :status do |tc|
      case tc.status
      when "late"
        span "Late", style: "background-color: #e74c3c; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      when "on_time"
        span "On Time", style: "background-color: #2ecc71; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      else
        span tc.status || "N/A", style: "background-color: #bdc3c7; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      end
    end
    actions
  end
end
