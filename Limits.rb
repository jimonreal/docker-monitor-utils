#!/usr/bin/env ruby

class Limits
    attr_reader :warningLimit, :criticalLimit

    def initialize(warn, crit)
        @warningLimit = warn
        @criticalLimit = crit
    end
end

