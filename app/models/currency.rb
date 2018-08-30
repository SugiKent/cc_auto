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
      next if type == 'xmr' || type == 'rep' || type = 'zec' || type == 'dash'
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

  def compare_rate
    Currency.types.keys.each do |type|
      # xrpだけをチェックする
      next unless type == "xrp"

      uri = URI.parse "https://coincheck.com/api/rate/#{type}_jpy"
      json = Net::HTTP.get(uri)
      result = JSON.parse(json)

      next if result.blank?

      now_rate = result['rate'].to_i
      lowest_rate = lowest_rate_1day(type)
      highest_rate = highest_rate_1day(type)

      # 現在の価格が24時間以内の最低値の場合、trueを返す
      if now_rate < lowest_rate.rate
        notify_rate(type, now_rate, '最低値')
      end

      if now_rate > highest_rate.rate
        notify_rate(type, now_rate, '最高値')
      end
    end
  end

  def notify_rate(type,rate, word)
    msg = "【BOT】#{type}が24時間以内で#{word}になりました。\n\n現在のレート：#{rate}円/#{type}\n\ncoincheckのデータより"
    Line.new.notify(msg)
  end

  def lowest_rate_1day(type)
    lowest_rate = Currency.where(type: type).where("currencies.created_at > ?", DateTime.now - 1.days).order(:rate).first
  end

  def highest_rate_1day(type)
    highest_rate = Currency.where(type: type).where("currencies.created_at > ?", DateTime.now - 1.days).order('rate DESC').first
  end

end
