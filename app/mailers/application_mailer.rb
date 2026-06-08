class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('SMTP_FROM', 'development@quikraistaging.com')
  layout "mailer"
end
