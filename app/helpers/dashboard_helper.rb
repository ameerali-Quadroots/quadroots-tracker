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

    def format_seconds_to_hms(total_seconds)
      return "0h 0m" if total_seconds.nil? || total_seconds <= 0
      hours = (total_seconds / 3600).to_i
      minutes = ((total_seconds % 3600) / 60).to_i
      "#{hours}h #{minutes}m"
    end

    def total_breaks_seconds(time_clock)
      return 0 unless time_clock.present?
      secs = 0
      time_clock.breaks.each do |b|
        if b.break_out.present?
          secs += (b.break_out - b.break_in).to_i
        else
          secs += (Time.current - b.break_in).to_i
        end
      end
      secs
    end

    def live_work_seconds(time_clock)
      return 0 unless time_clock.present? && time_clock.clock_in.present?
      end_time = time_clock.clock_out || Time.current
      total = (end_time - time_clock.clock_in).to_i
      total - total_breaks_seconds(time_clock)
    end

    # Returns a hash of pre-computed status values for an executive in the given shift range.
    # Keys: :time_clock, :status, :status_html, :live_label, :breaks_count, :break_duration_label, :break_since
    def executive_status_data(executive, shift_range)
      tc = executive.time_clocks.where(clock_in: shift_range).order(clock_in: :desc).first

      data = {
        time_clock: tc,
        status: 'Off',
        status_html: %Q(<span class="badge rounded-pill" style="background-color: #f1f5f9; color: #475569; border: 1px solid #e2e8f0; padding: 5px 16px; font-weight: 600; font-size: 0.75rem;">Off</span>),
        live_label: '-',
        breaks_count: 0,
        break_duration_label: '0h 0m',
        break_since: nil
      }

      return data unless tc.present?

      breaks_count = tc.breaks.count
      total_break_secs = total_breaks_seconds(tc)
      live_secs = live_work_seconds(tc)
      live_label = format_seconds_to_hms(live_secs)
      break_dur_label = format_seconds_to_hms(total_break_secs)

      if tc.on_break?
        status = 'On Break'
        last_break = tc.breaks.where(break_out: nil).last
        since_label = last_break&.break_in&.strftime('%I:%M %p')
        status_html = %Q(<span class="badge rounded-pill" style="background-color: #f59e0b; color: #fff; padding: 5px 14px; font-weight: 600; font-size: 0.75rem;">On Break</span>)
      elsif tc.clock_out.nil?
        status = 'Working'
        status_html = %Q(<span class="badge rounded-pill" style="background-color: #00b894; color: #fff; padding: 5px 14px; font-weight: 600; font-size: 0.75rem;">Working</span>)
      else
        status = 'Off'
        status_html = %Q(<span class="badge rounded-pill" style="background-color: #f1f5f9; color: #475569; border: 1px solid #e2e8f0; padding: 5px 16px; font-weight: 600; font-size: 0.75rem;">Off</span>)
      end

      data.merge!(
        status: status,
        status_html: status_html,
        live_label: live_label,
        breaks_count: breaks_count,
        break_duration_label: break_dur_label,
        break_since: since_label
      )

      data
    end
  end
  