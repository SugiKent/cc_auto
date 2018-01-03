class Bitcoin < ApplicationRecord

  # btcの買値のレートを保存していく
  def self.get_rate
    ['buy', 'sell'].each do |order_type|
      result = Transaction.new.get_rate(order_type)
      bitcoin = Bitcoin.new(order_type: order_type, rate: result['rate'])
      bitcoin.save
    end
  end

end
