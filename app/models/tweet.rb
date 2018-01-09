class Tweet

  def initialize
    @client = Twitter::REST::Client.new do |config|
      # 事前準備で取得したキーのセット
      config.consumer_key         = ENV['TWI_KEY']
      config.consumer_secret      = ENV['TWI_SECRET']
      config.access_token        = ENV['TWI_TOKEN']
      config.access_token_secret = ENV['TWI_TOKEN_SECRET']
    end
  end

  def tweet(content)
    @client.update(content)
  end


end
