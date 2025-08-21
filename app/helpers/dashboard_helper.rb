module DashboardHelper
    def time_difference(clock_in_time)
      # Calculate the duration between clock_in_time and the current time
      duration = Time.current - clock_in_time
  
      # Convert the duration into hours, minutes, and seconds
      hours = (duration / 1.hour).to_i
      minutes = ((duration % 1.hour) / 1.minute).to_i
      seconds = ((duration % 1.minute) / 1.second).to_i
  
      # Format the output
      formatted_time = "#{hours}h #{minutes}m #{seconds}s"
      
      formatted_time
    end
  end
  