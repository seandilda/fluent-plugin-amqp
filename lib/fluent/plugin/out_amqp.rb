require 'json'
module Fluent
  ##
  # AMQPOutput to be used as a Fluent MATCHER, sending messages to a RabbitMQ
  # messaging broker
  class AMQPOutput < BufferedOutput
    Plugin.register_output("amqp", self)

    attr_accessor :connection

    config_param :host, :string, :default => nil
    config_param :user, :string, :default => "guest"
    config_param :pass, :string, :default => "guest", :secret => true
    config_param :vhost, :string, :default => "/"
    config_param :port, :integer, :default => 5672
    config_param :ssl, :bool, :default => false
    config_param :verify_ssl, :bool, :default => false
    config_param :heartbeat, :integer, :default => 60
    config_param :exchange, :string, :default => ""
    config_param :exchange_type, :string, :default => "direct"
    config_param :passive, :bool, :default => false
    config_param :durable, :bool, :default => false
    config_param :auto_delete, :bool, :default => false
    config_param :key, :string, :default => nil
    config_param :persistent, :bool, :default => false
    config_param :tag_key, :bool, :default => false
    config_param :tag_header, :string, :default => nil
    config_param :time_header, :string, :default => nil
    config_param :tls, :bool, :default => false
    config_param :tls_cert, :string, :default => nil
    config_param :tls_key, :string, :default => nil
    config_param :tls_ca_certificates, :array, :default => nil
    config_param :tls_verify_peer, :bool, :default => true

    def initialize
      super
      require "bunny"
    end

    def configure(conf)
      super
      @conf = conf
      unless @host
        raise ConfigError, "'host' must be specified."
      end
      unless @key || @tag_key
        raise ConfigError, "Either 'key' or 'tag_key' must be set."
      end
      check_tls_configuration
    end

    def start
      super
      @connection = Bunny.new(get_connection_options) unless @connection

      @connection.start
      @channel = @connection.create_channel
      @exch = @channel.exchange(@exchange, :type => @exchange_type.intern,
                              :passive => @passive, :durable => @durable,
                              :auto_delete => @auto_delete)
    end

    def shutdown
      super
      @connection.stop
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      chunk.msgpack_each do |(tag, time, data)|
        data = JSON.dump( data ) unless data.is_a?( String )
        @exch.publish(data, :key => routing_key( tag ), :persistent => @persistent, :headers => headers( tag, time ))
      end
    end

    def routing_key( tag )
      if @tag_key
        tag
      else
        @key
      end
    end

    def headers( tag, time )
      {}.tap do |h|
        h[@tag_header] = tag if @tag_header
        h[@time_header] = Time.at(time).utc.to_s if @time_header
      end
    end


    private
    def check_tls_configuration()
      if @tls
        unless @tls_key && @tls_cert
            raise ConfigError, "'tls_key' and 'tls_cert' must be all specified if tls is enabled."
        end
      end
    end

    def get_connection_options()
      opts = {
        :host => @host, :port => @port, :vhost => @vhost,
        :pass => @pass, :user => @user, :ssl => @ssl,
        :verify_ssl => @verify_ssl, :heartbeat => @heartbeat,
        :tls                 => @tls,
        :tls_cert            => @tls_cert,
        :tls_key             => @tls_key,
        :verify_peer         => @tls_verify_peer
      }
      opts[:tls_ca_certificates] = @tls_ca_certificates if @tls_ca_certificates
      return opts
    end

  end
end
