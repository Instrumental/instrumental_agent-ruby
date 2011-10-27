#!/usr/bin/env ruby

require 'rubygems'
$: << File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'instrumental_agent'


class SystemInspector
  TYPES = [:gauges, :incrementors]
  attr_accessor *TYPES

  def initialize
    @gauges = {}
    @incrementors = {}
    @platform =
      case RUBY_PLATFORM
      when /linux/
        Linux
      when /darwin/
        OSX
      else
        raise "unsupported OS"
      end
  end

  def load_all
    load @platform.load_cpu
    load @platform.load_memory
    load @platform.load_disks
  end

  def load(stats)
    @gauges.merge!(stats[:gauges] || {})
  end

  module OSX
    def self.load_cpu
      { :gauges => top }
    end

    def self.top
      lines = []
      processes = date = load = cpu = nil
      IO.popen('top -l 1 -n 0') do |top|
        processes = top.gets.split(': ')[1]
        date = top.gets
        load = top.gets.split(': ')[1]
        cpu = top.gets.split(': ')[1]
      end

      user, system, idle = cpu.split(", ").map { |v| v.to_f }
      load1, load5, load15 = load.split(", ").map { |v| v.to_f }
      total, running, stuck, sleeping, threads = processes.split(", ").map { |v| v.to_i }

      {
        'cpu.user' => user,
        'cpu.system' => system,
        'cpu.idle' => idle,
        'load.1min' => load1,
        'load.5min' => load5,
        'load.15min' => load15,
        'processes.total' => total,
        'processes.running' => running,
        'processes.stuck' => stuck,
        'processes.sleeping' => sleeping,
        'threads' => threads,
      }
    end

    def self.load_memory
      # TODO: swap
      { :gauges => vm_stat }
    end

    def self.vm_stat
      header, *rows = `vm_stat`.split("\n")
      page_size = header.match(/page size of (\d+) bytes/)[1].to_i
      sections = ["free", "active", "inactive", "wired", "speculative", "wired down"]
      output = {}
      total = 0.0
      rows.each do |row|
        if match = row.match(/Pages (.*):\s+(\d+)\./)
          section, value = match[1, 2]
          if sections.include?(section)
            value = value.to_f * page_size / 1024 / 1024
            output["memory.#{section.gsub(' ', '_')}_mb"] = value
            total += value
          end
        end
      end
      output["memory.free_percent"] = output["memory.free_mb"] / total * 100 # TODO: verify
      output
    end

    def self.load_disks
      { :gauges => df }
    end

    def self.df
      output = {}
      `df -k`.split("\n").grep(%r{^/dev/}).each do |line|
        device, total, used, available, capacity, mount = line.split(/\s+/)
        names = [File.basename(device)]
        names << 'root' if mount == '/'
        names.each do |name|
          output["disk.#{name}.total_mb"] = total.to_f / 1024
          output["disk.#{name}.used_mb"] = used.to_f / 1024
          output["disk.#{name}.available_mb"] = available.to_f / 1024
          output["disk.#{name}.available_percent"] = available.to_f / total.to_f * 100
        end
      end
      output
    end

    def self.netstat(interface = 'en1')
      # mostly functional network io stats
      headers, *lines = `netstat -ibI #{interface}`.split("\n").map { |l| l.split(/\s+/) } # FIXME: vulnerability?
      headers = headers.map { |h| h.downcase }
      lines.each do |line|
        if !line[3].include?(':')
          return Hash[headers.zip(line)]
        end
      end
    end
  end

  module Linux
    def self.load_cpu
      output = { :gauges => {} }
      output[:gauges].merge!(cpu)
      output[:gauges].merge!(loadavg)
      output
    end

    def self.cpu
      cpu, user, nice, system, idle, iowait = `cat /proc/stat | grep cpu[^0-9]`.chomp.split(/\s+/)
      total = user.to_i + system.to_i + idle.to_i + iowait.to_i
      {
        'cpu.user' => (user.to_f / total) * 100,
        'cpu.system' => (system.to_f / total) * 100,
        'cpu.idle' => (idle.to_f / total) * 100,
        'cpu.iowait' => (iowait.to_f / total) * 100,
      }
    end

    def self.loadavg
      min_1, min_5, min_15 = `cat /proc/loadavg`.split(/\s+/)
      {
        'load.1min' => min_1.to_f,
        'load.5min' => min_5.to_f,
        'load.15min' => min_15.to_f,
      }
    end

    def self.load_memory
      output = { :gauges => {} }
      output[:gauges].merge!(memory)
      output[:gauges].merge!(swap)
      output
    end

    def self.memory
      _, total, used, free, shared, buffers, cached = `free -k -o | grep Mem`.chomp.split(/\s+/)
      {
        'memory.used_mb' => used.to_f / 1024,
        'memory.free_mb' => free.to_f / 1024,
        'memory.buffers_mb' => buffers.to_f / 1024,
        'memory.cached_mb' => cached.to_f / 1024,
        'memory.free_percent' => (free.to_f / total.to_f) * 100,
      }
    end

    def self.swap
      _, total, used, free = `free -k -o | grep Swap`.chomp.split(/\s+/)
      {
        'swap.used_mb' => used.to_f / 1024,
        'swap.free_mb' => free.to_f / 1024,
        'swap.free_percent' => (free.to_f / total.to_f) * 100,
      }
    end

    def self.load_disks
      { :gauges => disks }
    end

    def self.disks
      output = {}
      `df -Pk`.split("\n").grep(%r{^/dev/}).each do |line|
        device, total, used, available, capacity, mount = line.split(/\s+/)
        names = [File.basename(device)]
        names << 'root' if mount == '/'
        names.each do |name|
          output["disk.#{name}.total_mb"] = total.to_f / 1024
          output["disk.#{name}.used_mb"] = used.to_f / 1024
          output["disk.#{name}.available_mb"] = available.to_f / 1024
          output["disk.#{name}.available_percent"] = available.to_f / total.to_f * 100
        end
      end
      output
    end
  end
end

# TODO: utilization

token, collector = *ARGV
unless token
  puts "Usage: #{$0} <token> [collector]"
  exit 1
end
I = Instrumental::Agent.new(token, :collector => collector)

host = `hostname`.chomp

puts "Collecting stats under the hostname: #{host}"

loop do
  inspector = SystemInspector.new
  inspector.load_all
  inspector.gauges.each do |stat, value|
    I.gauge("#{host}.#{stat}", value)
  end
  # I.increment("#{host}.#{stat}", delta)
  sleep 1
end
