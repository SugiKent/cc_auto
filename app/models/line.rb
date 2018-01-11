class Line
  attr_accessor :content
  def initialize
    @uri = URI.parse("https://notify-api.line.me/api/notify")
    @token = ENV['CC_LINE_TOKEN']
    @content = ""
  end

  def notify(msg)
    request = make_request(msg)
    response = Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: @uri.scheme == "https") do |https|
      https.request(request)
    end
  end

  def content_notify
    request = make_request(@content)
    response = Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: @uri.scheme == "https") do |https|
      https.request(request)
    end

    # logメッセージ用
    puts @content
  end

  def make_request(msg)
    request = Net::HTTP::Post.new(@uri)
    request["Authorization"] = "Bearer #{@token}"
    request.set_form_data(message: msg)
    request
  end

  # メッセージに改行を加えて新しいメッセージを追加する
  def update_content(msg)
    @content = @content + "\n" + msg
  end

end
