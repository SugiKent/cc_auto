class Bitcoin < ApplicationRecord

  # btcの買値のレートを保存していく
  def self.get_rate
    ['buy', 'sell'].each do |order_type|
      result = Transaction.new.get_rate(order_type)
      bitcoin = Bitcoin.new(order_type: order_type, rate: result['rate'])
      bitcoin.save
    end
  end

  def self.destroy_all_data
    bitcoins = Bitcoin.where('created_at < ?', Time.new.ago(6.months))
    bitcoins.delete_all
  end

end
