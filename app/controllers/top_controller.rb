class TopController < ApplicationController
  def index
    Currency.get_rates

    trans = Transaction.new
    binding.pry
    if Rails.env == 'development'
      trans.sell_buy_coin
    end

  end
end
