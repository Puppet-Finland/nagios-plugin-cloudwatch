#!/usr/bin/env ruby

require 'aws-sdk-cloudwatch'
require 'yaml'
require 'optparse'

class CloudWatchMetrics

  attr_reader :nagios_metrics

  def initialize(settings = {})
    @region = settings[:region]
    @aws_access_key_id = settings[:aws_access_key_id]
    @aws_secret_access_key = settings[:aws_secret_access_key]
    @namespace = settings[:namespace]
    @dimensions = settings[:dimensions]

    # Convert the keys in the dimensions array to Symbols. This is required by
    # the AWS get_metric_statistics method call. This requires Ruby 2.5 or
    # greater.
    #
    # https://stackoverflow.com/questions/800122/best-way-to-convert-strings-to-symbols-in-hash
    #
    @dimensions.each do |dimension|
      dimension.transform_keys!(&:to_sym)
      #dimension.transform_keys! { |key| key.to_sym }
    end

    # Optional parameters
    settings.has_key?(:precision) ? @precision = settings[:precision] : @precision = 2
    settings.has_key?(:period) ? @period = settings[:period] : @period = 600

    # The desired metrics
    @metrics = settings[:metrics]

    # This will get populated by the AWS API calls
    @metric_statistics = {}

    # These are the human readable matric-value pairs also used by the nagios
    # plugin code for graph names and alert messages.
    @nagios_metrics = {}

    # This stores information about statistics that are above the defined thresholds
    @issues = {}

    # This stores the aggregate exit status
    # 
    # 1: any of the statistics exceeded the critical threshold
    # 2: any of the statistics exceeded the warning threshold
    # 0: all statistics were below the thresholds
    #
    @exit_code = 0

    # Update the AWS settings
    Aws.config.update({ region: @region,
                        credentials: Aws::Credentials.new(@aws_access_key_id, @aws_secret_access_key)
                      })

    @client = Aws::CloudWatch::Client.new(region: @region)
  end

  def populate_metrics
    base_parameters = { namespace: @namespace,
                        dimensions: @dimensions,
                        start_time: Time.now - @period,
                        end_time: Time.now,
                        period: @period
                      }

    @metrics.each_pair do |metric, parameters|
      aws_statistics = parameters['statistics'].clone

      # If a statistic (e.g. "average") has children then we must flatten it
      # for the AWS API call. We need those children entries for the optional
      # alert thresholds.
      parameters['statistics'].each_with_index do |statistic, index|
        aws_statistics[index] = statistic.keys[0] if statistic.is_a?(Hash)
      end

      @metric_statistics[metric] = @client.get_metric_statistics(params=base_parameters.merge(metric_name:  parameters['metric_name'],
                                                                                              unit:         parameters['unit'],
                                                                                              statistics:   aws_statistics))

      # Construct a human readable hash of metric names and their respective values
      aws_statistics.each do |statistic|
        key = "#{metric}_#{parameters['unit'].downcase}_#{statistic.downcase}"
        value = "#{@metric_statistics[metric]['datapoints'][0][statistic.downcase.to_sym]}"
        @nagios_metrics[key] = value.to_f
      end
    end
  end

  # Get the "human readable" first part of Nagios plugin output
  def get_service_output
    # Figure out if we are OK or if the status is WARN or CRITICAL
    if @issues.empty?
      "#{@namespace} #{@dimensions[0][:value]} OK"
    else
      "#{@namespace} #{@dimensions[0][:value]} #{self.issues_to_s}"
    end
  end

  # Get the optional performance data that follows the human readable part
  def get_service_perf_data
    output = ""
    @nagios_metrics.each do |key, value|
      output << "#{key}=#{value.round(@precision)}, "
    end
    output.chomp(', ')
  end

  def puts_and_exit
    puts "#{self.get_service_output} | #{self.get_service_perf_data}"
    exit(@exit_code)
  end

  def get_metric_status
    @metrics.each do |metric, value|
      @metrics[metric]['statistics'].each do |statistic|
        if statistic.is_a?(Hash)
          unit = @metrics[metric]['unit'].downcase
          statistic_name = statistic.keys[0]
          warn_threshold = statistic[statistic_name]['warn_threshold'].to_f
          critical_threshold = statistic[statistic_name]['critical_threshold'].to_f
          statistic_path = "#{metric}_#{unit}_#{statistic_name.downcase}"
          
          # Populate the issues hash which we will use to construct CRITICAL
          # and WARNING messages. Also set the exit code if any warnings or
          # critical issues are found.
          if @nagios_metrics[statistic_path] > critical_threshold
            @issues[statistic_path] = { status: 'critical', current: @nagios_metrics[statistic_path].round(@precision), warning: warn_threshold, critical: critical_threshold }
            @exit_code = 1
          elsif @nagios_metrics[statistic_path] > warn_threshold
            @issues[statistic_path] = { status: 'warning', current: @nagios_metrics[statistic_path].round(@precision), warning: warn_threshold, critical: critical_threshold } 

            # If we already have a critical problem we don't want to override
            # it with a warning exit code
            @exit_code = 2 unless @exit_code == 1
          end
        end
      end
    end
  end

  # Convert the issues has into a printable string
  def issues_to_s
    issues = ""
    @issues.each do |statistic, data|
      issues << "#{data[:status].upcase}: #{statistic}=#{data[:current]} exceeds the #{data[:status]} threshold of #{data[data[:status].to_sym]}! "
    end
    issues.chomp(' ')
  end
end

### Main program

# Parse command-line options
options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: check_rds -c config_file"
  opts.on( '-c', '--config file', 'Path to the config file' ) do |file|
    options[:config_file] = file
  end
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

optparse.parse!

begin
  config = YAML.load_file(options[:config_file])
rescue Errno::ENOENT
  puts "ERROR: config file #{options[:config_file]} not found!"
  exit 1
end

settings = config['defaults']

# Mandatory settings
cloudwatch_settings = { region: settings['region'],
                        aws_access_key_id: settings['aws_access_key_id'],
                        aws_secret_access_key: settings['aws_secret_access_key'],
                        namespace: settings['namespace'],
                        dimensions: settings['dimensions'],
                        metrics: settings['metrics'] }

# Optional settings: rounding precision (default 3) and time period (default 600 seconds)
cloudwatch_settings.merge!(precision: settings['precision']) if settings.has_key?('precision')
cloudwatch_settings.merge!(period: settings['period']) if settings.has_key?('period')
cloudwatch = CloudWatchMetrics.new(cloudwatch_settings)

cloudwatch.populate_metrics
cloudwatch.get_metric_status
cloudwatch.puts_and_exit
