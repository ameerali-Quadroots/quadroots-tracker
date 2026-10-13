set :environment, "development"
set :output, "/home/qrt-lh-len-17/Desktop/tracker/clock_in_clock_out/log/cron.log"

every :day, at: '4:00am' do  command "
    cd /home/qrt-lh-len-17/Desktop/tracker/clock_in_clock_out && 
    export PATH=\"$HOME/.rbenv/bin:$PATH\" && 
    eval \"\$(rbenv init -)\" && 
    /home/qrt-lh-len-17/.rbenv/shims/bundle exec rails runner 'AutoClockJob.perform_now'"
end



every :day, at: '4:30am' do  command "
    cd /home/qrt-lh-len-17/Desktop/tracker/clock_in_clock_out && 
    export PATH=\"$HOME/.rbenv/bin:$PATH\" && 
    eval \"\$(rbenv init -)\" && 
    /home/qrt-lh-len-17/.rbenv/shims/bundle exec rails runner 'AutoClockJob.perform_now'"
end



every :day, at: '5:00am' do  command "
    cd /home/qrt-lh-len-17/Desktop/tracker/clock_in_clock_out && 
    export PATH=\"$HOME/.rbenv/bin:$PATH\" && 
    eval \"\$(rbenv init -)\" && 
    /home/qrt-lh-len-17/.rbenv/shims/bundle exec rails runner 'AutoClockJob.perform_now'"
end



every :day, at: '5:30am' do  command "
    cd /home/qrt-lh-len-17/Desktop/tracker/clock_in_clock_out && 
    export PATH=\"$HOME/.rbenv/bin:$PATH\" && 
    eval \"\$(rbenv init -)\" && 
    /home/qrt-lh-len-17/.rbenv/shims/bundle exec rails runner 'AutoClockJob.perform_now'"
end
