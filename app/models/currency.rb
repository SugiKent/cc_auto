require 'net/http'
require 'uri'
require 'openssl'
require 'json'

class Currency < ApplicationRecord
  self.inheritance_column = :_type_disabled

  scope :newer_order, -> { order(created_at: :desc) }

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

  # 全通貨の販売レートを取得して、dbに登録していく。
  def self.get_rates

    Currency.types.keys.each do |type|
      uri = URI.parse "https://coincheck.com/api/rate/#{type}_jpy"
      json = Net::HTTP.get(uri)
      result = JSON.parse(json)

      next if result.blank?

      currency = Currency.new(type: type.to_sym, rate: result['rate'])
      currency.save
    end

  end

  # 過去の販売レートから、買うべきかを判定する。
  def self.calc_rates
    # btcの100を取得
    currencies = Currency.where(type: 0).limit(500).newer_order

    sum_all = currencies.pluck(:rate).sum / currencies.count

  end

  def compare_lowest_rate
    Currency.types.keys.each do |type|
      uri = URI.parse "https://coincheck.com/api/rate/#{type}_jpy"
      json = Net::HTTP.get(uri)
      result = JSON.parse(json)

      next if result.blank?

      lowest_rate = lowest_rate_1day(type)

      # 現在の価格が24時間以内の最低値の場合、trueを返す
      if result['rate'].to_i < lowest_rate.rate
        notify_lowest_rate(type,result['rate'].to_i)
      end
    end
  end

  def notify_lowest_rate(type,rate)
    msg = "【BOT】#{type}が24時間以内で最低値になりました。\n\n現在のレート：#{rate}円/#{type}\n\ncoincheckのデータより"
    line_notify(msg)
    Tweet.new.tweet(msg)
  end

  def lowest_rate_1day(type)
    lowest_rate = Currency.where(type: type).where("currencies.created_at > ?", DateTime.now - 1.days).order(:rate).first
  end

  def line_notify(msg)
    uri = URI.parse("https://notify-api.line.me/api/notify")

    request = make_request(msg)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |https|
      https.request(request)
    end
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
