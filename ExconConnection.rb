#!/usr/bin/env ruby

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

  attr_reader :cid, :names, :img, :env_vars, :stats, :prev_stats, :inspect_data
  attr_writer :env_vars

  def initialize(cid, names, image)
    @cid = cid
    @names = names
    @img = image
    @env_vars = ""
    @inspect_data = { :env => nil }
    @stats = { :memory_usage => 0.0, :memory_limit => 0.0, :memory_percentage_usage => "0.0%", :network_in => 0.0, :network_out => 0.0, :cpu => 0.0, :cpu_system_usage => 0.0, :cpu_percentage_usage => "0.0%", :disk_io_read => 0.0 }
    @prev_stats = {  :memory_usage => nil, :memory_limit => nil, :memory_percentage_usage => nil, :network_in => nil, :network_out => nil, :cpu => nil, :cpu_system_usage => nil, :cpu_percentage_usage => nil, :disk_io_read => nil }
  end

  def inspect
    ExconConnection.connection.request(:method => :get, :path => "/containers/#{self.cid}/json", :read_timeout => 10, :response_block => streamer_inspect)
  rescue Excon::Errors::Timeout
  rescue Excon::Errors::SocketError => e
    unless e.message.include?('inspect gathered')
     print "Invalid Stats API endpoint", "There was an error reading from the stats API.\nAre you running Docker version 1.5+, and is /var/run/docker.sock readable by the user running scout?"
    end
  end

  def get_stats!
    ExconConnection.connection.request(:method => :get, :path => "/containers/#{self.cid}/stats", :read_timeout => 10, :response_block => streamer)
  rescue Excon::Errors::Timeout
  rescue Excon::Errors::SocketError => e
    unless e.message.include?('stats gathered')
     print "Invalid Stats API endpoint", "There was an error reading from the stats API.\nAre you running Docker version 1.5+, and is /var/run/docker.sock readable by the user running scout?"
    end
  end

  def calc_difference(stat)
    @prev_stats[stat].nil? ? 0 : @stats[stat] - @prev_stats[stat]
  end

  def set_prev_stats(stat)
    @prev_stats[stat] = @stats[stat]
  end

  private

  def streamer_inspect
    lambda do |chunk, remaining_bytes, total_bytes|
      parse_inspect(self.cid, chunk)
      raise 'inspect gathered'
    end
  end

  def parse_inspect(container_id, inspect_string)
    inspect = JSON.parse(inspect_string)
    @inspect_data[:env] = inspect["Config"]["Env"]
  end

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
    @stats[:network_in] = stats["network"]["rx_bytes"].to_f / 1024.0
    @stats[:network_out] = stats["network"]["tx_bytes"].to_f / 1024.0
    @stats[:cpu_usage] = (stats["cpu_stats"]["cpu_usage"]["total_usage"].to_f).round(3)
    @stats[:cpu_system_usage] = (stats["cpu_stats"]["system_cpu_usage"].to_f).round(3)
    #Percentage
    @stats[:cpu_percentage_usage] = ((@stats[:cpu_usage]/@stats[:cpu_system_usage])*100).round(3)
    unless stats["blkio_stats"]["io_service_bytes_recursive"].empty?
      @stats[:disk_io_read] = stats["blkio_stats"]["io_service_bytes_recursive"].first["value"].to_f / 1024.0 / 1024.0
    end
  end
end

class ContainerMonitor

  attr_reader :containers

  def initialize
    @containers = []
    refresh_containers
  end

  def read_stat(container)
    summary_str = [ "containerId=#{container.cid}",
		    "containerImg=#{container.img}",
		    "containerName=#{container.names.first}"
    ]


  end

  def send_stats
    refresh_containers
    containers.each do |container|
      container.get_stats!
      summary_str = _read_stat(container)

      print "containerId=#{container.cid} "
      print "containerImg=#{container.img} "
      print "containerName=#{container.names.first} "

      container.inspect
      container.env_vars = container.inspect_data[:env].join(" ")
      print "#{container.env_vars} "

      container.get_stats!
      keepKeys = [:memory_limit, :memory_percentage_usage, :cpu_system_usage, :cpu_percentage_usage]
      container.stats.each do |key, value|
        if keepKeys.include? key
          print "#{key}=#{value} "
        else
	  diff = container.calc_difference(key)
          print "#{key}=#{diff} "
          container.set_prev_stats(key)
        end
      end
      print "\n"
    end
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

