class TopController < ApplicationController
  def index
    # 以下テスト用
    Currency.get_rates
    trans = Transaction.new
    if Rails.env == 'production'
      trans.sell_buy_coin
    end

  end
end
