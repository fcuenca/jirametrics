# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkBarChart < ChartBase
  @@next_id = 0
  attr_accessor :possible_statuses

  def initialize
    super()

    header_text 'Aging Work Bar Chart'
    description_text <<-HTML
      <p>
        This chart shows all active (started but not completed) work, ordered from oldest at the top to
        newest at the bottom.
      </p>
      <p>
        The colours indicate different statuses, grouped by status category. Any statuses in the status
        category of "To Do" will be in a shade of blue. Any in the category of "In Progress" will be in a
        shade of yellow and any in "Done" will be in a shade of green. Depending on how you calculate
        cycletime, you may end up with only yellows or you may have a mix of all three.
      </p>
      <p>
        The gray backgrounds indicate weekends and the red vertical line indicates the 85% point for all
        items in this time period. Anything that started to the left of that is now an outlier.
      </p>
    HTML
  end

  def run
    aging_issues = @issues.select do |issue|
      cycletime = issue.board.cycletime
      cycletime.started_time(issue) && cycletime.stopped_time(issue).nil?
    end
    @status_colors = pick_colors_for_statuses

    today = date_range.end
    aging_issues.sort! do |a, b|
      a.board.cycletime.age(b, today: today) <=> b.board.cycletime.age(a, today: today)
    end
    data_sets = []
    aging_issues.each do |issue|
      cycletime = issue.board.cycletime
      issue_start_date = cycletime.started_time(issue).to_date
      issue_label = "[#{label_days cycletime.age(issue, today: today)}] #{issue.key}: #{issue.summary}"[0..60]
      [
        status_data_sets(issue: issue, label: issue_label, today: today),
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Blocked',
          stack: 'blocked',
          color: 'red',
          start_date: issue_start_date
        ) { |day| issue.blocked_on_date? day },
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Stalled',
          stack: 'blocked',
          color: 'orange',
          start_date: issue_start_date
        ) { |day| issue.stalled_on_date?(day) && !issue.blocked_on_date?(day) },
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Expedited',
          stack: 'expedited',
          color: 'red',
          start_date: issue_start_date
        ) { |day| issue.expedited_on_date?(day) }
      ].compact.flatten.each do |data|
        data_sets << data
      end
    end

    percentage = calculate_percent_line
    percentage_line_x = date_range.end - calculate_percent_line if percentage

    wrap_and_render(binding, __FILE__)
  end

  def status_data_sets issue:, label:, today:
    cycletime = issue.board.cycletime

    issue_started_time = cycletime.started_time(issue)

    previous_start = nil
    previous_status = nil

    data = []
    issue.changes.each do |change|
      next unless change.status?

      unless previous_start.nil? || previous_start < issue_started_time

        hash = {
          type: 'bar',
          label: "#{issue.key}-#{@@next_id += 1}",
          data: [{
            x: [chart_format(previous_start), chart_format(change.time)],
            y: label,
            title: "#{issue.type} : #{change.value}"
          }],
          backgroundColor: color_for(status_name: change.value),
          borderRadius: 0,
          stacked: true,
          stack: 'status'
        }
        data << hash if date_range.include?(change.time.to_date)
      end

      previous_start = change.time
      previous_status = change.value
    end

    if previous_start
      data << {
        type: 'bar',
        label: "#{issue.key}-#{@@next_id += 1}",
        data: [{
          x: [chart_format(previous_start), chart_format(today)],
          y: label,
          title: "#{issue.type} : #{previous_status}"
        }],
        backgroundColor: color_for(status_name: previous_status),
        borderRadius: 0,
        stacked: true,
        stack: 'status'
      }
    end

    data
  end

  def data_set_by_block(
    issue:, issue_label:, title_label:, stack:, color:, start_date:, end_date: date_range.end, &block
  )
    started = nil
    ended = nil
    data = []

    (start_date..end_date).each do |day|
      marked = block.call(day)
      if marked
        started = day if started.nil?
        ended = day
      elsif ended
        data << {
          x: [chart_format(started), chart_format(ended)],
          y: issue_label,
          title: "#{issue.type} : #{title_label} #{label_days (ended - started).to_i + 1}"
        }

        started = nil
        ended = nil
      end
    end

    return nil if data.empty?

    {
      type: 'bar',
      data: data,
      backgroundColor: color,
      stacked: true,
      stack: stack
    }
  end

  def color_for status_name:
    @status_colors[@possible_statuses.find { |status| status.name == status_name }]
  end

  def pick_colors_for_statuses
    blues = [
      '#B0E0E6', # powderblue
      '#ADD8E6', # lightblue
      '#87CEFA', # lightskyblue
      '#87CEEB', # skyblue
      '#00BFFF', # deepskyblue
      '#B0C4DE', # lightsteelblue
      '#1E90FF', # dodgerblue
      '#6495ED'  # cornflowerblue
    ]
    yellows = [
      '#FFEFD5', # papayawhip
      '#FFE4B5', # moccasin
      '#FFDAB9', # rpeachpuff
      '#EEE8AA', # palegoldenrod
      '#F0E68C', # khaki
      '#BDB76B', # darkkhaki
      '#FFFF00'  # yellow
    ]
    greens = [
      '#7CFC00', # lawngreen
      '#7FFF00', # chartreuse
      '#32CD32', # limegreen
      '#00FF00', # lime
      '#228B22', # forestgreen
      '#008000', # green
      '#006400', # darkgreen
      '#ADFF2F', # greenyellow
      '#9ACD32', # yellowgreen
      '#00FF7F', # springgreen
      '#00FA9A', # mediumspringgreen
      '#90EE90'  # lightgreen
    ]

    status_colors = {}
    blue_index = 0
    yellow_index = 0
    green_index = 0

    possible_statuses.each do |status|
      puts "Status #{status} shows up multiple times in possible statuses" if status_colors.key? status

      other_status = @possible_statuses.find do |other|
        other.name == status.name && other.category_name == status.category_name
      end
      if other_status && status_colors[other_status]
        status_colors[status] = status_colors[other_status]
        next
      end

      case status.category_name
      when 'To Do'
        color = blues[blue_index % blues.length]
        blue_index += 1
      when 'In Progress'
        color = yellows[yellow_index % yellows.length]
        yellow_index += 1
      when 'Done'
        color = greens[green_index % greens.length]
        green_index += 1
      when 'No Category'
        # Yet another theoretically impossible thing that we've seen in production
        color = 'gray'
      else
        puts "AgingWorkBarChart: Unexpected status category: #{status.category_name}"
        color = 'gray'
      end

      status_colors[status] = color
    end

    status_colors
  end

  def calculate_percent_line percentage: 85
    days = completed_issues_in_range.collect { |issue| issue.board.cycletime.cycletime(issue) }.compact.sort
    return nil if days.empty?

    days[days.length * percentage / 100]
  end
end
