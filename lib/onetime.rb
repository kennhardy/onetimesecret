# https://github.com/shuber/encryptor

require 'bundler/setup'

require 'syslog'

require 'encryptor'
require 'bcrypt'
require 'sysinfo'
require 'gibbler'
require 'familia'
require 'storable'

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)
Gibbler.secret = "(I AM THE ONE TRUE SECRET!)".freeze
Familia.secret = "[WHAT IS UP MY FAMILIALS??]".freeze

class String
  def to_file(filename, mode, chmod=0744)
    mode = (mode == :append) ? 'a' : 'w'
    f = File.open(filename,mode)
    f.puts self
    f.close
    raise "Provided chmod is not a Fixnum (#{chmod})" unless chmod.is_a?(Fixnum)
    File.chmod(chmod, filename)
  end
end


module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    ERRNO = {
      :internalerror.gibbler.short => 'Not found',
      :nosecret.gibbler.short => 'No secret provided',
    }.freeze unless defined?(Onetime::ERRNO)
  end
  @debug = false
  @mode = :app
  class << self
    attr_accessor :debug, :mode
    attr_reader :conf
    def mode? guess
      @mode.to_s == guess.to_s
    end
    def errno name
      name.gibbler.short
    end
    def load! mode=nil, base=Onetime::HOME
      OT.mode = mode unless mode.nil?
      @conf = OT::Config.load
      Familia.uri = Onetime.conf[:redis][:uri]
      ld "---  ONETIME v#{OT::VERSION}  -----------------------------------"
      ld "Connection: #{Familia.uri}"
      @conf
    end
    def info(*msg)
      prefix = "(#{Time.now}):  "
      SYSLOG.info "#{prefix}" << msg.join("#{$/}#{prefix}")
    end
    def sysinfo
      @sysinfo = SysInfo.new.freeze if @sysinfo.nil?
      @sysinfo
    end
    def ld(*msg)
      return unless Onetime.debug
      prefix = "D:  "
      SYSINFO.crit "#{prefix}" << msg.join("#{$/}#{prefix}")
    end
  end
  
  module Config
    extend self
    SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
    UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
    attr_reader :env, :base, :bootstrap
    def load path=self.path
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)
      YAML.load_file path
    end
    def exists?
      !config_path.nil?
    end
    def path
      find_configs.first
    end
    def find_configs
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect { |f| 
        f = File.join File.expand_path(f), 'config'
        Onetime.ld "Looking for #{f}"
        f if File.exists?(f) 
      }.compact
    end
  end
  
  module VERSION
    def self.to_a
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH], @version[:BUILD]]
    end
    def self.to_s
      to_a[0..-2].join('.')
    end
    def self.inspect
      to_a.join('.')
    end
    def self.increment!(msg=nil)
      load_config
      @version[:BUILD] = @version[:BUILD].to_s.succ!
      @version[:STAMP] = Time.now.utc.to_i
      @version[:OWNER] = OT.sysinfo.user
      @version[:STORY] = msg || '[no message]'
      @version.to_yaml.to_file File.join(OT::HOME, 'BUILD.yml'), 'w'
      @version
    end
    def self.load_config
      return if @version
      require 'yaml'
      @version = YAML.load_file(File.join(OT::HOME, 'BUILD.yml'))
    end
  end
  
  module Utils
    extend self
    unless defined?(VALID_CHARS)
      VALID_CHARS = [("a".."z").to_a, ("A".."Z").to_a, ("0".."9").to_a, %w[* $ ! ? ( )]].flatten
      VALID_CHARS_SAFE = VALID_CHARS.clone
      VALID_CHARS_SAFE.delete_if { |v| %w(i l o 1 0).member?(v) }
      VALID_CHARS.freeze
      VALID_CHARS_SAFE.freeze
    end
    def strand(len=12, safe=true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size-1)] }.join
    end
  end
  
  class MissingSecret < RuntimeError
  end
end
OT = Onetime

require 'onetime/models'

Onetime::Secret.db 0
Kernel.srand


