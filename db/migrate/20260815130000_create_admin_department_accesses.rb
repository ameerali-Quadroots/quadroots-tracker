class CreateAdminDepartmentAccesses < ActiveRecord::Migration[7.1]
  def change
    create_table :admin_department_accesses do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :department, null: false, foreign_key: true

      t.timestamps
    end

    add_index :admin_department_accesses, [:admin_user_id, :department_id],
              unique: true, name: "index_admin_dept_access_on_admin_and_dept"

    # Backfill: admins previously scoped to the "HOD'S" department saw
    # WEB/SEO/ADS/CONTENT via a hardcoded special case in app/admin/dashboard.rb
    # and app/admin/time_clocks.rb. Grant that as explicit access rows so the
    # generic viewable_department_names lookup replaces the hardcoded case
    # without changing anyone's existing visibility.
    reversible do |dir|
      dir.up do
        hods_department_id = execute("SELECT id FROM departments WHERE name = 'HOD''S' LIMIT 1").first&.fetch("id", nil)
        next unless hods_department_id

        target_ids = execute(
          "SELECT id FROM departments WHERE name IN ('WEB', 'SEO', 'ADS', 'CONTENT')"
        ).map { |row| row["id"] }
        next if target_ids.empty?

        admin_ids = execute(
          "SELECT id FROM admin_users WHERE department_id = #{hods_department_id}"
        ).map { |row| row["id"] }

        now = Time.current
        admin_ids.each do |admin_id|
          target_ids.each do |dept_id|
            execute(<<~SQL.squish)
              INSERT INTO admin_department_accesses (admin_user_id, department_id, created_at, updated_at)
              VALUES (#{admin_id}, #{dept_id}, '#{now.to_fs(:db)}', '#{now.to_fs(:db)}')
              ON CONFLICT DO NOTHING
            SQL
          end
        end
      end
    end
  end
end
