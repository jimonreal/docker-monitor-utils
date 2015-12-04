#!/usr/bin/env ruby

class Driver

    def initialize(driver, cpuLimits, ramLimits, diskLimits, netLimits)
	    if driver.downcase.eql? "nagios"
		    return Nagios.new(cpuLimits, ramLimits, diskLimits, netLimits)
	    end
    end
end

