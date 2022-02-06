# frozen_string_literal: true

require 'random-word'

class Anonymizer
  def initialize issues:, all_board_metadata:, possible_statuses:
    @issues = issues
    @all_board_metadata = all_board_metadata
    @possible_statuses = possible_statuses
  end

  def run
    anonymize_issue_keys_and_titles
    anonymize_column_names
    anonymize_issue_statuses
    puts 'Anonymize done'
  end

  def anonymize_issue_keys_and_titles
    puts 'Anonymizing issue ids and descriptions'
    counter = 1
    @issues.each do |issue|
      new_key = "ANON-#{counter += 1}"

      issue.raw['key'] = new_key
      issue.raw['fields']['summary'] = RandomWord.phrases.next.gsub(/_/, ' ')
    end
  end

  def anonymize_column_names
    @all_board_metadata.each_key do |board_id|
      puts "Anonymizing column names for board #{board_id}"

      column_name = 'Column-A'
      @all_board_metadata[board_id].each do |column|
        column.name = column_name
        column_name = column_name.next
      end
    end
  end

  def build_status_name_hash
    next_status = 'a'
    status_name_hash = {}
    @issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        # TODO: Do old value too
        status_key = "#{issue.type}-#{change.value}"
        if status_name_hash[status_key].nil?
          status_name_hash[status_key] = "#{issue.type.downcase}-status-#{next_status}"
          next_status = next_status.next
        end
      end
    end

    @possible_statuses.each do |status|
      status_key = "#{status.type}-#{status.name}"
      if status_name_hash[status_key].nil?
        status_name_hash[status_key] = "#{status.type.downcase}-status-#{next_status}"
        next_status = next_status.next
      end
    end

    status_name_hash
  end

  def anonymize_issue_statuses
    puts 'Anonymizing issue statuses and status categories'
    status_name_hash = build_status_name_hash

    @issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        status_key = "#{issue.type}-#{change.value}"
        anonymized_value = status_name_hash[status_key]
        raise "status_name_hash[#{status_key.inspect} is nil" if anonymized_value.nil?

        change.value = anonymized_value

        next if change.old_value.nil?

        status_key = "#{issue.type}-#{change.old_value}"
        anonymized_value = status_name_hash[status_key]
        raise "status_name_hash[#{status_key.inspect} is nil" if anonymized_value.nil?

        change.old_value = anonymized_value
      end
    end

    @possible_statuses.each do |status|
      status_key = "#{status.type}-#{status.name}"
      if status_name_hash[status_key].nil?
        raise "Can't find status_key #{status_key.inspect} in #{status_name_hash.inspect}"
      end

      status.name = status_name_hash[status_key] unless status_name_hash[status_key].nil?
    end
  end
end

