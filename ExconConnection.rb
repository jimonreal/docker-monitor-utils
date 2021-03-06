#!/usr/bin/env ruby

require_relative 'Driver/Driver'

require 'excon'
require 'json'

module ExconConnection

  class << self
    
    def connection
      Excon.new('unix:///', :socket => socket_path)
    end

    def socket_path
      unless(@socket_path)
        if(File.exists?('/host/var/run/docker.sock'))
          @socket_path = '/host/var/run/docker.sock'
        else
          @socket_path = '/var/run/docker.sock'
        end
      end
      @socket_path
    end
  end
end

class Container

  attr_reader :cid, :names, :img, :stats, :prev_stats, :inspect_data

  def initialize(cid, names, image)
    @cid = cid
    @names = names
    @img = image
    @stats = { :memory_usage => 0.0, :memory_limit => 0.0, :memory_percentage_usage => "0.0%", :network_in => 0.0, :network_out => 0.0, :cpu => 0.0, :cpu_system_usage => 0.0, :cpu_percentage_usage => "0.0%", :disk_io_read => 0.0 }
    @prev_stats = {  :memory_usage => nil, :memory_limit => nil, :memory_percentage_usage => nil, :network_in => nil, :network_out => nil, :cpu => nil, :cpu_system_usage => nil, :cpu_percentage_usage => nil, :disk_io_read => nil }
  end

  def get_stats!
    ExconConnection.connection.request(:method => :get, :path => "/containers/#{self.cid}/stats", :read_timeout => 10, :response_block => streamer)
  rescue Excon::Errors::Timeout
  rescue Excon::Errors::SocketError => e
    unless e.message.include?('stats gathered')
     print "Invalid Stats API endpoint", "There was an error reading from the stats API.\nAre you running Docker version 1.5+, and is /var/run/docker.sock readable by the user running the script?"
    end
  end

  def calc_difference(stat)
    @prev_stats[stat].nil? ? 0 : @stats[stat] - @prev_stats[stat]
  end

  def set_prev_stats(stat)
    @prev_stats[stat] = @stats[stat]
  end

  private

  def streamer
    lambda do |chunk, remaining_bytes, total_bytes|
      parse_stats(self.cid, chunk)
      raise 'stats gathered'
    end
  end

  def parse_stats(container_id, stats_string)
    stats = JSON.parse(stats_string)
    @stats[:memory_usage] = (stats["memory_stats"]["usage"].to_f / 1024.0 / 1024.0).round(3)
    @stats[:memory_limit] = (stats["memory_stats"]["limit"].to_f / 1024.0 / 1024.0).round(3)
    #Percentage
    @stats[:memory_percentage_usage] = ((@stats[:memory_usage]/@stats[:memory_limit])*100).round(3)
    #TODO: Fix the interface to be dynamic
    @stats[:network_in] = stats["networks"]["eth0"]["rx_bytes"].to_f / 1024.0
    @stats[:network_out] = stats["networks"]["eth0"]["tx_bytes"].to_f / 1024.0
    @stats[:cpu_usage] = (stats["cpu_stats"]["cpu_usage"]["total_usage"].to_f).round(3)
    @stats[:cpu_system_usage] = (stats["cpu_stats"]["system_cpu_usage"].to_f).round(3)
#    #Percentage
    @stats[:cpu_percentage_usage] = ((@stats[:cpu_usage]/@stats[:cpu_system_usage])*100).round(3)
    unless stats["blkio_stats"]["io_service_bytes_recursive"].empty?
      @stats[:disk_io_service_bytes] = stats["blkio_stats"]["io_service_bytes_recursive"].first["value"].to_f / 1024.0 / 1024.0
    end
  end
end

class ContainerMonitor

  attr_reader :containers, :cpuLimits, :ramLimits, :diskLimits, :netLimits, :driver

  def initialize(cpuLimits, ramLimits, diskLimits, netInLimits, netOutLimits, driver, server)
    @containers = []
    @cpuLimits = cpuLimits
    @ramLimits = ramLimits
    @diskLimits = diskLimits
    @netLimits = netLimits
    @driver = Driver.new(driver, server, cpuLimits, ramLimits, diskLimits, netInLimits, netOutLimits)
    refresh_containers
  end

  def read_stat(container)
      summary_str = "containerId=#{container.cid} " +
          	    "containerImg=#{container.img} " +
          	    "containerName=#{container.names.first} "

      container.get_stats!
      keepKeys = [:memory_limit, :memory_percentage_usage, :cpu_system_usage, :cpu_percentage_usage]
      container.stats.each do |key, value|
          if keepKeys.include? key
              summary_str += "#{key}=#{value} "
          else
              diff = container.calc_difference(key)
              summary_str += "#{key}=#{diff} "
              container.set_prev_stats(key)
          end
      end

      summary_str.rstrip

      return summary_str
  end

  def send_stats(logger)
    refresh_containers
    driver.reset
    containers.each do |container|
      container.get_stats!
      summary_str = read_stat(container)
      summary_hash = Hash[summary_str.scan /([^=\s]+)=(\S+)/]
      driver.monitorContainerStats(container.cid, summary_hash)
      logger.info summary_str
    end
    driver.responseExitCode
  end

  private

  def get_containers
    response = ExconConnection.connection.request(:method => :get, :path => "/containers/json")
    containers = JSON.parse(response.body)
  end

  def create_new_container(container)
    Container.new(container["Id"], container["Names"].map { |name| name.gsub(/\A\//, '') }, container["Image"])
  end

  def build_container_list(containers)
    containers.map { |container| create_new_container(container) }
  end

  def check_for_new_containers(new_containers)
    new_containers.each do |new_container|
      unless @containers.any? { |existing_container| existing_container.cid == new_container.cid }
        @containers << new_container
      end
    end
  end

  def check_for_shutdown_containers(new_containers)
    @containers.each do |existing_container|
      unless new_containers.any? { |new_container| new_container.cid == existing_container.cid }
        @containers.delete(existing_container)
      end
    end
  end

  def refresh_containers
    if @containers.empty?
      @containers = build_container_list(get_containers)
    else
      new_containers = build_container_list(get_containers)
      check_for_new_containers(new_containers)
      check_for_shutdown_containers(new_containers)
    end
  end
end

