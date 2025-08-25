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
    column :total_duration
    column :status
    actions
  end
end
