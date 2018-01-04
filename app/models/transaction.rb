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

    # .envのTRANS_ON環境変数で取引するかを切り替える
    trans_on = ENV['TRANS_ON']
    return false unless trans_on == 'go'

    # 取引を実行するかどうか
    # check_rateの結果がtrueでない限り、取引を実行せずにreturn falseする
    return false unless check_rate

    amount = 0.005

    # 最後の取引が"買い"なら、"売る"
    if Transaction.last.order_type == 'buy'
      # 売る場合
      order_type = 'sell'
      rate = get_rate(order_type)

      # 相場より500円あげた指値で売る
      price = rate['rate'].to_i + 500
    else
      # 買う場合
      order_type = 'buy'
      rate = get_rate(order_type)

      # 相場より500円下げた指値で買う
      price = rate['rate'].to_i - 500
    end

    # order_typeを元にレートを取得
    rate = get_rate(order_type)

    body = {
      rate: price,
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

      # amountがFloat型のためデータ登録できず
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

  def get_ticker
    # 1BTC当たりのorder_typeのレートを取得する
    uri = URI.parse "https://coincheck.com/api/ticker"
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

      # 現在の売値レート
      now_rate = get_rate('sell')

      puts "現在のレートは#{now_rate['rate']}円"

      # 前回の[購入]より、レートが3000円高くなっていたら売る
      which = now_rate['rate'].to_i > past_trans.rate + 3000

      # 損切り判断
      # 前回の[購入]レートより、現在のレートが3000円低くなっていたら売る
      # which = now_rate['rate'].to_i < past_trans.rate - 5000

      puts "判定の結果：売りは#{which}"
      which
    elsif past_trans.order_type == 'sell'
      # 前回は売った = 今回は買う

      # 現在の買値レート
      now_rate = get_rate('buy')
      puts "現在のレートは#{now_rate['rate']}円"

      if now_rate['rate'].to_i > 2000000
        # 200万円を超えている場合は買わない
        puts '200万円を超えているため、購入を見送りました。'
        return false
      else
        last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id
        before_2m_bitcoin = Bitcoin.find(last_bitcoin_id - 2)
        before_5m_bitcoin = Bitcoin.find(last_bitcoin_id - 10)
        puts "2分前の購入レートは#{before_2m_bitcoin.rate}円\n5分前の購入レートは#{before_5m_bitcoin.rate}円"

        # 5分前 < 2分前 < 現在と上昇していたら買う
        which = now_rate['rate'].to_i > before_2m_bitcoin.rate && before_2m_bitcoin.rate > before_5m_bitcoin.rate

        # 前回の[売却]よりも1.5万円レートが下がっていたら、買う
        # which = now_rate['rate'].to_i < past_trans.rate

        puts "判定の結果：購入は#{which}"
        which
      end
    end
  end

  # 取引履歴を取得します。
  def read_transactions
    key = ENV['CC_API_KEY']
    secret = ENV['CC_API_SECRET']

    uri = URI.parse "https://coincheck.com/api/exchange/orders/transactions"
    headers = get_signature(uri, key, secret)
    request_for_get(uri, headers)
  end

  private

  def http_request(uri, request)
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE

    response = https.start do |h|
      h.request(request)
    end

    p response

    response

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

  def request_for_get(uri, headers = {})
    request = Net::HTTP::Get.new(uri.request_uri, initheader = custom_header(headers))
    http_request(uri, request)
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
