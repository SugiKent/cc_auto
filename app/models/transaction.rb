require 'net/http'
require 'uri'
require 'openssl'
require 'json'

class Transaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  enum type: [
    :btc,
    :eth,
    :etc,
    :lsk,
    :fct,
    :xmr,
    :rep,
    :xrp,
    :zec,
    :xem,
    :ltc,
    :dash,
    :bch
  ]

  def sell_buy_coin
    key = ENV['CC_API_KEY']
    secret = ENV['CC_API_SECRET']

    # 取引を実行するかどうか
    # check_rateの結果がfalseのtrueでない限り、取引を実行せずにreturn falseする
    return false unless check_rate

    amount = 0.005
    # 最後の取引が"買い"なら、"売る"
    order_type = if Transaction.last.order_type == 'buy'
      'sell'
    else
      'buy'
    end
    rate = get_rate(order_type)

    body = {
      rate: rate['rate'].to_i,
      amount: amount,
      order_type: order_type,
      pair: 'btc_jpy',
      market_buy_amount: nil,
      position_id: nil,
    }

    uri = URI.parse "https://coincheck.com/api/exchange/orders"
    headers = get_signature(uri, key, secret, body.to_json)
    if Rails.env == 'production'
      puts "POSTでの#{order_type}を開始"
      request_for_post(uri, headers, body)

      trans = Transaction.new(type: 0, amount: amount, rate: rate['rate'].to_i, order_type: order_type)
      trans.save
      puts "POSTでの#{order_type}を完了"
    else
      puts '開発環境のため売買行わず'
    end

  end

  def get_rate(order_type)
    # 1BTC当たりのorder_typeのレートを取得する
    uri = URI.parse "https://coincheck.com/api/exchange/orders/rate?order_type=#{order_type}&pair=btc_jpy&amount=1"
    json = Net::HTTP.get(uri)
    result = JSON.parse(json)

    result
  end

  def check_rate
    puts "\n\n------------------------\n" + Time.zone.now.to_s + "\nTransaction#check_rateを実行"
    past_trans = Transaction.last

    puts "最後の取引が[#{past_trans.order_type}]で、レートは#{past_trans.rate}円"

    if past_trans.order_type == 'buy'
      # 前回は買った = 今回は売る
      # 前回のrateよりも、3000円now_rateが高ければ売る

      # 現在の売値レート
      now_rate = get_rate('sell')

      # 過去1000分のデータからの平均値
      bitcoins = Bitcoin.where(order_type: 'sell').limit(1000)
      bitcoins_avg = bitcoins.pluck(:rate).inject(0.0){|r,i| r+=i } / bitcoins.size

      puts "過去のbtcの平均値は、#{bitcoins_avg}円\n現在のレートは、#{now_rate['rate']}円"

      which = now_rate['rate'].to_i > bitcoins_avg || now_rate['rate'].to_i > past_trans.rate + 3000
      puts "判定の結果：売りは#{which}"
      which
    elsif past_trans.order_type == 'sell'
      # 前回は売った = 今回は買う
      # 前回のrateよりも、5000円now_rateが低ければ買う
      # 5000円にしているのは、それくらいの回復力がbtcにはあるであろうから

      # 現在の買値レート
      now_rate = get_rate('buy')

      # 過去1000分のデータからの平均値
      bitcoins = Bitcoin.where(order_type: 'buy').limit(1000)
      bitcoins_avg = bitcoins.pluck(:rate).inject(0.0){|r,i| r+=i } / bitcoins.size

      puts "過去のbtcの平均値は#{bitcoins_avg}円\n現在のレートは、#{now_rate['rate']}円"

      if now_rate['rate'].to_i > 2000000
        # 200万円を超えている場合は買わない
        puts '200万円を超えているため、購入を見送りました。'
        return false
      else
        which = now_rate['rate'].to_i < bitcoins_avg + 1000 && now_rate['rate'].to_i < past_trans.rate - 2000
        puts "判定の結果：購入は#{which}"
        which
      end
    end
  end

  private

  def http_request(uri, request)
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE

    response = https.start do |h|
      h.request(request)
    end

  end

  def get_signature(uri, key, secret, body = "")
    nonce = (Time.now.to_f * 1000000).to_i.to_s
    message = nonce + uri.to_s + body
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, message)
    headers = {
      "ACCESS-KEY" => key,
      "ACCESS-NONCE" => nonce,
      "ACCESS-SIGNATURE" => signature
    }
  end

  def request_for_post(uri, headers, body)
    request = Net::HTTP::Post.new(uri.request_uri, initheader = custom_header(headers))
    request.body = body.to_json
    http_request(uri, request)
  end

  def custom_header(headers = {})
    headers.merge!({
      "Content-Type" => "application/json"
    })
  end

end
