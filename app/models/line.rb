class Line
  def initialize
    @uri = URI.parse("https://notify-api.line.me/api/notify")
    @token = ENV['LINE_TOKEN']
  end

  def notify(msg)
    request = make_request(msg)
    response = Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: @uri.scheme == "https") do |https|
      https.request(request)
    end
  end

  def make_request(msg)
    request = Net::HTTP::Post.new(@uri)
    request["Authorization"] = "Bearer #{@token}"
    request.set_form_data(message: msg)
    request
  end

end
