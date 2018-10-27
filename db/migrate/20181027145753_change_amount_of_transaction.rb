class ChangeAmountOfTransaction < ActiveRecord::Migration[5.1]
  def change
      change_column :transactions, :amount, :string
  end
end
