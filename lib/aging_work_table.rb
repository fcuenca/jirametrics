# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkTable < ChartBase
  attr_accessor :issues, :cycletime, :date_range

  def initialize expedited_priority_name
    @expedited_priority_name = expedited_priority_name
  end

  def run
    @today = date_range.end + 1
    aging_issues = select_aging_issues

    expedited_but_not_started = @issues.select do |issue|
      @cycletime.started_time(issue).nil? && @cycletime.stopped_time(issue).nil? && expedited?(issue)
    end
    aging_issues += expedited_but_not_started.sort_by(&:created)

    render(binding, __FILE__)
  end

  def select_aging_issues
    aging_issues = @issues.select { |issue| @cycletime.started_time(issue) && @cycletime.stopped_time(issue).nil? }
    aging_issues.sort { |a, b| @cycletime.age(b, today: @today) <=> @cycletime.age(a, today: @today) }
  end

  def expedited? issue
    issue.raw['fields']['priority']['name'] == @expedited_priority_name
  end

  def expedited_text issue
    "<span title='Expedited' style='font-size: 0.8em;'>🔥</span>" if expedited?(issue)
  end

  def blocked_text issue
    if issue.blocked_on_date? @today
      "<span title='Blocked' style='font-size: 0.8em;'>🛑</span>"
    elsif issue.stalled_on_date?(@today, 5) && @cycletime.started_time(issue)
      "<span title='Stalled' style='font-size: 0.8em;'>&#x1F7E7;</span>"
    else
      ''
    end
  end

  def assigned_to issue
    issue.raw['fields']['assignee']['displayName']
  end
end
