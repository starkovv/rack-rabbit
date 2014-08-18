require 'securerandom'
require 'rack-rabbit'
require 'rack-rabbit/adapter'

module RackRabbit
  class Client

    #--------------------------------------------------------------------------

    attr_reader :rabbit

    def initialize(options = {})
      @rabbit = Adapter.load(DEFAULT_RABBIT.merge(options))
      connect
    end

    #--------------------------------------------------------------------------

    def connect
      rabbit.connect
    end

    def disconnect
      rabbit.disconnect
    end

    #--------------------------------------------------------------------------

    def get(queue, path, options = {})
      request(queue, "GET", path, "", options)
    end

    def post(queue, path, body, options = {})
      request(queue, "POST", path, body, options)
    end

    def put(queue, path, body, options = {})
      request(queue, "PUT", path, body, options)
    end

    def delete(queue, path, options = {})
      request(queue, "DELETE", path, "", options)
    end

    #--------------------------------------------------------------------------

    def request(queue, method, path, body, options = {})

      id        = SecureRandom.uuid
      lock      = Mutex.new
      condition = ConditionVariable.new
      headers   = options[:headers] || {}
      response  = nil

      rabbit.with_reply_queue do |reply_queue|

        rabbit.subscribe(reply_queue) do |message|
          if message.correlation_id == id
            response = Response.new(message.status, message.headers, message.body)
            lock.synchronize { condition.signal }
          end
        end

        rabbit.publish(body,
          :correlation_id   => id,
          :priority         => options[:priority],
          :routing_key      => queue,
          :reply_to         => reply_queue.name,
          :content_type     => options[:content_type]     || default_content_type,
          :content_encoding => options[:content_encoding] || default_content_encoding,
          :timestamp        => options[:timestamp]        || default_timestamp,
          :headers          => headers.merge({
            RackRabbit::HEADER::METHOD => method.to_s.upcase,
            RackRabbit::HEADER::PATH   => path
          })
        )

      end

      lock.synchronize { condition.wait(lock) }

      response

    end

    #--------------------------------------------------------------------------

    def default_content_type
      'text/plain; charset = "utf-8"'
    end

    def default_content_encoding
      'utf-8'
    end

    def default_timestamp
      Time.now.to_i
    end

    #--------------------------------------------------------------------------

    def self.define_class_method_for(method_name)
      define_singleton_method(method_name) do |*params|
        options  = params.last.is_a?(Hash) ? params.pop : {}
        client   = Client.new(options.delete(:rabbit))
        response = client.send(method_name, *params, options)
        client.disconnect
        response
      end
    end

    define_class_method_for :request
    define_class_method_for :get
    define_class_method_for :post
    define_class_method_for :put
    define_class_method_for :delete

    #--------------------------------------------------------------------------

  end
end
