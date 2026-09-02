class CreateClientsProjectsAndSprints < ActiveRecord::Migration[7.1]
  def change
    create_table :clients do |t|
      t.string :name, null: false
      t.references :department, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end
    add_index :clients, %i[department_id name], unique: true

    create_table :projects do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "planned"
      t.date :start_date
      t.date :target_end_date
      t.timestamps
    end
    add_index :projects, %i[client_id name], unique: true

    create_table :sprints do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :goal
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: "planned"
      t.timestamps
    end
    add_index :sprints, %i[project_id name], unique: true
    add_index :sprints, %i[project_id start_date]
  end
end
