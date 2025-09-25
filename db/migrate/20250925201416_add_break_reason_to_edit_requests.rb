class AddBreakReasonToEditRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :edit_requests, :break_reason, :string
  end
end
