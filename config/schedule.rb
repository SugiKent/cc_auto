# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron
# env :GEM_PATH, ENV['GEM_PATH']
set :environment, ENV['ENVIRONMENT']
require File.expand_path(File.dirname(__FILE__) + "/environment")
set :output, 'log/cron.log'
set :bundle_command, "/root/.rbenv/shims/bundle"

# Could not find command "script/runner"のエラー対処のため
job_type :custom_runner, "export PATH=\"$HOME/.rbenv/bin:$PATH\"; eval \"$(rbenv init -)\"; cd :path && RAILS_ENV=:environment bundle exec rails runner :task :output"

every 1.minute do
  # custom_runner "Currency.get_rates"
  custom_runner "Bitcoin.get_rate"
  custom_runner "Transaction.new.sell_buy_coin"
  # custom_runner "Currency.new.compare_rate"
end

every 1.day do
  # custom_runner "Bitcoin.destroy_all_data"
  custom_runner "Currency.destroy_all_data"
end
