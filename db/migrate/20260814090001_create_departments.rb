class CreateDepartments < ActiveRecord::Migration[7.1]
  def change
    create_table :departments do |t|
      t.string  :name, null: false
      t.string  :code
      t.integer :position, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :departments, :name, unique: true
  end
end
