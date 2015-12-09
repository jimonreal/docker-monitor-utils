#!/usr/bin/env ruby

require_relative 'ExconConnection'
require_relative 'Limits'

require 'optparse'
require 'ostruct'

class Parser
	def self.parse(args)
		options = OpenStruct.new
		options.url = "unix://var/run/docker.sock"
		options.log_path = "/var/log/docker-stats.log"
		options.delay = 2
		options.warn_cpu = 30
		options.crit_cpu = 80
		options.warn_ram = 50
		options.crit_ram = 80
		options.warn_net_in = 50
		options.crit_net_in = 80
		options.warn_net_out = 50
		options.crit_net_out = 80
		options.warn_disk = 50
		options.crit_disk = 80
		options.driver = "nagios"
		options.server_addr = "nagios1dal"

		opt_parser = OptionParser.new do |opts|
			opts.banner = "Usage: example run.rb [options]"

			opts.separator ""
			opts.separator "Specific options:"

			opts.on("--warn-cpu", Integer, "Warning percentage limit for CPU usage") do |warn|
				options.warn_cpu = warn
			end
			opts.on("--critical-cpu", Integer, "Critical percentage limit for CPU usage") do |crit|
				options.crit_cpu = crit
			end
			opts.on("--warn-ram", Integer, "Warning percentage limit for RAM usage") do |warn|
				options.warn_ram = warn
			end
			opts.on("--critical-ram", Integer, "Critical percentage limit for RAM usage") do |crit|
				options.crit_ram = crit
			end
			opts.on("--warn-disk", Integer, "Warning percentage limit for IO DISK usage") do |warn|
				options.warn_disk = warn
			end
			opts.on("--critical-disk", Integer, "Critical percentage limit for IO DISK usage") do |crit|
				options.crit_disk = crit
			end
			opts.on("--warn-net-in", Integer, "Warning percentage limit for IO NET IN usage") do |warn|
				options.warn_net_in = warn
			end
			opts.on("--critical-net-in", Integer, "Critical percentage limit for IO NET IN usage") do |crit|
				options.crit_net_in = crit
			end

			opts.on("--warn-net-out", Integer, "Warning percentage limit for IO NET OUT usage") do |warn|
				options.warn_net_out = warn
			end
			opts.on("--critical-net-out", Integer, "Critical percentage limit for IO NET OUT usage") do |crit|
				options.crit_net_out = crit
			end

			opts.on("-D", "--driver [DRIVERNAME]", "Driver to be used") do |driver|
				options.driver = driver
			end

			opts.on("-s", "--server-addr [HOSTNAME]", "Hostname of driver server") do |addr|
				options.server_addr = addr
			end

			opts.on("-u", "--url [URL]", "Docker socket URL") do |url|
				options.url = url
			end

			opts.on("-l", "--log-path [PATH]", "Absolute path of the log file") do |log|
				options.log_path = log
			end

			opts.on("-d", "--delay [SECONDS]", "Delay in seconds to collect data") do |secs|
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

cpuLimits = Limits.new(options[:warn_cpu], options[:crit_cpu])
ramLimits = Limits.new(options[:warn_ram], options[:crit_ram])
netInLimits = Limits.new(options[:warn_net_in], options[:crit_net_in])
netOutLimits = Limits.new(options[:warn_net_out], options[:crit_net_out])
diskLimits = Limits.new(options[:warn_disk], options[:crit_disk])

c = ContainerMonitor.new(cpuLimits, ramLimits, diskLimits, netInLimits, netOutLimits, options[:driver], options[:server_addr])
loop do
	sleep options[:delay]
	c.send_stats(options[:log_path])
end

