# frozen_string_literal: true

class DataQualityReport < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses

  class Entry
    attr_reader :started, :stopped, :issue, :problems

    def initialize started:, stopped:, issue:
      @started = started
      @stopped = stopped
      @issue = issue
      @problems = []
    end

    def report problem_key: nil, detail: nil, problem: nil, impact: nil
      @problems << [problem_key, detail, problem, impact]
    end
  end

  def run
    initialize_entries

    @entries.each do |entry|
      scan_for_completed_issues_without_a_start_time entry: entry
      scan_for_status_change_after_done entry: entry
      scan_for_backwards_movement entry: entry
      scan_for_issues_not_created_in_the_right_status entry: entry
    end

    entries_with_problems = entries_with_problems()
    return '' if entries_with_problems.empty?

    percentage = (entries_with_problems.size * 100.0 / @entries.size).round(1)
    render(binding, __FILE__)
  end

  # Return a format that's easier to assert against
  def testable_entries
    @entries.collect { |entry| [entry.started.to_s, entry.stopped.to_s, entry.issue] }
  end

  def entries_with_problems
    @entries.reject { |entry| entry.problems.empty? }
  end

  def category_name_for type:, status_name:
    @possible_statuses.find { |status| status.type == type && status.name == status_name}&.category_name
  end

  def initialize_entries
    @entries = @issues.collect do |issue|
      Entry.new(
        started: @cycletime.started_time(issue),
        stopped: @cycletime.stopped_time(issue),
        issue: issue
      )
    end

    @entries.sort! do |a, b|
      a.issue.key =~ /.+-(\d+)$/
      a_id = $1.to_i

      b.issue.key =~ /.+-(\d+)$/
      b_id = $1.to_i

      a_id <=> b_id
    end
  end

  def scan_for_completed_issues_without_a_start_time entry:
    return unless entry.stopped && entry.started.nil?

    changes = entry.issue.changes.select { |change| change.status? && change.time == entry.stopped }
    detail = 'No status changes found at the time that this item was marked completed.'
    unless changes.empty?
      detail = changes.collect do |change|
        "Status changed from [#{change.old_value}] to [#{change.value}] on [#{change.time}]."
      end.join ' '
    end

    entry.report(
      problem_key: :completed_but_not_started,
      detail: detail,
      problem: 'Item has finished but no start time can be found. Likely it went directly from "created" to "done"',
      impact: 'Item will not show up in cycletime, aging, or WIP calculations'
    )
  end

  def scan_for_status_change_after_done entry:
    return unless entry.stopped

    changes_after_done = entry.issue.changes.select do |change|
      change.status? && change.time > entry.stopped
    end

    return if changes_after_done.empty?

    problem = "This item was done on #{entry.stopped} but status changes continued after that."
    changes_after_done.each do |change|
      problem << " Status change to #{change.value} on #{change.time}."
    end
    entry.report(
      problem_key: :status_changes_after_done,
      detail: problem,
      problem: problem,
      impact: '<span class="highlight">This likely indicates an incorrect end date and will' \
        ' impact cycletime and WIP calculations</span>'
    )
  end

  def scan_for_backwards_movement entry:
    issue = entry.issue

    # Moving backwards through statuses is bad. Moving backwards through status categories is almost always worse.
    last_index = -1
    issue.changes.each do |change|
      next unless change.status?

      index = @board_metadata.find_index { |column| column.status_ids.include? change.value_id }
      if index.nil?
        entry.report(
          problem: "The issue changed to a status that isn't visible on the board: #{change.value}",
          impact: 'The issue may be on the wrong board or may be missing'
        )
      elsif change.old_value.nil?
        # Do nothing
      elsif index < last_index
        new_category = category_name_for(type: issue.type, status_name: change.value)
        old_category = category_name_for(type: issue.type, status_name: change.old_value)

        if new_category == old_category
          entry.report(
            problem_key: :backwords_through_statuses,
            detail: "The issue moved backwards from #{change.old_value.inspect} to #{change.value.inspect}" \
              " on #{change.time.to_date}",

            problem: "The issue moved backwards from #{change.old_value.inspect} to #{change.value.inspect}" \
              " on #{change.time.to_date}",
            impact: 'Backwards movement across statuses may result in incorrect cycletimes or WIP.'
          )
        else
          entry.report(
            problem_key: :backwards_through_status_categories,
            detail: "The issue moved backwards from #{change.old_value.inspect} to #{change.value.inspect}" \
              " on #{change.time.to_date}, " \
              " crossing status categories from #{old_category.inspect} to #{new_category.inspect}.",

            problem: "The issue moved backwards from #{change.old_value.inspect} to #{change.value.inspect}" \
              " on #{change.time.to_date}, " \
              " crossing status categories from #{old_category.inspect} to #{new_category.inspect}.",
            impact: '<span class="highlight">Backwards movement across status categories will usually result' \
              ' in incorrect cycletimes or WIP.</span>'
          )
        end
      end
      last_index = index
    end
  end

  def scan_for_issues_not_created_in_the_right_status entry:
    valid_initial_status_ids = @board_metadata[0].status_ids
    creation_change = entry.issue.changes.find { |issue| issue.status? }

    return if valid_initial_status_ids.include? creation_change.value_id

    entry.report(
      problem_key: :created_in_wrong_status,
      detail: "Issue was created in #{creation_change.value.inspect} status on #{creation_change.time.to_date}",

      problem: "Issue was created in #{creation_change.value.inspect} status on #{creation_change.time.to_date}",
      impact: '<span class="highlight">Issues not created in the first column (backlog) are an indication' \
        '  of corrupted or invalid data</span>. It might be' \
        ' the result of a migration from another system or project. Start times, and therefore cycletimes, aging,' \
        '  and WIP, will almost certainly be wrong.'
    )
  end
end
