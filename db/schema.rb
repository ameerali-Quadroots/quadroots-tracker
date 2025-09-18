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

ActiveRecord::Schema[7.1].define(version: 2025_09_17_152243) do
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

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "admin"
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_admin_users_on_role"
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
    t.index ["time_clock_id"], name: "index_edit_requests_on_time_clock_id"
    t.index ["user_id"], name: "index_edit_requests_on_user_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "breaks", "time_clocks"
  add_foreign_key "edit_requests", "time_clocks"
  add_foreign_key "edit_requests", "users"
  add_foreign_key "time_clocks", "users"
end
