class TopController < ApplicationController
  def index
    # 以下テスト用
    trans = Transaction.new
    if Rails.env == 'development'
      Currency.get_rates
      trans.sell_buy_coin
    end

    @transactions = JSON.parse(trans.read_transactions.body)

    @ticker = trans.get_ticker

    @balance = trans.get_balance

    @btc_rate = trans.get_rate('sell')

  end
end
