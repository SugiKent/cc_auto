class CreateCurrencies < ActiveRecord::Migration[5.1]
  def change
    create_table :currencies do |t|
      t.integer :type, null: false
      t.integer :rate, null: false

      t.timestamps
    end
  end
end
