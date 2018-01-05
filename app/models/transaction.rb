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
      trans = Transaction.new(type: 0, amount: amount, rate: price, order_type: order_type)
      trans.save
      puts "POSTでの#{order_type}を完了"

      balance = get_balance

      msg = "cc_auto\n[#{order_type}]を完了しました\nレート:#{price}円\n\n------------\n残高\n#{balance['jpy']}円\nBitcoin：#{balance['btc']}"

      line_notify(msg)
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
    # Ticker情報を取得する
    uri = URI.parse "https://coincheck.com/api/ticker"
    json = Net::HTTP.get(uri)
    result = JSON.parse(json)

    result
  end

  # 残高を取得してJSONで返します
  def get_balance
    key = ENV['CC_API_KEY']
    secret = ENV['CC_API_SECRET']

    uri = URI.parse "https://coincheck.com/api/accounts/balance"
    headers = get_signature(uri, key, secret)
    JSON.parse(request_for_get(uri, headers).body)
  end

  def check_rate
    puts "\n\n------------------------\n" + Time.zone.now.to_s + "\nTransaction#check_rateを実行"
    past_trans = Transaction.last
    puts "最後の取引が[#{past_trans.order_type}]で、レートは#{past_trans.rate}円"

    if past_trans.order_type == 'buy'
      # 前回は買った = 今回は売る

      # 現在の売値レート
      now_rate = get_rate('sell')
      now_rate = now_rate['rate'].to_i
      puts "現在のレートは#{now_rate}円"

      # 前回の[購入]より、レートが2万高くなっていたら売る
      rikaku = 5000
      which = now_rate > past_trans.rate + rikaku

      if which
        puts "前回の[購入]より、レートが#{rikaku}円高いので、売り"
      else
        puts "利確目標+#{rikaku}円に達していないので、売らない"
      end

      if which
        # 上がり続けている時は売らない
        # 1~3分前のbitcoin価格を取得
        last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id
        before_2m_rate = Bitcoin.find(last_bitcoin_id - 3).rate
        before_4m_rate = Bitcoin.find(last_bitcoin_id - 7).rate
        # 1分前 > 2分前 > 3分前とレートが上昇していたら売らない
        which = !(now_rate > before_2m_rate &&
                before_2m_rate > before_4m_rate)
        puts "現在 > 2分前 && 2分前 > 4分前"
        puts "#{now_rate} > #{before_2m_rate} && #{before_2m_rate} > #{before_4m_rate}"
        if which
          puts "ここ3分間のレートは上がり続けていないので、売り"
        else
          puts "ここ3分間レートが上がり続けているので、売らない"
          # 損切り対策
          # 購入時より2万下がったら売る
          songiri = 20000
          which = now_rate < past_trans.rate - songiri

          if which
            puts '損切りで、売り'
          end
        end
      end


      puts "判定の結果：売りは#{which}"
      which
    elsif past_trans.order_type == 'sell'
      # 前回は売った = 今回は買う

      # 現在の買値レート
      now_rate = get_rate('buy')
      now_rate = now_rate['rate'].to_i
      puts "現在のレートは#{now_rate}円"

      last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id
      before_1m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
      before_5m_rate = Bitcoin.find(last_bitcoin_id - 10).rate
      puts '現在 > 1分前 && 1分前 > 5分前'
      puts "#{now_rate} > #{before_1m_rate} && #{before_1m_rate} > #{before_5m_rate}"

      # 5分前 < 1分前 < 現在と上昇していたら買う
      which = now_rate > before_1m_rate && before_1m_rate > before_5m_rate
      if which
        puts "上昇しているので購入"
      else
        puts "上昇していないので購入を見送り"
      end

      if which
        # 高掴み対策
        # 24時間での最高取引価格-1.2万円より低いなら買う
        ticker = get_ticker
        which = now_rate < ticker['high'].to_i - 12000
        puts "24時間以内の最高値が#{ticker['high'].to_i}円"
        if which
          puts "高掴みではないので、購入"
        else
          puts "高掴みしそうなので、購入を見送り"
        end
      end

      puts "判定の結果：購入は#{which}"
      which
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

  def line_notify(msg)
    uri = URI.parse("https://notify-api.line.me/api/notify")

    request = make_request(msg)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |https|
      https.request(request)
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

  def make_request(msg)
    token = ENV['LINE_TOKEN']
    uri = URI.parse("https://notify-api.line.me/api/notify")

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request.set_form_data(message: msg)
    request
  end

end
