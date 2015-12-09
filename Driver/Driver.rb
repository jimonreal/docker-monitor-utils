#!/usr/bin/env ruby

require_relative 'Nagios'
require_relative 'DummyDriver'

module Driver
    class << self
        attr_reader :driver
    
        def new(driverName, server, cpuLimits, ramLimits, diskLimits, netInLimits, netOutLimits)
    	    if driverName.downcase.eql? "nagios"
                    @driver = Nagios.new(server, cpuLimits, ramLimits, diskLimits, netInLimits, netOutLimits)
                else
                    @driver = DummyDriver.new
    	    end
    	    return driver
        end
    end
end

