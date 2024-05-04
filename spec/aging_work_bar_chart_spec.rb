# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  let(:chart) { described_class.new }

  context 'data_set_by_block' do
    it 'handles nothing blocked at all' do
      issue = load_issue('SP-1')
      data_sets = chart.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| false }

      expect(data_sets).to eq({
        backgroundColor: 'red',
        data: [],
        stack: 'blocked',
        stacked: true,
        type: 'bar'
      })
    end

    it 'handles a single blocked range completely within the date range' do
      issue = load_issue('SP-1')
      data_sets = chart.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..6).cover? day.day }

      expect(data_sets).to eq(
        {
          backgroundColor: 'red',
          data: [
            {
              title: 'Story : Blocked 4 days',
              x: %w[2022-01-03 2022-01-06],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      )
    end

    it 'handles multiple blocked ranges, all completely within the date range' do
      issue = load_issue('SP-1')
      data_set = chart.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..4).cover?(day.day) || day.day == 6 }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set[:data]).to eq([
        {
          title: 'Story : Blocked 2 days',
          x: %w[2022-01-03 2022-01-04],
          y: 'SP-1'
        },
        {
          title: 'Story : Blocked 1 day',
          x: %w[2022-01-06 2022-01-06],
          y: 'SP-1'
        }
      ])
    end

    it 'never becomes unblocked' do
      issue = load_issue('SP-1')
      data_set = chart.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| true }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set[:data]).to eq([
        {
          title: 'Story : Blocked 10 days',
          x: %w[2022-01-01 2022-01-10],
          y: 'SP-1'
        }
      ])
    end
  end

  context 'status_data_sets' do
    it 'returns nil if no status' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-01', nil]])
      data_sets = chart.status_data_sets(
        issue: issue, label: issue.key, today: to_date('2021-01-05')
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--status-category-todo-color'],
          data: [
            {
              title: 'Bug : Backlog',
              x: ['2021-01-01T00:00:00+0000', '2021-01-05T00:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'status',
          stacked: true,
          type: 'bar'
        }
      ])
    end
  end

  context 'blocked_data_sets' do
    let(:board) do
      board = sample_board
      board.project_config = ProjectConfig.new(
        exporter: Exporter.new, target_path: 'spec/testdata/', jira_config: nil, block: nil
      )
      board
    end

    it 'handles blocked by flag' do
      chart.settings = board.project_config.settings
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(field: 'Flagged', value: 'Flagged', time: '2021-01-02T01:00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',        time: '2021-01-02T02:00:00')

      data_sets = chart.blocked_data_sets(
        issue: issue, stack: 'blocked', issue_label: 'SP-1', issue_start_time: issue.created
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--blocked-color'],
          data: [
            {
              title: 'Blocked by flag',
              x: ['2021-01-02T01:00:00+0000', '2021-01-02T02:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      ])
    end

    it 'handles blocked by status' do
      chart.settings = board.project_config.settings
      chart.settings['blocked_statuses'] = ['Blocked']
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(field: 'status', value: 'Blocked', time: '2021-01-02')
      issue.changes << mock_change(field: 'status', value: 'Doing',   time: '2021-01-03')

      data_sets = chart.blocked_data_sets(
        issue: issue, stack: 'blocked', issue_label: 'SP-1', issue_start_time: issue.created
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--blocked-color'],
          data: [
            {
              title: 'Blocked by status: Blocked',
              x: ['2021-01-02T00:00:00+0000', '2021-01-03T00:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      ])
    end

    it 'handle blocked by issue' do
      chart.settings = board.project_config.settings
      chart.settings['blocked_link_text'] = ['is blocked by']

      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(
        field: 'Link', value: 'This issue is blocked by SP-10', time: '2021-01-02'
      )
      issue.changes << mock_change(
        field: 'Link', value: nil, old_value: 'This issue is blocked by SP-10', time: '2021-01-03'
      )

      data_sets = chart.blocked_data_sets(
        issue: issue, stack: 'blocked', issue_label: 'SP-1', issue_start_time: issue.created
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--blocked-color'],
          data: [
            {
              title: 'Blocked by issues: SP-10',
              x: ['2021-01-02T00:00:00+0000', '2021-01-03T00:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      ])
    end
  end
end
