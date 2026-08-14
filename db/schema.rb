# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_08_14_090006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_admin_comments", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "admin"
    t.string "department"
    t.bigint "role_id"
    t.bigint "department_id"
    t.index ["department_id"], name: "index_admin_users_on_department_id"
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_admin_users_on_role"
    t.index ["role_id"], name: "index_admin_users_on_role_id"
  end

  create_table "approval_flows", force: :cascade do |t|
    t.string "name", null: false
    t.string "subject_type", null: false
    t.string "request_type"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "request_type"], name: "index_approval_flows_on_subject_type_and_request_type", unique: true
  end

  create_table "approval_steps", force: :cascade do |t|
    t.bigint "approval_flow_id", null: false
    t.bigint "role_id", null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.boolean "optional", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approval_flow_id", "position"], name: "index_approval_steps_on_approval_flow_id_and_position"
    t.index ["approval_flow_id"], name: "index_approval_steps_on_approval_flow_id"
    t.index ["role_id"], name: "index_approval_steps_on_role_id"
  end

  create_table "approvals", force: :cascade do |t|
    t.string "approvable_type", null: false
    t.bigint "approvable_id", null: false
    t.bigint "approval_step_id", null: false
    t.string "approver_type"
    t.bigint "approver_id"
    t.string "status", default: "pending", null: false
    t.integer "position", default: 0, null: false
    t.text "note"
    t.datetime "acted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approvable_type", "approvable_id", "position"], name: "index_approvals_on_approvable_and_position"
    t.index ["approvable_type", "approvable_id"], name: "index_approvals_on_approvable"
    t.index ["approval_step_id"], name: "index_approvals_on_approval_step_id"
    t.index ["approver_type", "approver_id"], name: "index_approvals_on_approver"
    t.index ["status"], name: "index_approvals_on_status"
  end

  create_table "breaks", force: :cascade do |t|
    t.bigint "time_clock_id", null: false
    t.datetime "break_in"
    t.datetime "break_out"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "break_type"
    t.index ["time_clock_id"], name: "index_breaks_on_time_clock_id"
  end

  create_table "departments", force: :cascade do |t|
    t.string "name", null: false
    t.string "code"
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_departments_on_name", unique: true
  end

  create_table "edit_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "time_clock_id", null: false
    t.datetime "requested_clock_in"
    t.text "reason"
    t.string "status"
    t.text "manager_note"
    t.datetime "resolved_at"
    t.string "department"
    t.boolean "approved_by_manager"
    t.boolean "approved_by_admin"
    t.string "request_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "break_reason"
    t.index ["time_clock_id"], name: "index_edit_requests_on_time_clock_id"
    t.index ["user_id"], name: "index_edit_requests_on_user_id"
  end

  create_table "leaves", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "leave_type"
    t.date "start_date"
    t.date "end_date"
    t.text "reason"
    t.string "status"
    t.boolean "approved_by_manager", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_leaves_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "message", null: false
    t.string "url", default: "/"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.string "kind", null: false
    t.string "subject"
    t.string "action"
    t.string "key", null: false
    t.string "label", null: false
    t.string "group"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_permissions_on_key", unique: true
    t.index ["kind", "subject"], name: "index_permissions_on_kind_and_subject"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh_key", null: false
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "scope", default: "employee", null: false
    t.integer "rank", default: 100, null: false
    t.text "description"
    t.boolean "system", default: false, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
    t.index ["scope"], name: "index_roles_on_scope"
    t.index ["slug"], name: "index_roles_on_slug", unique: true
  end

  create_table "time_clocks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "clock_in"
    t.datetime "clock_out"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "total_duration"
    t.string "status"
    t.integer "break_duration"
    t.string "current_state"
    t.string "ip_address"
    t.index ["user_id"], name: "index_time_clocks_on_user_id"
  end

  create_table "user_managers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "manager_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["manager_id"], name: "index_user_managers_on_manager_id"
    t.index ["user_id", "manager_id"], name: "index_user_managers_on_user_id_and_manager_id", unique: true
    t.index ["user_id"], name: "index_user_managers_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name"
    t.string "phone_number"
    t.string "address"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "department"
    t.time "shift_time", default: "2000-01-01 18:00:00"
    t.string "status"
    t.boolean "employeed", default: true
    t.string "sudo_name"
    t.bigint "role_id"
    t.bigint "department_id"
    t.bigint "reports_to_id"
    t.index ["department_id"], name: "index_users_on_department_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reports_to_id"], name: "index_users_on_reports_to_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role_id"], name: "index_users_on_role_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_users", "departments"
  add_foreign_key "admin_users", "roles"
  add_foreign_key "approval_steps", "approval_flows"
  add_foreign_key "approval_steps", "roles"
  add_foreign_key "approvals", "approval_steps"
  add_foreign_key "breaks", "time_clocks"
  add_foreign_key "edit_requests", "time_clocks"
  add_foreign_key "edit_requests", "users"
  add_foreign_key "leaves", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "time_clocks", "users"
  add_foreign_key "user_managers", "users"
  add_foreign_key "user_managers", "users", column: "manager_id"
  add_foreign_key "users", "departments"
  add_foreign_key "users", "roles"
  add_foreign_key "users", "users", column: "reports_to_id"
end
