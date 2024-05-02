# frozen_string_literal: true

require 'fileutils'

class Object
  def deprecated message:
    text = +''
    text << 'Deprecated:'
    text << message
    text << "\n-> Called from #{caller(1..1).first}"
    warn text
  end
end

class Exporter
  attr_reader :project_configs, :file_system

  def self.configure &block
    logfile_name = 'jirametrics.log'
    logfile = File.open logfile_name, 'w'
    file_system = FileSystem.new
    file_system.logfile = logfile
    file_system.logfile_name = logfile_name

    exporter = Exporter.new file_system: file_system

    exporter.instance_eval(&block)
    @@instance = exporter
  end

  def self.instance = @@instance

  def initialize file_system: FileSystem.new
    @project_configs = []
    @timezone_offset = '+00:00'
    @target_path = '.'
    @holiday_dates = []
    @downloading = false
    @file_system = file_system
  end

  def export name_filter:
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level
      project.run
    end
  end

  def download name_filter:
    @downloading = true
    # logfile_name = 'downloader.log'
    # File.open logfile_name, 'w' do |logfile|
      # file_system.logfile = logfile
      # file_system.logfile_name = logfile_name

      each_project_config(name_filter: name_filter) do |project|
        project.evaluate_next_level
        next if project.aggregated_project?

        project.download_config.run
        downloader = Downloader.new(
          download_config: project.download_config,
          file_system: file_system,
          jira_gateway: JiraGateway.new(file_system: file_system)
        )
        downloader.run
      end
    # end
    puts "Full output from downloader in #{file_system.logfile_name}"
  end

  def each_project_config name_filter:
    @project_configs.each do |project|
      yield project if project.name.nil? || File.fnmatch(name_filter, project.name)
    end
  end

  def downloading?
    @downloading
  end

  def project name: nil, &block
    raise 'target_path was never set!' if @target_path.nil?
    raise 'jira_config not set' if @jira_config.nil?

    @project_configs << ProjectConfig.new(
      exporter: self, target_path: @target_path, jira_config: @jira_config, block: block, name: name
    )
  end

  def xproject *args; end

  def target_path path = nil
    unless path.nil?
      @target_path = path
      @target_path += File::SEPARATOR unless @target_path.end_with? File::SEPARATOR
      FileUtils.mkdir_p @target_path
    end
    @target_path
  end

  def jira_config filename = nil
    @jira_config = file_system.load_json(filename) unless filename.nil?
    @jira_config
  end

  def timezone_offset offset = nil
    @timezone_offset = offset unless offset.nil?
    @timezone_offset
  end

  def holiday_dates *args
    unless args.empty?
      dates = []
      args.each do |arg|
        if arg =~ /^(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})$/
          Date.parse($1).upto(Date.parse($2)).each { |date| dates << date }
        else
          dates << Date.parse(arg)
        end
      end
      @holiday_dates = dates
    end
    @holiday_dates
  end
end
