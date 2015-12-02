#!/usr/bin/env ruby

require_relative 'ExconConnection'

require 'optparse'
require 'ostruct'

class Parser
	def self.parse(args)
		options = OpenStruct.new
		options.url = "unix://var/run/docker.sock"
		options.log_path = "/var/log/docker-stats.log"
		options.delay = 2

		opt_parser = OptionParser.new do |opts|
			opts.banner = "Usage: example run.rb [options]"

			opts.separator ""
			opts.separator "Specific options:"

			opts.on("-w_cpu", "--warn-cpu WARNING_LIMIT", "Warning percentage limit for CPU usage") do |warn|
				options.warn_cpu << warn
			end
			opts.on("-c_cpu", "--critical-cpu CRITICAL_LIMIT", "Critical percentage limit for CPU usage") do |crit|
				options.crit_cpu << crit
			end
			opts.on("-w_ram", "--warn-ram WARNING_LIMIT", "Warning percentage limit for RAM usage") do |warn|
				options.warn_ram << warn
			end
			opts.on("-c_ram", "--critical-ram CRITICAL_LIMIT", "Critical percentage limit for RAM usage") do |crit|
				options.crit_ram << crit
			end
			opts.on("-w_disk", "--warn-disk WARNING_LIMIT", "Warning percentage limit for IO DISK usage") do |warn|
				options.warn_disk << warn
			end
			opts.on("-c_disk", "--critical-disk CRITICAL_LIMIT", "Critical percentage limit for IO DISK usage") do |crit|
				options.crit_disk << crit
			end
			opts.on("-w_net", "--warn-net WARNING_LIMIT", "Warning percentage limit for IO NET usage") do |warn|
				options.warn_net << warn
			end
			opts.on("-c_net", "--critical-net CRITICAL_LIMIT", "Critical percentage limit for IO NET usage") do |crit|
				options.crit_net << crit
			end

			opts.on("-u", "--url URL", "Docker socket URL") do |url|
				options.inplace = true
				options.url = url
			end

			opts.on("-l", "--log-path PATH", "Absolute path of the log file") do |log|
				options.inplace = true
				options.log_path = log
			end

			opts.on("-d", "--delay SECONDS", "Delay in seconds to collect data") do |secs|
				options.inplace = true
				options.delay = secs
			end

			opts.on_tail("-h", "--help", "Help") do
				puts opts
				exit
			end
		end
		
		opt_parser.parse!(args)
		options
	end
end

## Main ##
options = Parser.parse(ARGV)

c = ContainerMonitor.new
loop do
	sleep options[:delay]
	c.send_stats
end

