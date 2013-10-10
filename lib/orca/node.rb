require 'net/ssh'
require 'net/sftp'

class Orca::Node
  attr_reader :name, :host

  def self.find(name)
    return name if name.is_a?(Orca::Node)
    @nodes[name]
  end

  def self.register(node)
    @nodes ||= {}
    Orca::Group.from_node(node)
    @nodes[node.name] = node
  end

  def initialize(name, host, options={})
    @name = name
    @host = host
    @options = options
    @connection = nil
    @history = []
    Orca::Node.register(self)
  end

  def get(option)
    @options[option]
  end

  def method_missing(meth, *args)
    get(meth)
  end

  def upload(from, to)
    log.sftp("UPLOAD: #{from} => #{to}")
    sftp.upload!(from, to)
  end

  def download(from, to)
    log.sftp("DOWLOAD: #{from} => #{to}")
    sftp.download!(from, to)
  end

  def remove(path)
    log.sftp("REMOVE: #{path}")
    begin
      sftp.remove!(path)
    rescue Net::SFTP::StatusException
      sudo("rm #{path}")
    end
  end

  def stat(path)
    log.sftp("STAT: #{path}")
    sftp.stat!(path)
  end

  def setstat(path, opts)
    log.sftp("SET: #{path} - #{opts.inspect}")
    sftp.setstat!(path, opts)
  end

  def sftp
    @sftp ||= connection.sftp.connect
  end

  def execute(cmd, opts={})
    if should_execute?(cmd, opts)
      really_execute(cmd, opts)
    else
      cached_execute(cmd, opts)
    end
  end

  def sudo(cmd, opts={})
    with_external_password = opts[:with_external_password]
    if with_external_password.is_a?(String)
      execute("echo #{with_external_password} | sudo -S  #{cmd}", opts)
    else
      execute("sudo #{cmd}", opts)
    end
  end

  def log
    @log
  end

  def log_to(log)
    @log = log
  end

  def connection
    return @connection if @connection
    @connection = Net::SSH.start(@host, (@options[:user] || 'root'), options_for_ssh)
  end

  def disconnect
    @connection.close if @connection && !@connection.closed?
  end

  def to_s
    "#{name}(#{host})"
  end

  private

  def options_for_ssh
    opts = [:auth_methods, :compression, :compression_level, :config, :encryption , :forward_agent , :global_known_hosts_file , :hmac , :host_key , :host_key_alias , :host_name, :kex , :keys , :key_data , :keys_only , :logger , :paranoid , :passphrase , :password , :port , :properties , :proxy , :rekey_blocks_limit , :rekey_limit , :rekey_packet_limit , :timeout , :user , :user_known_hosts_file , :verbose ]
    @options.reduce({}) do |hsh, (k,v)|
      hsh[k] = v if opts.include?(k)
      hsh
    end
  end

  def cached_execute(cmd, opts={})
    log.cached(cmd)
    last_output(cmd)
  end

  def really_execute(cmd, opts={})
    log.execute(cmd.cyan)
    output = ""
    connection.exec! cmd do |channel, stream, data|
      output += data if stream == :stdout
      data.split("\n").each do |line|
        log.send(stream, line, opts[:log])
      end
    end
    @history << {cmd:cmd, output:output}
    output
  end

  def should_execute?(cmd, opts)
    return true unless opts[:once]
    last_output(cmd).nil?
  end

  def last_output(cmd)
    results = @history.select {|h| h[:cmd] == cmd }
    return nil unless results && results.size > 0
    results.last[:output]
  end
end