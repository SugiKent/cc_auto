#ワーカーの数。後述
  $worker  = 2
#何秒経過すればワーカーを削除するのかを決める
  $timeout = 30
#自分のアプリケーション名、currentがつくことに注意。
  $app_dir = "/var/www/cc_auto/current"
#リクエストを受け取るポート番号を指定。後述
  $listen  = '/var/www/cc_auto/current/tmp/sockets/unicorn.sock'
#PIDの管理ファイルディレクトリ
  $pid     = File.expand_path 'tmp/pids/unicorn.pid', $app_dir
#エラーログを吐き出すファイルのディレクトリ
  $std_log = File.expand_path 'log/unicorn.log', $app_dir

# 上記で設定したものが適応されるよう定義
  worker_processes  $worker
  working_directory $app_dir
  stderr_path $std_log
  stdout_path $std_log
  timeout $timeout
  listen  $listen
  pid $pid
preload_app true

root = "/var/www/cc_auto/current"
  before_exec do |server|
    ENV['BUNDLE_GEMFILE'] = "#{root}/Gemfile"
end

before_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection.disconnect!
  end

  old_pid = "#{server.config[:pid]}.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end
end

after_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection
  end
end
