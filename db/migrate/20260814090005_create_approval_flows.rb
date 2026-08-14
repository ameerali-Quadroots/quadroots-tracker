class CreateApprovalFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :approval_flows do |t|
      t.string  :name, null: false
      # What this flow approves, e.g. "EditRequest" or "Leave".
      t.string  :subject_type, null: false
      # Narrows the flow to one request_type; null = the catch-all for that subject.
      t.string  :request_type
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :approval_flows, [:subject_type, :request_type], unique: true

    create_table :approval_steps do |t|
      t.references :approval_flow, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.string  :name
      t.integer :position, default: 0, null: false
      # An optional step can be skipped when nobody holds the role.
      t.boolean :optional, default: false, null: false
      t.timestamps
    end

    add_index :approval_steps, [:approval_flow_id, :position]

    create_table :approvals do |t|
      t.references :approvable, polymorphic: true, null: false
      t.references :approval_step, null: false, foreign_key: true
      t.references :approver, polymorphic: true, null: true
      t.string   :status, default: "pending", null: false
      t.integer  :position, default: 0, null: false
      t.text     :note
      t.datetime :acted_at
      t.timestamps
    end

    add_index :approvals, [:approvable_type, :approvable_id, :position],
              name: "index_approvals_on_approvable_and_position"
    add_index :approvals, :status
  end
end
