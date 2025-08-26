set :output, "log/cron.log"
set :environment, "production"

every 1.day, at: '3:00 am' do
  rake "time_clocks:auto_clock_out"
end
