require 'hashie/hash'
require 'set'

module Hashie
  # A Dash is a 'defined' or 'discrete' Hash, that is, a Hash
  # that has a set of defined keys that are accessible (with
  # optional defaults) and only those keys may be set or read.
  #
  # Dashes are useful when you need to create a very simple
  # lightweight data object that needs even fewer options and
  # resources than something like a DataMapper resource.
  #
  # It is preferrable to a Struct because of the in-class
  # API for defining properties as well as per-property defaults.
  class Dash < Hashie::Hash
    include Hashie::PrettyInspect
    alias_method :to_s, :inspect

    # Defines a property on the Dash. Options are
    # as follows:
    #
    # * <tt>:default</tt> - Specify a default value for this property,
    #   to be returned before a value is set on the property in a new
    #   Dash.
    #
    # * <tt>:required</tt> - Specify the value as required for this
    #   property, to raise an error if a value is unset in a new or
    #   existing Dash.
    #
    def self.property(property_name, options = {})
      property_name = property_name.to_sym

      self.properties << property_name

      if options.has_key?(:default)
        self.defaults[property_name] = options[:default]
      elsif self.defaults.has_key?(property_name)
        self.defaults.delete property_name
      end

      if options.has_key?(:validate)
        self.validates[property_name] = options[:validate]
      elsif self.validates.has_key?(property_name)
        self.validates.delete property_name
      end

      if defined? @subclasses
        @subclasses.each { |klass| klass.property(property_name, options) }
      end
      required_properties << property_name if options.delete(:required)
    end

    class << self
      attr_reader :properties, :defaults, :validates
      attr_reader :required_properties
    end
    instance_variable_set('@properties', Set.new)
    instance_variable_set('@defaults', {})
    instance_variable_set('@validates', {})
    instance_variable_set('@required_properties', Set.new)

    def self.inherited(klass)
      super
      (@subclasses ||= Set.new) << klass
      klass.instance_variable_set('@properties', self.properties.dup)
      klass.instance_variable_set('@defaults', self.defaults.dup)
      klass.instance_variable_set('@validates', self.validates.dup)
      klass.instance_variable_set('@required_properties', self.required_properties.dup)
    end

    # Check to see if the specified property has already been
    # defined.
    def self.property?(name)
      properties.include? name.to_sym
    end

    # Check to see if the specified property is
    # required.
    def self.required?(name)
      required_properties.include? name.to_sym
    end

    # You may initialize a Dash with an attributes hash
    # just like you would many other kinds of data objects.
    def initialize(attributes = {}, &block)
      super(&block)

      self.class.defaults.each_pair do |prop, value|
        self[prop] = value
      end

      attributes.each_pair do |att, value|
        self[att] = value
      end if attributes
      assert_required_properties_set!
    end

    alias_method :_regular_reader, :[]
    alias_method :_regular_writer, :[]=
    private :_regular_reader, :_regular_writer

    # Retrieve a value from the Dash (will return the
    # property's default value if it hasn't been set).
    def [](property)
      assert_property_exists! property
      value = super(property.to_s)
      yield value if block_given?
      value
    end

    # Set a value on the Dash in a Hash-like way. Only works
    # on pre-existing properties.
    def []=(property, value)
      assert_property_required! property, value
      assert_property_exists! property
      assert_property_validate! property, value
      super(property.to_s, value)
    end

    private

      def assert_property_exists!(property)
        unless self.class.property?(property)
          raise NoMethodError, "The property '#{property}' is not defined for this Dash."
        end
      end

      def assert_required_properties_set!
        self.class.required_properties.each do |required_property|
          assert_property_set!(required_property)
        end
      end

      def assert_property_validate!(property, value)
        validate = self.class.validates[property.to_sym] || self.class.validates[property.to_s]

        # https://github.com/amazonwebservices/aws-sdk-for-ruby/blob/master/lib/aws/dynamo_db/types.rb
        return if validate.nil?
        if validate == :n && !(value.kind_of?(Numeric))
          raise ArgumentError, "The property '#{property}' v(#{value}) is not Numeric, it is a #{value.class}."
        elsif validate == :s && !(value.kind_of?(String))
          raise ArgumentError, "The property '#{property}' v(#{value}) is not a String, it is a #{value.class}."
        elsif validate.kind_of?(Regexp) && !(value =~ validate)
          raise ArgumentError, "The property '#{property}' v(#{value}) must match regexp /#{validate}/."
        elsif validate == :ss || validate == :ns
          if !value.respond_to?(:each)
            raise ArgumentError, "The property '#{property}' is not a Collection." 
          end

          value.each do |v| 
            if v.respond_to?(each)
              raise ArgumentError, "The property '#{property}' has nested collections."
            elsif (validate == :ss && !(value.kind_of?(String))) or
                  (validate == :ns && !(value.kind_of?(Numeric)))
              raise ArgumentError, "The property '#{property}' has elements not of type #{validate.to_s}."
            end 
          end
        end
      end

      def assert_property_set!(property)
        if self[property.to_sym].nil? && self[property.to_s].nil?
          raise ArgumentError, "The property '#{property}' is required for this Dash."
        end
      end

      def assert_property_required!(property, value)
        if self.class.required?(property) && value.nil?
          raise ArgumentError, "The property '#{property}' is required for this Dash."
        end
      end

  end
end
