# frozen_string_literal: true

require './spec/spec_helper'

describe DataQualityReport do
  let(:issue1) { load_issue('SP-1') }
  let(:issue10) { load_issue('SP-10') }
  let(:subject) do
    subject = DataQualityReport.new
    subject.issues = [issue10, issue1]

    today = Date.parse('2021-12-17')
    block = lambda do |_|
      start_at first_status_change_after_created
      stop_at last_resolution
    end
    subject.cycletime = CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today

    subject
  end

  it 'should create entries' do
    subject.initialize_entries

    expect(subject.testable_entries).to eq [
      ['2021-06-18T18:43:34+00:00', '', issue1],
      ['2021-08-29T18:06:28+00:00', '2021-09-06T04:34:26+00:00', issue10]
    ]

    expect(subject.entries_with_problems).to be_empty
  end

  it 'should identify items with completed but not started' do
    issue1.changes.clear
    issue1.changes << mock_change(field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    subject.initialize_entries

    subject.scan_for_completed_issues_without_a_start_time

    expect(subject.entries_with_problems.collect { |entry| entry.issue.key }).to eq ['SP-1']
  end
end
