class TopController < ApplicationController
  def index
    Currency.get_rates

    trans = Transaction.new
    if Rails.env == 'development'
      trans.sell_buy_coin
    end

  end
end
