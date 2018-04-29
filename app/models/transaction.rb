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

    @line = Line.new

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

      # 相場より700円あげた指値で売る
      price = rate['rate'].to_i + 700
    else
      # 買う場合
      order_type = 'buy'
      rate = get_rate(order_type)

      # 相場より700円下げた指値で買う
      price = rate['rate'].to_i - 700
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
      @line.update_content("POSTでの#{order_type}を開始")
      post_response = request_for_post(uri, headers, body)

      p post_response.body

      if post_response.code == '200'
        # amountがFloat型のためデータ登録できず
        trans = Transaction.new(type: 0, amount: amount, rate: price, order_type: order_type)
        trans.save
        @line.update_content("POSTでの#{order_type}を完了")

        # 残高を取得
        balance = get_balance
        jpy_balance = if order_type == 'buy'
          balance['jpy'].to_i - amount*price
        else
          balance['jpy'].to_i + amount*price
        end
        @line.update_content("[#{order_type}]を完了しました\nレート:#{price}円\n\n------------\n残高：#{jpy_balance}円\nBitcoin：#{balance['btc']}")

        @line.content_notify
      else
        @line.update_content("POSTでの#{order_type}に失敗")
        @line.content_notify
      end

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
    @line.update_content("------------------------\n" + Time.zone.now.to_s + "\nTransaction#check_rateを実行")

    past_trans = Transaction.last
    @line.update_content("最後の取引が[#{past_trans.order_type}]で、レートは#{past_trans.rate}円")

    if past_trans.order_type == 'buy'
      # 前回は買った = 今回は売る
      sell?(past_trans)
    elsif past_trans.order_type == 'sell'
      # 前回は売った = 今回は買う
      buy?
    end
  end

  # 引数は買った時の取引データ
  def sell?(past_trans)
    # 現在の売値レート
    now_rate = get_rate('sell')
    now_rate = now_rate['rate'].to_i
    @line.update_content("現在のレートは#{now_rate}円")

    # tickerを取得
    ticker = get_ticker

    # なるべく高い価格で売る
    # 24時間以内の最高取引価格-1万円
    # かつ、購入時より高ければ売る
    which = now_rate > past_trans.rate && now_rate > ticker['high'].to_i - 10000
    @line.update_content("24時間以内の最高取引価格：#{ticker['high'].to_i}円")

    if which
      @line.update_content("【24時間以内の最高取引価格-1万円】かつ、【購入時より高い】ので、売り")
    else
      @line.update_content("【24時間以内の最高取引価格-1万円】かつ、【購入時より高く】ないので、売らない")
    end

    if which
      # 上がり続けている時は売らない
      # 1~3分前のbitcoin価格を取得
      last_bitcoin_id = Bitcoin.where(order_type: 'sell').last.id
      before_2m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
      before_3m_rate = Bitcoin.find(last_bitcoin_id - 4).rate
      # 現在 > 2分前 > 3分前とレートが上昇していたら売らない
      which = !(now_rate > before_2m_rate &&
              before_2m_rate > before_3m_rate)
      @line.update_content("現在 > 2分前 && 2分前 > 3分前")
      @line.update_content("#{now_rate} > #{before_2m_rate} && #{before_2m_rate} > #{before_3m_rate}")
      if which
        @line.update_content("ここ3分間のレートは上がり続けていないので、売り")
      else
        @line.update_content("ここ3分間レートが上がり続けているので、売らない")
      end
    end

    if which
      @line.update_content("20時間前と35時間前のbitcoin価格から判断")
      # 上がり続けている時は売らない
      # 20と35時間前のbitcoin価格を取得
      last_bitcoin_id = Bitcoin.where(order_type: 'sell').last.id
      before_20h_rate = Bitcoin.find(last_bitcoin_id - 2400).rate
      before_35h_rate = Bitcoin.find(last_bitcoin_id - 4200).rate
      # 現在 > 20時間前 > 35時間前とレートが上昇していたら売らない
      which = !(now_rate > before_20h_rate &&
              before_20h_rate > before_35h_rate)
      @line.update_content("現在 > 20時間前 && 20時間前 > 35時間前")
      @line.update_content("#{now_rate} > #{before_20h_rate} && #{before_20h_rate} > #{before_35h_rate}")
      if which
        @line.update_content("ここ35時間のレートは上がり続けていないので、売り")
      else
        @line.update_content("ここ35時間レートが上がり続けているので、売らない")

        @line.content_notify
      end
    end

    @line.update_content("判定の結果：売りは#{which}")
    which
  end

  def buy?
    # 現在の買値レート
    now_rate = get_rate('buy')
    now_rate = now_rate['rate'].to_i
    @line.update_content("現在のレートは#{now_rate}円")

    # tickerを取得
    ticker = get_ticker
    @line.update_content("24時間以内の最安取引価格：#{ticker['low'].to_i}円")

    # 24時間以内の最安取引価格+1万円以下なら購入
    which = now_rate < ticker['low'].to_i + 10000

    if which
      @line.update_content("【24時間以内の最安取引価格+1万円以下】なので購入")
    else
      @line.update_content('【24時間以内の最安取引価格+1万円以下】ではないので購入しない')
    end

    if which
      last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id
      before_2m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
      before_3m_rate = Bitcoin.find(last_bitcoin_id - 4).rate
      @line.update_content('現在 > 2分前 && 2分前 > 3分前')
      @line.update_content("#{now_rate} > #{before_2m_rate} && #{before_2m_rate} > #{before_3m_rate}")

      # 現在 < 2分前 < 3分前と下落していたら買わない
      which = !(now_rate < before_2m_rate &&
                before_2m_rate < before_3m_rate)
      if which
        @line.update_content("下落し続けていないので購入")
      else
        @line.update_content("下落し続けているので買わない")
      end
    end

    if which
      last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id
      before_20h_rate = Bitcoin.find(last_bitcoin_id - 2400).rate
      before_35h_rate = Bitcoin.find(last_bitcoin_id - 4200).rate
      @line.update_content('現在 > 20時間前 && 20時間前 > 35時間前')
      @line.update_content("#{now_rate} > #{before_20h_rate} && #{before_20h_rate} > #{before_35h_rate}")

      # 現在 < 20時間前 < 35時間前と下落していたら買わない
      which = !(now_rate < before_20h_rate &&
                before_20h_rate < before_35h_rate)
      if which
        @line.update_content("下落し続けていないので購入")
      else
        @line.update_content("下落し続けているので買わない")
      end
    end

    if which
      # 高掴み対策
      # 24時間での最高取引価格-2万円より低いなら買う
      which = now_rate < ticker['high'].to_i - 20000
      @line.update_content("24時間以内の最高値が#{ticker['high'].to_i}円")
      if which
        @line.update_content("高掴みではないので、購入")
      else
        @line.update_content("高掴みしそうなので、購入を見送り")
      end
    end

    @line.update_content("判定の結果：購入は#{which}")
    which
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

    p Time.now
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
