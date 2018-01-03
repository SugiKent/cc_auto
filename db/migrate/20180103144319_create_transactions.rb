class CreateTransactions < ActiveRecord::Migration[5.1]
  def change
    create_table :transactions do |t|
      t.integer :type, null: false
      t.integer :amount, null: false
      t.integer :rate, null: false
      t.string :order_type, null: false

      t.timestamps
    end
  end
end
