# frozen_string_literal: true

require 'time'
require 'jirametrics/status_collection'

class ProjectConfig
  include DiscardChangesBefore

  attr_reader :target_path, :jira_config, :all_boards, :possible_statuses,
    :download_config, :file_configs, :exporter, :data_version, :name, :board_configs,
    :settings, :id
  attr_accessor :time_range, :jira_url, :id

  def initialize exporter:, jira_config:, block:, target_path: '.', name: '', id: nil
    @exporter = exporter
    @block = block
    @file_configs = []
    @download_config = nil
    @target_path = target_path
    @jira_config = jira_config
    @possible_statuses = StatusCollection.new
    @name = name
    @board_configs = []
    @all_boards = {}
    @settings = {
      'stalled_threshold' => 5,
      'blocked_statuses' => [],
      'stalled_statuses' => [],
      'blocked_link_text' => [],

      'colors' => {
        'stalled' => 'orange',
        'blocked' => '#FF7400'
      }
    }
    @id = id
  end

  def evaluate_next_level
    instance_eval(&@block)
  end

  def run
    unless aggregated_project?
      load_all_boards
      @id = guess_project_id
      load_status_category_mappings
      load_project_metadata
      load_sprints
    end
    anonymize_data if @anonymizer_needed

    @board_configs.each do |board_config|
      board_config.run
    end
    @file_configs.each do |file_config|
      file_config.run
    end
  end

  def guess_project_id
    return @id if @id

    previous_id = nil
    @all_boards.each_value do |board|
      project_id = board.project_id

      # If the id is ambiguous then return nil for now. The user will get an error later
      # in the case where we need it to be unambiguous. Sometimes we don't care and there's
      # no point forcing the user to enter a project id if we don't need it.
      return nil if previous_id && project_id && previous_id != project_id

      previous_id = project_id if project_id
    end
    previous_id
  end

  def aggregated_project?
    !!@aggregate_config
  end

  def download &block
    raise 'Not allowed to have multiple download blocks in one project' if @download_config
    raise 'Not allowed to have both an aggregate and a download section. Pick only one.' if @aggregate_config

    @download_config = DownloadConfig.new project_config: self, block: block
  end

  def file &block
    @file_configs << FileConfig.new(project_config: self, block: block)
  end

  def aggregate &block
    raise 'Not allowed to have multiple aggregate blocks in one project' if @aggregate_config
    raise 'Not allowed to have both an aggregate and a download section. Pick only one.' if @download_config

    @aggregate_config = AggregateConfig.new project_config: self, block: block
    return if @exporter.downloading?

    @aggregate_config.evaluate_next_level
  end

  def board id:, &block
    config = BoardConfig.new(id: id, block: block, project_config: self)
    @board_configs << config
  end

  def file_prefix prefix = nil
    @file_prefix = prefix unless prefix.nil?
    @file_prefix
  end

  def status_category_mapping status:, category:
    add_possible_status Status.new(name: status, category_name: category)
  end

  def load_all_boards
    Dir.foreach(@target_path) do |file|
      next unless file =~ /^#{@file_prefix}_board_(\d+)_configuration\.json$/

      board_id = $1.to_i
      load_board board_id: board_id, filename: "#{@target_path}#{file}"
    end
    raise "No boards found in #{@target_path.inspect}" if @all_boards.empty?
  end

  def load_board board_id:, filename:
    board = Board.new(
      raw: JSON.parse(File.read(filename)), possible_statuses: @possible_statuses
    )
    board.project_config = self
    @all_boards[board_id] = board
  end

  def raise_with_message_about_missing_category_information
    message = +''
    message << 'Could not determine categories for some of the statuses used in this data set.\n\n' \
      'If you specify a project: then we\'ll ask Jira for those mappings. If you\'ve done that' \
      ' and we still don\'t have the right mapping, which is possible, then use the' \
      " 'status_category_mapping' declaration in your config to manually add one.\n\n" \
      ' The mappings we do know about are below:'

    @possible_statuses.each do |status|
      message << "\n  type: #{status.type.inspect}, status: #{status.name.inspect}, " \
        "category: #{status.category_name.inspect}'"
    end

    message << "\n\nThe ones we're missing are the following:"

    missing_statuses = []
    issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        missing_statuses << change.value unless find_status(name: change.value)
      end
    end

    missing_statuses.uniq.each do |status_name|
      message << "\n  status: #{status_name.inspect}, category: <unknown>"
    end

    raise message
  end

  def load_status_category_mappings
    filename = "#{@target_path}/#{file_prefix}_statuses.json"
    # We may not always have this file. Load it if we can.
    return unless File.exist? filename

    statuses = JSON.parse(File.read(filename))
      .map { |snippet| Status.new(raw: snippet) }
    statuses
      .find_all { |status| status.global? }
      .each { |status| add_possible_status status }
    statuses
      .find_all { |status| status.project_scoped? }
      .each { |status| add_possible_status status }
  end

  def load_sprints
    Dir.foreach(@target_path) do |file|
      next unless file =~ /#{file_prefix}_board_(\d+)_sprints_\d+/

      board_id = $1.to_i
      timezone_offset = exporter.timezone_offset
      JSON.parse(File.read("#{target_path}#{file}"))['values'].each do |json|
        @all_boards[board_id].sprints << Sprint.new(raw: json, timezone_offset: timezone_offset)
      end
    end

    @all_boards.each_value do |board|
      board.sprints.sort_by!(&:id)
    end
  end

  def add_possible_status status
    existing_status = find_status(name: status.name)

    if status.project_scoped?
      # If the project specific status doesn't change anything then we don't care whether it's
      # our project or not.
      return if existing_status && existing_status.category_name == status.category_name

      raise_ambiguous_project_id if @id.nil?

      # Not our project, ignore it.
      return unless status.project_id == @id

      # Replace the old one with this
      @possible_statuses.delete(existing_status)
      @possible_statuses << status
      return
    end

    # If it isn't there, add it and go.
    return @possible_statuses << status unless existing_status

    # We're registering the same one twice. Shouldn't be possible with the new status API but it
    # did happen with the project specific one.
    return if status.category_name == existing_status.category_name

    # If we got this far then someone has called status_category_mapping and is attempting to
    # change the category.
    raise "Redefining status category #{status} with #{existing_status}. Was one set in the config?"
  end

  def raise_ambiguous_project_id
    raise 'Ambiguous project id: There is a project specific status that could affect out calculations. ' \
      'We are unable to automatically detect the id of the project so you will have to set it manually ' \
      'in the configuration like: "project id: 5"'
  end

  def find_status name:
    @possible_statuses.find_by_name name
  end

  def load_project_metadata
    filename = "#{@target_path}/#{file_prefix}_meta.json"
    json = JSON.parse(File.read(filename))

    @data_version = json['version'] || 1

    start = json['date_start'] || json['time_start'] # date_start is the current format. Time is the old.
    stop  = json['date_end'] || json['time_end']
    @time_range = to_time(start)..to_time(stop)

    @jira_url = json['jira_url']
  rescue Errno::ENOENT
    puts "== Can't load files from the target directory. Did you forget to download first? =="
    raise
  end

  def to_time string
    string = "#{string}T00:00:00#{@timezone_offset}" if string.match?(/^\d{4}-\d{2}\d{2}$/)
    Time.parse string
  end

  def guess_board_id
    return nil if aggregated_project?

    unless all_boards&.size == 1
      message = "If the board_id isn't set then we look for all board configurations in the target" \
        ' directory. '
      if all_boards.nil? || all_boards.empty?
        message += ' In this case, we couldn\'t find any configuration files in the target directory.'
      else
        message += 'If there is only one, we use that. In this case we found configurations for' \
          " the following board ids and this is ambiguous: #{all_boards.keys}"
      end
      raise message
    end
    all_boards.keys[0]
  end

  def find_board_by_id board_id = nil
    board = all_boards[board_id || guess_board_id]

    raise "Unable to find configuration for board_id: #{board_id}" if board.nil?

    board
  end

  # To be used by the aggregate_config only. Not intended to be part of the public API
  def add_issues issues_list
    @issues = [] if @issues.nil?
    @all_boards = {}

    issues_list.each do |issue|
      @issues << issue
      board = issue.board
      @all_boards[board.id] = board unless @all_boards[board.id]
    end
  end

  def issues
    raise "issues are being loaded before boards in project #{name.inspect}" if all_boards.nil? && !aggregated_project?

    unless @issues
      if @aggregate_config
        raise 'This is an aggregated project and issues should have been included with the include_issues_from ' \
          'declaration but none are here. Check your config.'
      end

      timezone_offset = exporter.timezone_offset

      issues_path = "#{@target_path}#{file_prefix}_issues/"
      if File.exist?(issues_path) && File.directory?(issues_path)
        issues = load_issues_from_issues_directory path: issues_path, timezone_offset: timezone_offset
      else
        puts "Can't find issues in #{path}. Has a download been done?"
      end

      # Attach related issues
      issues.each do |i|
        attach_subtasks issue: i, all_issues: issues
        attach_parent issue: i, all_issues: issues
        attach_linked_issues issue: i, all_issues: issues
      end

      # We'll have some issues that are in the list that weren't part of the initial query. Once we've
      # attached them in the appropriate places, remove any that aren't part of that initial set.
      @issues = issues.select { |i| i.in_initial_query? }
    end

    @issues
  end

  def attach_subtasks issue:, all_issues:
    issue.raw['fields']['subtasks']&.each do |subtask_element|
      subtask_key = subtask_element['key']
      subtask = all_issues.find { |i| i.key == subtask_key }
      issue.subtasks << subtask if subtask
    end
  end

  def attach_parent issue:, all_issues:
    parent_key = issue.parent_key
    parent = all_issues.find { |i| i.key == parent_key }
    issue.parent = parent if parent
  end

  def attach_linked_issues issue:, all_issues:
    issue.issue_links.each do |link|
      if link.other_issue.artificial?
        other = all_issues.find { |i| i.key == link.other_issue.key }
        link.other_issue = other if other
      end
    end
  end

  def find_default_board
    default_board = all_boards.values.first
    raise "No boards found for project #{name.inspect}" if all_boards.empty?

    if all_boards.size != 1
      puts "Multiple boards are in use for project #{name.inspect}. " \
        "Picked #{default_board.name.inspect} to attach issues to."
    end
    default_board
  end

  def load_issues_from_issues_directory path:, timezone_offset:
    issues = []
    default_board = nil

    group_filenames_and_board_ids(path: path).each do |filename, board_ids|
      content = File.read(File.join(path, filename))
      if board_ids == :unknown
        boards = [(default_board ||= find_default_board)]
      else
        boards = board_ids.collect { |b| all_boards[b] }
      end

      boards.each do |board|
        issues << Issue.new(raw: JSON.parse(content), timezone_offset: timezone_offset, board: board)
      end
    end

    issues
  end

  # Scan through the issues directory (path), select the filenames to be loaded and map them to board ids.
  # It's ok if there are multiple files for the same issue. We load the newest one and map all the other
  # board ids appropriately.
  def group_filenames_and_board_ids path:
    hash = {}
    Dir.foreach(path) do |filename|
      # Matches either FAKE-123.json or FAKE-123-456.json
      if /^(?<key>[^-]+-\d+)(?<_>-(?<board_id>\d+))?\.json$/ =~ filename
        (hash[key] ||= []) << [filename, board_id&.to_i || :unknown]
      end
    end

    result = {}
    hash.values.collect do |list|
      if list.size == 1
        filename, board_id = *list.first
        result[filename] = board_id == :unknown ? board_id : [board_id]
      else
        max_time = nil
        max_board_id = nil
        max_filename = nil
        all_board_ids = []

        list.each do |filename, board_id|
          mtime = File.mtime(File.join(path, filename))
          if max_time.nil? || mtime > max_time
            max_time = mtime
            max_board_id = board_id
            max_filename = filename
          end
          all_board_ids << board_id unless board_id == :unknown
        end

        result[max_filename] = all_board_ids
      end
    end
    result
  end

  def anonymize
    @anonymizer_needed = true
  end

  def anonymize_data
    Anonymizer.new(project_config: self).run
  end

  def discard_changes_before_hook issues_cutoff_times
    issues_cutoff_times.each do |issue, cutoff_time|
      days = (cutoff_time.to_date - issue.changes.first.time.to_date).to_i + 1
      message = "#{issue.key}(#{issue.type}) discarding #{days} "
      if days == 1
        message << "day of data on #{cutoff_time.to_date}"
      else
        message << "days of data from #{issue.changes.first.time.to_date} to #{cutoff_time.to_date}"
      end
      puts message
    end
    puts "Discarded data from #{issues_cutoff_times.count} issues out of a total #{issues.size}"
  end
end
