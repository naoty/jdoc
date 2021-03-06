module Jdoc
  class Link
    # @param link [JsonSchema::Schema::Link]
    def initialize(link)
      @raw_link = link
    end

    # @return [String] method + path
    # @example
    #   link.endpoint #=> "GET /apps"
    def endpoint
      "#{method} #{path}"
    end

    # Responds to .sort method
    # @return [Fixnum]
    def <=>(schema)
      sort_key <=> schema.sort_key
    end

    # For #<=> method
    # @return [String]
    def sort_key
      "#{path} #{method_order_score}"
    end

    # @return [String] Description for this endpoint, defined in description property
    # @example
    #   link.description #=> "List existing apps."
    def description
      @raw_link.description
    end

    # @return [String] Href anchor for putting link in ToC
    # @example
    #   link.anchor #=> "#get-apps"
    def anchor
      "#" + endpoint.gsub(" ", "-").gsub(/[:\/]/, "").downcase
    end

    # @return [String] Markdown styled link text for endpoint
    # @example
    #   link.hyperlink #=> "[GET /apps](#get-apps)"
    def hyperlink
      "[#{endpoint}](#{anchor})"
    end

    # @return [String] Upper cased HTTP request method name
    # @example
    #   link.method #=> "GET"
    def method
      @method ||= @raw_link.method.to_s.upcase
    end

    # @return [String] Request path name, defined at href property
    # @note URI Template is replaced with placeholder
    # @example
    #   link.path #=> "GET /apps/:id"
    def path
      @path ||= @raw_link.href.gsub(/{(.+?)}/) do |matched|
        ":" + CGI.unescape($1).gsub(/[()\s]/, "").split("/").last
      end
    end

    # Adds query string if a link has a schema property and method is GET
    # @return [String, nil] A query string prefixed with `?` only to GET request
    # @example
    #   link.query_string #=> "?type=Recipe"
    def query_string
      if method == "GET" && !request_parameters.empty?
        "?#{request_parameters.to_query}"
      end
    end

    # @return [String, nil] Example request body in JSON format
    def request_body
      JSON.pretty_generate(request_parameters) + "\n"
    end

    # @return [Hash] Example request parameters for this endpoint
    def request_parameters
      @request_parameters ||= begin
        if has_schema_in_link?
          RequestGenerator.call(request_schema.properties)
        else
          {}
        end
      end
    end

    # @return [true, false] True if this endpoint must have request body
    def has_request_body?
      ["PATCH", "POST", "PUT"].include?(method)
    end

    # @return [String] JSON response body generated from example properties
    def response_body
      object = has_list_data? ? [response_hash] : response_hash
      JSON.pretty_generate(object)
    end

    # @return [Fixnum] Preferred respone status code for this endpoint
    def response_status
      method == "POST" ? 201 : 200
    end

    # @return [JsonSchema::Schema] Response schema for this link
    def response_schema
      @raw_link.target_schema || @raw_link.parent
    end

    # @return [JsonSchema::Schema] Request schema for this link
    def request_schema
      @raw_link.schema || @raw_link.parent
    end

    # @return [Json::Link::Resource]
    # @note Resource means each property of top-level properties in this context
    def resource
      @resource ||= Resource.new(response_schema)
    end

    private

    # @return [true, false] True if a given link has a schema property
    def has_schema_in_link?
      !!@raw_link.schema
    end

    # @return [true, false] True if response is intended to be list data
    def has_list_data?
      @raw_link.rel == "instances"
    end

    # @return [Hash]
    # @raise [Rack::Spec::Mock::ExampleNotFound]
    def response_hash
      ResponseGenerator.call(response_schema.properties)
    end

    # @return [Fixnum] Order score, used to sort links by preferred method order
    def method_order_score
      case method
      when "GET"
        1
      when "POST"
        2
      when "PUT"
        3
      when "PATCH"
        4
      when "DELETE"
        5
      else
        6
      end
    end

    class RequestGenerator
      # Generates example request body from given schema
      # @param properties [Hash]
      # @note Not includes properties that have readOnly property
      # @return [Hash]
      # @example
      #   Jdoc::Link::RequestGenerator(schema.properties) #=> { "name" => "example", "description" => "foo bar." }
      def self.call(properties)
        ResponseGenerator.call(properties.reject {|key, value| value.data["readOnly"] })
      end
    end

    class ResponseGenerator
      # Generates example response Hash from given schema
      # @param properties [Hash]
      # @return [Hash]
      # @example
      #   Jdoc::Link::ResponseGenerator(properties) #=> { "id" => 1, "name" => "example" }
      def self.call(properties)
        properties.inject({}) do |result, (key, value)|
          result.merge(
            key => case
            when !value.properties.empty?
              call(value.properties)
            when !value.data["example"].nil?
              value.data["example"]
            when value.type.include?("null")
              nil
            when value.type.include?("array")
              if example = value.items.data["example"]
                [example]
              else
                [call(value.items.properties)]
              end
            else
              raise ExampleNotFound, "No example found for #{value.pointer}"
            end
          )
        end
      end
    end

    class ExampleNotFound < StandardError
    end
  end
end
