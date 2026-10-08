require "prawn"
require "prawn/table"

# Shared look for the app's PDF reports: a purple title band, tinted table
# headers, hairline rows, right-aligned figures and a page-numbered footer.
# Subclasses implement #title, #subtitle and #body(pdf).
class ReportPdf
  PURPLE = "6F2B8A".freeze
  PURPLE_DARK = "56206C".freeze
  INK    = "1B1023".freeze
  MUTED  = "6E6878".freeze
  LINE   = "E9E1EF".freeze
  SOFT   = "F5EEF9".freeze
  RED    = "B91C1C".freeze

  def render
    pdf = Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: [36, 36, 44, 36],
                              info: { Title: title, Author: "QuadRoots Tracker", CreationDate: generated_at })
    pdf.font "Helvetica"
    pdf.fill_color INK

    header(pdf)
    body(pdf)
    footer(pdf)
    pdf.render
  end

  private

  def page_layout
    :portrait
  end

  def generated_at
    @generated_at ||= Time.zone.now
  end

  def header(pdf)
    pdf.fill_color PURPLE
    pdf.fill_rectangle [pdf.bounds.left, pdf.cursor], pdf.bounds.width, 62
    pdf.fill_color "FFFFFF"
    pdf.bounding_box([pdf.bounds.left + 18, pdf.cursor - 12], width: pdf.bounds.width - 36, height: 44) do
      pdf.text safe(title), size: 18, style: :bold
      pdf.move_down 3
      pdf.text safe(subtitle), size: 9.5
    end
    pdf.fill_color INK
    pdf.move_down 20
  end

  # A row of headline figures: [[label, value], ...]
  def figures(pdf, pairs)
    last = pairs.size - 2
    pdf.table([pairs.map { |_label, value| value.to_s }, pairs.map(&:first)],
              width: pdf.bounds.width, cell_style: { borders: [], padding: [2, 10] }) do
      row(0).font_style = :bold
      row(0).size = 17
      row(0).padding = [10, 10, 0, 10]
      row(1).size = 8.5
      row(1).text_color = MUTED
      row(1).padding = [2, 10, 10, 10]
      cells.background_color = SOFT
      if last >= 0
        columns(0..last).borders = [:right]
        columns(0..last).border_color = "FFFFFF"
        columns(0..last).border_width = 3
      end
    end
    pdf.move_down 6
  end

  def section(pdf, heading, caption = nil)
    pdf.move_down 12
    pdf.fill_color PURPLE
    pdf.text safe(heading), size: 12.5, style: :bold
    if caption
      pdf.fill_color MUTED
      pdf.text safe(caption), size: 8.5
    end
    pdf.fill_color INK
    pdf.move_down 6
  end

  # A table with a tinted header, hairline rows and right-aligned figures from
  # column `numeric_from` on. `totals` adds a bold last row; `red_rows` are
  # body row indexes (0-based) to print in red.
  def data_table(pdf, head, rows, totals: nil, widths: {}, numeric_from: 1, numeric_to: -1, red_rows: [])
    all = [head] + rows + (totals ? [totals] : [])
    pdf.table(all, header: true, width: pdf.bounds.width, column_widths: widths,
              cell_style: { size: 8.5, padding: [5, 8], borders: [:bottom], border_color: LINE, border_width: 0.5 }) do
      row(0).font_style = :bold
      row(0).background_color = SOFT
      row(0).text_color = PURPLE_DARK
      columns(numeric_from..numeric_to).align = :right
      red_rows.each { |index| row(index + 1).text_color = RED }
      if totals
        row(-1).font_style = :bold
        row(-1).borders = [:top]
        row(-1).border_color = "C9B8D4"
        row(-1).border_width = 1
      end
    end
  end

  def empty(pdf, message)
    pdf.fill_color MUTED
    pdf.text safe(message), size: 9.5
    pdf.fill_color INK
  end

  def footer(pdf)
    pdf.number_pages "QuadRoots Tracker  |  #{safe(title)}  |  Page <page> of <total>",
                     at: [pdf.bounds.left, -16], width: pdf.bounds.width, align: :center, size: 8, color: MUTED
  end

  def hours(seconds)
    seconds = seconds.to_i
    return "-" if seconds.zero?

    h, rem = seconds.divmod(3600)
    h.positive? ? "#{h}h #{rem / 60}m" : "#{rem / 60}m"
  end

  # Prawn's built-in fonts only cover Windows-1252; anything else (emoji, other
  # scripts) would raise, so it is replaced with "?".
  def safe(text)
    text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  end
end
