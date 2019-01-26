require 'csv'

desc "Transactionを過去のデータで試します。"
task "transaction:test" => :environment do

  # csv用のファイル
  file_name = './log/' + "test_trans_#{Time.now.strftime("%Y%m%d")}_#{Time.now.strftime("%H%M%S")}.csv"

  all_count = Bitcoin.count
  count_id = 80001
  order_price = 0
  trans_count = 0
  yen = 30000
  bitcoin = 0
  order_type = 'buy'

  while count_id < all_count
    if order_type == 'buy'
      # 購入の場合のロジックテスト
      now = Bitcoin.find(count_id)

      which = true

      last_bitcoin_id = Bitcoin.find(now.id-2).id

      # 現在よりも[2,3,4分前]のいずれか高かったら買わない
      if which

        before_2m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
        before_3m_rate = Bitcoin.find(last_bitcoin_id - 4).rate
        before_4m_rate = Bitcoin.find(last_bitcoin_id - 6).rate
        which = !(now.rate < before_2m_rate ||
                  now.rate < before_3m_rate ||
                  now.rate < before_4m_rate)
        puts 'ここ4分間の判別クリア' if which
      end

      if which
        before_0h_1h = Bitcoin.where(order_type: 'buy', id: [(last_bitcoin_id - 120)..(last_bitcoin_id)])
        before_0h_10h = Bitcoin.where(order_type: 'buy', id: [(last_bitcoin_id - 1200)..(last_bitcoin_id)])
        before_0h_20h = Bitcoin.where(order_type: 'buy', id: [(last_bitcoin_id - 2400)..(last_bitcoin_id)])

        @t = Transaction.new

        reg_0_1 = @t.reg_line(before_0h_1h.count, before_0h_1h.pluck(:rate))
        reg_0_10 = @t.reg_line(before_0h_10h.count, before_0h_10h.pluck(:rate))
        reg_0_20 = @t.reg_line(before_0h_20h.count, before_0h_20h.pluck(:rate))

        # ここ1時間の傾きが-0.1より小さいなら買う
        # かつ、ここ20時間の傾きが-0.7より大きい時
        # すなわち、傾きがかなりプラス向きの時
        which = reg_0_1[:slope] > 0.01 && reg_0_20[:slope] > 5

        # if which
        #   which = reg_0_10[:slope] > reg_0_20[:slope]
        # end

        puts 'ここ20時間の判別クリア' if which
      end

      if which
        # 高掴み対策
        # 24時間での最高取引価格-10万円より低いなら買う
        before_24h = Bitcoin.where(order_type: 'buy', id: [(now.id-2880)..(now.id) ])
        before_24h_hiest = before_24h.order('rate ASC').last
        which = now.rate < before_24h_hiest.rate - 50000

        puts '24時間の最高値-5万円クリア' if which

      end

      puts "判定の結果：購入は#{which}"

      if which
        order_price = now.rate - 500

        amount = yen / order_price
        bitcoin = amount
        yen = 0
        count_id += 3
        trans_count += 1

        csv_data = CSV.generate do |csv|
          csv << [count_id, order_type, now.created_at, bitcoin, yen, order_price, trans_count]
        end
        File.open("#{file_name}", 'a') do |file|
          file.write(csv_data)
        end

        # 次はsellの判断をするため
        order_type = 'sell'
      else
        count_id += 2
      end
    else
      # 売る場合のロジックテスト

      now = Bitcoin.find(count_id)

      puts "#{now.rate} > #{order_price}"
      which = now.rate > order_price

      last_bitcoin_id = Bitcoin.find(now.id-2).id
      if which
        puts '[購入時よりも高い]クリア'

        before_2m_rate = Bitcoin.find(last_bitcoin_id - 2).rate
        before_3m_rate = Bitcoin.find(last_bitcoin_id - 4).rate
        # 現在よりも2,3分前の両方が大きいなら売る
        which = now.rate < before_2m_rate &&
                now.rate < before_3m_rate
        puts 'ここ3分間の判別クリア' if which
      end

      if which
        # 0~10時間前
        before_0h_10h = Bitcoin.where(order_type: 'sell', id: [(last_bitcoin_id - 1200)..(last_bitcoin_id)])
        # 0~20時間前
        before_0h_20h = Bitcoin.where(order_type: 'sell', id: [(last_bitcoin_id - 2400)..(last_bitcoin_id)])

        @t = Transaction.new
        reg_0_10 = @t.reg_line(before_0h_10h.count, before_0h_10h.pluck(:rate))
        reg_0_20 = @t.reg_line(before_0h_20h.count, before_0h_20h.pluck(:rate))

        # 0~10時間の傾きが10%以下なら売る
        # かつ、0~20時間の傾きが50%以下なら売る
        which = reg_0_10[:slope] < 0.2 && reg_0_20[:slope] < 0.5

        puts "ここ10時間の判別クリア\n0~10時間の傾き：#{reg_0_10[:slope]}" if which
      end

      puts "判定の結果：売却は#{which}"

      if which
        order_price = now.rate + 700
        bitcoin = 0
        yen = bitcoin * order_price
        profit += past_rate * 0.02
        count_id += 1
        trans_count += 1

        csv_data = CSV.generate do |csv|
          csv << [count_id, order_type, now.created_at, bitcoin, yen, order_price, trans_count]
        end
        File.open("#{file_name}", 'a') do |file|
          file.write(csv_data)
        end

        # 次はbuyの判断をするため
        order_type = 'buy'
      else
        count_id += 2
      end
    end

    puts "\n日時：#{now.created_at}\n日本円：#{yen}\ncount_id：#{count_id}\n取引回数：#{trans_count}回"
    puts "****************************************"

  end

  puts '----------------------'
  puts "日本円：#{yen}\ncount_id：#{count_id}\n取引回数：#{trans_count}回\n最後の取引レート：#{order_price}"
  puts '----------------------'

end
