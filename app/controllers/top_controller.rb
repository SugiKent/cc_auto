class TopController < ApplicationController
  def index
    # key = ENV['CC_API_KEY']
    # secret = ENV['CC_API_SECRET']
    # uri = URI.parse "https://coincheck.com/api/accounts/balance"
    # nonce = Time.now.to_i.to_s
    # message = nonce + uri.to_s
    # signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, message)
    # headers = {
    #   "ACCESS-KEY" => key,
    #   "ACCESS-NONCE" => nonce,
    #   "ACCESS-SIGNATURE" => signature
    # }
    #
    # https = Net::HTTP.new(uri.host, uri.port)
    # https.use_ssl = true
    # response = https.start {
    #   https.get(uri.request_uri, headers)
    # }
    # puts response.body
    #
    # uri = URI.parse 'https://coincheck.com/api/rate/btc_jpy'
    # json = Net::HTTP.get(uri)
    # result = JSON.parse(json)
    # puts result

    Currency.get_rates

    trans = Transaction.new
    trans.sell_buy_coin

    # Currency.calc_rates
  end
end
