class AddBreakTypeToBreaks < ActiveRecord::Migration[7.1]
  def change
    add_column :breaks, :break_type, :string
  end
end
