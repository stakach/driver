require "json"

class PlaceOS::Driver::Proxy::Driver
  def initialize(
    @reply_id : String,
    @module_name : String,
    @index : Int32,
    @module_id : String,
    @system : PlaceOS::Driver::Proxy::System,
    @metadata : PlaceOS::Driver::DriverModel::Metadata
  )
    @status = PlaceOS::Driver::Storage.new(@module_id)
  end

  getter :module_name, :index

  def [](status)
    value = @status[status]
    JSON.parse(value)
  end

  def []?(status)
    value = @status[status]?
    JSON.parse(value) if value
  end

  def status(klass, key)
    klass.from_json(@status[key.to_s])
  end

  def status?(klass, key)
    value = @status[key.to_s]?
    klass.from_json(value) if value
  end

  # This deliberately prevents compilation if called from driver code
  def []=(status, value)
    {{ raise "Remote drivers are read only. Please use the public interface to modify state" }}
  end

  def implements?(interface) : Bool
    @metadata.implements.includes?(interface.to_s) || !!@metadata.functions[interface.to_s]?
  end

  # All subscriptions to external drivers should be indirect as the driver might
  # be swapped into a completely different system - whilst we've looked up the id
  # of this instance of a driver, it's expected that this object is short lived
  def subscribe(status, &callback : (PlaceOS::Driver::Subscriptions::IndirectSubscription, String) -> Nil) : PlaceOS::Driver::Subscriptions::IndirectSubscription
    @system.subscribe(@module_name, @index, status, &callback)
  end

  # Don't raise errors directly.
  # Ensure they are logged and raise if the response is requested
  macro method_missing(call)
    function_name = {{call.name.id.stringify}}
    function = @metadata.functions[function_name]?

    # obtain the arguments provided
    arguments = {{call.args}} {% if call.args.size == 0 %} of String {% end %}
    {% if !call.named_args.is_a?(Nop) && call.named_args.size > 0 %}
      named_args = {
        {% for arg, index in call.named_args %}
          {{arg.name.stringify.id}}: {{arg.value}},
        {% end %}
      }
    {% else %}
      named_args = {} of String => String
    {% end %}

    # Execute is deferred so execution flow isn't interruped. }
    # Can use `.get` to syncronise
    __exec_request__(function_name, function, arguments, named_args)
  end

  private def __exec_request__(function_name, function, arguments, named_args)
    if function
      # Check if there is an argument mismatch }
      num_args = arguments.size + named_args.size
      funcsize = function.size
      if num_args > funcsize
        raise "wrong number of arguments for '#{function_name}' on #{@module_name}_#{@index} - #{@module_id} (given #{num_args}, expected #{funcsize})"
      elsif num_args < funcsize
        defaults = 0

        # check for defaults if there are not enough arguments
        function.each_value do |arg_details|
          defaults += 1 if arg_details.size > 1
        end

        minargs = funcsize - defaults
        raise "wrong number of arguments for '#{function_name}' on #{@module_name}_#{@index} - #{@module_id} (given #{num_args}, expected #{minargs}..#{funcsize})" if num_args < minargs
      end

      # Build the request payload
      request = String.build do |str|
        str << %({"__exec__":") << function_name << %(",") << function_name << %(":{)

        # Apply the arguments
        index = 0
        named_keys = named_args.keys.map &.to_s
        function.each_key do |arg_name|
          value = if named_keys.includes?(arg_name)
                    named_args[arg_name]?
                  else
                    index += 1
                    arguments[index - 1]?
                  end

          # Enums are special case
          if value.is_a?(::Enum)
            str << '"' << arg_name << %(":) << value.to_s.to_json << ','
          else
            str << '"' << arg_name << %(":) << value.to_json << ','
          end
        end
        # remove the trailing comma
        str.back(1) if function.size > 0
        str << "}}"
      end

      # parse the execute response
      channel = PlaceOS::Driver::Protocol.instance.expect_response(@module_id, @reply_id, "exec", request, raw: true)

      # Grab the result if required
      lazy do
        result = channel.receive

        if error = result.error
          backtrace = result.backtrace || [] of String
          exception = PlaceOS::Driver::RemoteException.new(result.payload, error, backtrace)
          @system.logger.warn "#{exception.message}\n#{exception.backtrace?.try &.join("\n")}"
          raise exception
        else
          JSON.parse(result.payload.not_nil!)
        end
      end
    else
      raise "undefined method '#{function_name}' for #{@module_name}_#{@index} (#{@module_id})"
    end
  rescue error
    @system.logger.warn error.inspect_with_backtrace
    lazy { raise error; JSON.parse("") }
  end
end
