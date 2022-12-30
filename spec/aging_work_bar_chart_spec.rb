# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  context 'data_set_by_block' do
    let(:subject) { AgingWorkBarChart.new }

    it 'should handle nothing blocked at all' do
      issue = load_issue('SP-1')
      data_sets = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| false }

      expect(data_sets).to be_nil
    end

    it 'should handle a single blocked range completely within the date range' do
      issue = load_issue('SP-1')
      data_sets = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..6).include? day.day }

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

    it 'should handle multiple blocked ranges, all completely within the date range' do
      issue = load_issue('SP-1')
      data_set = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..4).include?(day.day) || day.day == 6 }

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
      data_set = subject.data_set_by_block(
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
    let(:subject) { AgingWorkBarChart.new }

    it 'should return nil if no status' do
      subject.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      subject.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-01', nil]])
      data_sets = subject.status_data_sets(
        issue: issue, label: issue.key, today: to_date('2021-01-05')
      )
      expect(data_sets).to eq([
        {
          backgroundColor: 'gray',
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
end
