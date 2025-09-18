class AddIpAddressToTimeclocks < ActiveRecord::Migration[7.1]
  def change
    add_column :time_clocks, :ip_address, :string
  end
end
