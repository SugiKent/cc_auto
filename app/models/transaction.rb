require 'net/http'
require 'uri'
require 'openssl'
require 'json'
require 'bigdecimal'
require 'bigdecimal/util'

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

    # amountの型がintegerのため少数が入らず
    amount = ''

    # 残高の取得
    balance = get_balance
    puts "バランスの取得#{balance['btc']}"

    # 最後の取引が"買い"なら、"売る"
    if Transaction.last.order_type == 'buy'
      puts '売ります'
      # 売る場合
      order_type = 'sell'
      rate = get_rate(order_type)

      # 相場より700円あげた指値で売る
      price = rate['rate'].to_i + 700
      # 持ってるやつ全部売る
      amount = balance['btc'].to_d
    else
      puts '買います'
      # 買う場合
      order_type = 'buy'
      rate = get_rate(order_type)

      # 相場より500円下げた指値で買う
      price = rate['rate'].to_i - 500
      # 持ってる日本円で変えるだけ
      amount = balance['jpy'].to_s.to_d / price.to_s.to_d
    end

    # order_typeを元にレートを取得
    rate = get_rate(order_type)

    body = {
      rate: price,
      amount: amount.to_s,
      order_type: order_type,
      pair: 'btc_jpy',
      market_buy_amount: nil,
      position_id: nil,
    }

    if Rails.env == 'production'
      uri = URI.parse "https://coincheck.com/api/exchange/orders"
      headers = get_signature(uri, key, secret, body.to_json)
      @line.update_content("POSTでの#{order_type}を開始")
      post_response = request_for_post(uri, headers, body)

      puts '売買のPOSTします'
      p post_response.body

      if post_response.code == '200'
        puts '売買のPOSTの結果は200でした'
        # amountがFloat型のためデータ登録できず
        trans = Transaction.new(type: 0, amount: amount.to_d, rate: price, order_type: order_type)
        trans.save
        @line.update_content("POSTでの#{order_type}を完了")

        # 残高を取得
        balance = get_balance
        jpy_balance = if order_type == 'buy'
          balance['jpy'].to_i - amount.to_d*price
        else
          balance['jpy'].to_i + amount.to_d*price
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
    puts 'btc_jpyのrateを取得します'
    # 1BTC当たりのorder_typeのレートを取得する
    uri = URI.parse "https://coincheck.com/api/exchange/orders/rate?order_type=#{order_type}&pair=btc_jpy&amount=1"
    json = Net::HTTP.get(uri)
    result = JSON.parse(json)
    p result
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
      puts 'sell?の実行開始'
      # 前回は買った = 今回は売る
      sell?(past_trans)
    elsif past_trans.order_type == 'sell'
      puts 'buy?の実行開始'
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

    # なるべく高い価格で売る
    # かつ、購入時より高ければ売る
    which = now_rate > past_trans.rate

    if which
      @line.update_content("【購入時より高い】ので、売り")
    else
      @line.update_content("【購入時より高く】ないので、売らない")
    end

    if which
      # 上がり続けている時は売らない
      # 1~3分前のbitcoin価格を取得
      last_bitcoin_id = Bitcoin.where(order_type: 'sell').last.id
      before_2m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
      before_3m_rate = Bitcoin.find(last_bitcoin_id - 4).rate
      # 現在よりも2,3分前の両方が大きいなら売る
      which = now_rate < before_2m_rate &&
              now_rate < before_3m_rate
      @line.update_content("\n現在 > 2分前 && 現在 > 3分前")
      @line.update_content("現在：#{now_rate}")
      @line.update_content("2分前：#{before_2m_rate}")
      @line.update_content("3分前：#{before_3m_rate}")
      if which
        @line.update_content("ここ3分間のレートは上がり続けていないので、売り")
      else
        @line.update_content("ここ3分間レートが上がり続けているので、売らない")
      end
    end

    if which
      # 上がり続けている時は売らない
      last_bitcoin_id = Bitcoin.where(order_type: 'sell').last.id

      # 0~10時間前
      before_0h_10h = Bitcoin.where(order_type: 'sell', id: [(last_bitcoin_id - 1200)..(last_bitcoin_id)])
      reg_0_10 = reg_line(before_0h_10h.count, before_0h_10h.pluck(:rate))
      @line.update_content("\n0~10時間前の傾き：#{reg_0_10[:slope]}")

      # 0~20時間前
      before_0h_20h = Bitcoin.where(order_type: 'sell', id: [(last_bitcoin_id - 2400)..(last_bitcoin_id)])
      reg_0_20 = reg_line(before_0h_20h.count, before_0h_20h.pluck(:rate))
      @line.update_content("0~20時間前の傾き：#{reg_0_20[:slope]}")

      # 0~20時間前
      before_0h_40h = Bitcoin.where(order_type: 'sell', id: [(last_bitcoin_id - 4800)..(last_bitcoin_id)])
      reg_0_40 = reg_line(before_0h_40h.count, before_0h_40h.pluck(:rate))
      @line.update_content("0~40時間前の傾き：#{reg_0_40[:slope]}")

      @line.update_content("0~10時間の傾きが0.0001以下なら売る\nかつ、0~20時間の傾きが0.0001\nかつ、0~40時間の傾きが0.001以下なら売る")
      which = reg_0_10[:slope] < 0.0001 && reg_0_20[:slope] < 0.0001 && reg_0_40[:slope] < 0.001

      if which
        @line.update_content("ここ40時間の判別クリア")
      else
        @line.update_content("ここ40時間の判別アウト")

      end
    end

    # 損切り
    unless which
      which = now_rate.to_s.to_d < Transaction.last.rate.to_s.to_d - 100000
      @line.update_content("現在のレートが最後の取引から10万円落ちていたら損切り")
      if which
        @line.update_content("損切りで、売り")
      else
        @line.update_content("損切りではないので、売らない")
      end
    end

    @line.update_content("\n判定の結果：売りは#{which}")

    if which || (DateTime.now.hour % 10 == 0 && DateTime.now.minute == 0)
      @line.content_notify
      @line.reset_content
    end
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

    which = true

    if which
      last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id
      before_2m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
      before_3m_rate = Bitcoin.find(last_bitcoin_id - 4).rate
      before_4m_rate = Bitcoin.find(last_bitcoin_id - 6).rate
      @line.update_content("現在：#{now_rate}")
      @line.update_content("2分前：#{before_2m_rate}")
      @line.update_content("3分前：#{before_3m_rate}")
      @line.update_content("4分前：#{before_4m_rate}")

      @line.update_content("\n現在よりも[2,3,4分前]のいずれか高かったら買わない")
      which = !(now_rate < before_2m_rate ||
                now_rate < before_3m_rate ||
                now_rate < before_4m_rate)
      if which
        @line.update_content("下落し続けているわけではないので購入")
      else
        @line.update_content("下落し続けているので買わない")
      end
    end

    if which
      last_bitcoin_id = Bitcoin.where(order_type: 'buy').last.id

      # 0~1時間前
      before_0h_1h = Bitcoin.where(order_type: 'buy', id: [(last_bitcoin_id - 120)..(last_bitcoin_id)])
      reg_0_1 = reg_line(before_0h_1h.count, before_0h_1h.pluck(:rate))
      @line.update_content("\n0~1時間前の傾き：#{reg_0_1[:slope]}")

      # 0~20時間前
      before_0h_20h = Bitcoin.where(order_type: 'buy', id: [(last_bitcoin_id - 2400)..(last_bitcoin_id)])
      reg_0_20 = reg_line(before_0h_20h.count, before_0h_20h.pluck(:rate))
      @line.update_content("0~20時間前の傾き：#{reg_0_20[:slope]}")

      # 傾きがかなりプラス向きの時
      @line.update_content("0~1時間前の傾き > 0.001 && \n0~20時間前の傾き > 0.001\n傾きがプラス向き=上昇傾向なら購入")
      which = reg_0_1[:slope] > 0.001 && reg_0_20[:slope] > 0.001

      if which
        @line.update_content("ここ20時間の判別クリア")
      else
        @line.update_content("ここ20時間の判別アウト")
      end
    end

    if which
      # 高掴み対策
      which = now_rate < ticker['high'].to_i - 30000
      @line.update_content("\n24時間での最高取引価格-3万円より低いなら買う\n24時間以内の最高値が#{ticker['high'].to_i}円")
      if which
        @line.update_content("高掴みではないので、購入")
      else
        @line.update_content("高掴みしそうなので、購入を見送り")
      end
    end

    @line.update_content("\n判定の結果：購入は#{which}")
    if which || (DateTime.now.hour % 10 == 0 && DateTime.now.minute == 0)
      @line.content_notify
      @line.reset_content
    end
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

  def reg_line(count, y)
    x_array = [*1..count]
    sum_x = x_array.inject(0) {|s,a| s += a}
    sum_y = y.inject(0) {|s,a| s += a}

    sum_xx = x_array.inject(0) {|s,a| s += a*a}
    sum_xy = x_array.zip(y).inject(0) {|s,a| s += a[0] * a[1]}

    a = sum_xx * sum_y - sum_xy * sum_x
    a /= (x_array.size * sum_xx - sum_x * sum_x).to_f

    b = x_array.size * sum_xy - sum_x * sum_y
    b /= (x_array.size * sum_xx - sum_x * sum_y).to_f
    {intercept: a, slope: b}
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
