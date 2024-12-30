# frozen_string_literal: true

# RSpec.configure do |config|
#   config.formatter = :html
# end

ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  SimpleCov.add_filter do |src_file|
    File.basename(src_file.filename) == 'config.rb'
  end
end

require 'require_all'
require_all 'lib'

def file_read filename
  File.read filename, encoding: 'UTF-8'
end

def make_test_filename basename
  "spec/tmp/#{basename}"
end

def sample_board
  statuses = load_statuses './spec/testdata/sample_statuses.json'
  Board.new raw: JSON.parse(file_read('spec/testdata/sample_board_1_configuration.json')), possible_statuses: statuses
end

def load_issue key, board: nil
  board = sample_board if board.nil?
  issue = Issue.new(raw: JSON.parse(file_read("spec/testdata/#{key}.json")), board: board)
  issue.raw['exporter'] = 1 # Make it look like this issue was actually loaded from Jira. Ie not artificial.
  issue
end

def empty_issue created:, board: sample_board, key: 'SP-1', creation_status: nil
  unless creation_status
    backlog_statuses = board.possible_statuses.find_all_by_name('Backlog')
    raise 'No Backlog status found' if backlog_statuses.empty?

    creation_status = [backlog_statuses.first.name, backlog_statuses.first.id]
  end

  Issue.new(
    raw: {
      'key' => key,
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => to_time(created).to_s,
        'status' => {
          'name' => creation_status[0],
          'id' => creation_status[1].to_s
        },
        'issuetype' => {
          'name' => 'Bug'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        },
        'summary' => 'Do the thing'
      }
    },
    board: board
  )
end

def load_complete_sample_issues board:
  result = []
  Dir.each_child './spec/complete_sample/sample_issues' do |file|
    next unless file.match?(/SP-.+/)

    result << Issue.new(raw: JSON.parse(file_read("./spec/complete_sample/sample_issues/#{file}")), board: board)
  end

  # Sort them back into the order they would have come from Jira because some of the tests are order dependant.
  result.sort_by(&:key_as_i).reverse
end

def load_complete_sample_board
  json = JSON.parse(file_read('./spec/complete_sample/sample_board_1_configuration.json'))
  board = Board.new raw: json, possible_statuses: load_complete_sample_statuses
  board.project_config = ProjectConfig.new(
    exporter: Exporter.new, target_path: 'spec/testdata/', jira_config: nil, block: nil
  )

  board
end

def load_complete_sample_statuses
  load_statuses './spec/complete_sample/sample_statuses.json'
end

def load_statuses input_file
  statuses = StatusCollection.new

  json = JSON.parse(File.read(input_file))
  json.each do |status_config|
    statuses << Status.from_raw(status_config)
  end
  statuses
end

def load_complete_sample_date_range
  to_time('2021-09-14T00:00:00+00:00')..to_time('2021-12-13T23:59:59+00:00')
end

def add_mock_change issue:, field:, value:, time:, value_id: nil, old_value: nil, old_value_id: nil, artificial: false
  issue.changes << mock_change(
    issue: issue,
    field: field, time: time,
    value: value, value_id: value_id,
    old_value: old_value, old_value_id: old_value_id,
    artificial: artificial
  )
end

# If either value or old_value are statuses then the name and id will be pulled from that object
def mock_change field:, value:, time:, value_id: nil, old_value: nil, old_value_id: nil, artificial: false, issue: nil
  if value.is_a? Status
    value_id = value.id
    value = value.name
  end
  if old_value.is_a? Status
    old_value_id = old_value.id
    old_value = old_value.name
  end

  # Now that we know that status names are not unique, we have to specify an id every time we use a status name
  if field == 'status' && issue
    possible_statuses = issue.board.possible_statuses

    if value && !value_id
      guesses = possible_statuses.find_all_by_name(value).collect(&:id)
      message = "ID was not specified for new status #{value.inspect}. "
      if guesses.empty?
        message << "No statuses with name #{value.inspect} but did find these: #{possible_statuses.inspect}"
      else
        message << "Perhaps you meant one of #{guesses.inspect}"
      end
      raise message
    end

    if old_value && !old_value_id
      guesses = possible_statuses.find_all_by_name(old_value).collect(&:id)
      raise "ID was not specified for old status #{old_value.inspect}. Perhaps you meant one of #{guesses.inspect}"
    end

    if value_id
      status = possible_statuses.find_by_id(value_id)
      raise "No status found for id: #{value_id} (#{value.inspect}) in #{possible_statuses.inspect}" unless status

      unless status.name == value
        raise "Value passed to mock_change (#{value.inspect}:#{value_id.inspect}) " \
          "doesn't match the status found in the board (#{status})"
      end
    end
    if old_value_id
      status = possible_statuses.find_by_id(old_value_id)
      unless status
        raise "No status found for id: #{old_value_id} (#{old_value.inspect}) in #{possible_statuses.inspect}"
      end

      unless status.name == old_value
        raise "Old value passed to mock_change (#{old_value.inspect}:#{old_value_id.inspect}) " \
          "doesn't match the status found in the board (#{status})"
      end
    end
  end

  time = to_time(time) if time.is_a? String
  ChangeItem.new time: time, author: 'Tolkien', artificial: artificial, raw: {
    'field' => field,
    'to' => value_id,
    'toString' => value,
    'from' => old_value_id,
    'fromString' => old_value
  }
end

def mock_cycletime_config stub_values: []
  raise 'Stubs must be arrays of [issue, start_time, stop_time] tuples' unless stub_values.is_a? Array

  stub_values.each do |line|
    unless line[0].is_a? Issue
      raise 'Parameters to mock_cycletime_config must be an array of [issue, start_time, end_time] tuples'
    end

    line[1] = to_time(line[1]) if line[1].is_a? String
    line[2] = to_time(line[2]) if line[2].is_a? String
  end

  # TODO: Remove duplication in each of start_at/stop_at
  config = CycleTimeConfig.new parent_config: nil, label: nil, block: nil
  config.start_at(lambda do |issue|
    change = stub_values.find { |stub_issue, _start, _stop| stub_issue == issue }&.[](1)
    case change
    when nil
      nil
    when ChangeItem
      change
    else
      mock_change(field: 'status', value: 'fake', value_id: 1_000_001, time: change&.to_time)
    end
  end)
  config.stop_at(lambda do |issue|
    change = stub_values.find { |stub_issue, _start, _stop| stub_issue == issue }&.[](2)
    case change
    when nil
      nil
    when ChangeItem
      change
    else
      mock_change(field: 'status', value: 'fake', value_id: 1_000_001, time: change&.to_time)
    end
  end)
  config
end

def default_cycletime_config
  today = Date.parse('2021-12-17')

  block = lambda do |_|
    start_at ->(issue) { mock_change field: 'status', value: 'fake', value_id: 1_000_000, time: issue.created }
    stop_at last_resolution
  end
  CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today
end

# Duplicated from ChartBase. Should this be in a module?
def chart_format object
  if object.is_a? Time
    # "2022-04-09T11:38:30-07:00"
    object.strftime '%Y-%m-%dT%H:%M:%S%z'
  else
    object.to_s
  end
end

def to_time string
  case string
  when Date
    Time.new string.year, string.month, string.day, 0, 0, 0, '+00:00'
  when /^(\d{4})-(\d{2})-(\d{2})$/
    Time.new $1.to_i, $2.to_i, $3.to_i, 0, 0, 0, '+00:00'
  when /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/
    Time.new $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, '+00:00'
  else
    Time.parse string
  end
end

def to_date string
  Date.parse string
end

def empty_config_block
  ->(_) {}
end
