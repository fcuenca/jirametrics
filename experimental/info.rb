# frozen_string_literal: true

require 'require_all'
require_all 'lib'

class InfoDumper
  def initialize
    @target_dir = 'target/'
  end

  def run key
    find_file_prefixes.each do |prefix|
      issues = load_issues target_path: @target_dir, file_prefix: prefix
      issues.select { |issue| issue.key == key }.each do |issue|
        dump issue
      end
    end
  end

  def find_file_prefixes
    prefixes = []
    Dir.foreach @target_dir do |file|
      prefixes << $1 if file =~ /^(.+)_0.json/
    end
    prefixes
  end

  def load_issues target_path:, file_prefix:
    issues = []
    Dir.foreach(target_path) do |filename|
      if filename =~ /#{file_prefix}_\d+\.json/
        content = JSON.parse File.read("#{target_path}#{filename}")
        content['issues'].each { |issue| issues << Issue.new(issue) }
      end
    end
    issues
  end

  def dump issue
    puts "#{issue.key} : #{compact_text issue.summary, 200}"

    assignee = issue.raw['fields']['assignee']
    puts "  [assignee] #{assignee['name'].inspect} <#{assignee['emailAddress']}>" unless assignee.nil?

    issue.raw['fields']['issuelinks'].each do |link|
      puts "  [link] #{link['type']['outward']} #{link['outwardIssue']['key']}" if link['outwardIssue']
      puts "  [link] #{link['type']['inward']} #{link['inwardIssue']['key']}" if link['inwardIssue']
    end
    issue.changes.each do |change|
      value = change.value
      old_value = change.old_value

      # Description fields get pretty verbose so reduce the clutter
      if change.field == 'description' || change.field == 'summary'
        value = compact_text value
        old_value = compact_text old_value
      end
      # puts change.raw
      author = change.author
      author = "(#{author})" if author
      message = "  [change] #{change.time} [#{change.field}] "
      message << "#{old_value.inspect} -> " unless old_value.nil? || old_value.empty?
      message << value.inspect
      message << " #{author}" if author
      puts message
    end
    puts ''
  end

  def compact_text text, max = 40
    text = text.gsub(/\s+/, ' ').strip
    text = "#{text[0..max]}..." if text.length > max
    text
  end
end

ARGV.each do |key|
  InfoDumper.new.run key
end

