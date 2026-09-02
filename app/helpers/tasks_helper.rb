module TasksHelper
  def hours_label(seconds)
    seconds = seconds.to_i
    return "—" if seconds.zero?

    h, rem = seconds.divmod(3600)
    m, = rem.divmod(60)
    h.positive? ? "#{h}h #{m}m" : "#{m}m"
  end
end
