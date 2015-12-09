#!/usr/bin/env ruby
#
require 'socket'

class Nagios

    attr_reader :status, :cpuLimit, :ramLimit, :netInLimit, :netOutLimit, :diskLimit, :msg, :hostname, :nagiosServer

    OK = 0
    WARNING = 1
    CRITICAL = 2
    UNKNOWN = 3

    def initialize(server, cpuLimits, ramLimits, diskLimits, netInLimits, netOutLimits)
        @nagiosServer = server
	@cpuLimit = cpuLimits
	@ramLimit = ramLimits
	@netInLimit = netInLimits
	@netOutLimit = netOutLimits
	@diskLimit = diskLimits

	@hostname = Socket.gethostname

	@status = Hash.new({})

	@msg = []
    end

    def reset
        @msg = []
	@status = Hash.new({})
    end

    def monitorContainerStats(cid, stats)
	#CPU
        @status[:"#{cid}"][:CPU] = validateLimit(cid, stats["cpu_percentage_usage"].to_f, "CPU", cpuLimit)
	#RAM
        @status[:"#{cid}"][:RAM] = validateLimit(cid, stats["memory_percentage_usage"].to_f, "RAM", ramLimit)
	#NET
        @status[:"#{cid}"][:NETIN] = validateLimit(cid, stats["network_in"].to_f, "NETIN", netInLimit)
        @status[:"#{cid}"][:NETOUT] = validateLimit(cid, stats["network_out"].to_f, "NETOUT", netOutLimit)
	#DISK
        @status[:"#{cid}"][:DISK] = validateLimit(cid, stats["disk_io_service_bytes"].to_f, "DISK", diskLimit)
    end

    def responseExitCode
        #TODO LLAMADA A NAGIOS CON FORMAT
	message = ""
        if msg.empty?
            message = "OK: Everything is OK"
	else
            message = msg.join('::')
	end
	statusExit = getStatusExit
	response = sprintf("%s\t%s\t%d\t%s\n", hostname, "Docker Stats", statusExit, message)
	cmd = "/usr/sbin/send_nsca -H #{nagiosServer} #{response}"
	puts `#{cmd}`
    end

    def getStatusExit
        statusToReturn = OK
	status.each do |cid, innerHash|
            if innerHash.has_value?(CRITICAL)
                statusToReturn = CRITICAL
		break
            elsif innerHash.has_value(WARNING)
                statusToReturn = WARNING
            end
	end
        return statusToReturn
    end

    private
    def validateLimit(cid, usage, resource, limit)
	status = UNKNOWN
        if usage >= limit.criticalLimit
            msg.push("WARNING " + resource + ": The Container " + cid + " has % level of " + resource + ": " + usage)
            status = WARNING
	elsif usage >= limit.warningLimit
            msg.push("CRITICAL " + resource + ": The Container " + cid + " has % level of " + resource + ": " + usage)
            status = CRITICAL
	else
            status = OK
	end

	return status
    end
end
