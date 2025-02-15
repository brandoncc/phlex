# frozen_string_literal: true
require "digest"

module Phlex
  class Component

    SUBCOMPONENT_REGEX = /component\s([A-Z]+[A-Za-z:]*)/

    module Overrides
      def initialize(*args, cache: false, **kwargs, &block)
        @_cache = cache
        @_content = block

        super(*args, **kwargs)
      end

      def call
        return super unless @_cache
        Rails.cache.fetch(self) { super }
      end
    end

    extend Cacheable
    include Node, Context

    class << self
      def inherited(child)
        child.prepend(Overrides)
        super
      end

      def cache_key
        @cache_key ||= CacheKey.new(
          super,
          subcomponents,
          cacheable_ancestors
        )
      end

      def cache_version
        @cache_version ||= CacheVersion.new(
          super,
          subcomponents,
          cacheable_ancestors
        )
      end

      def subcomponents
        @subcomponents ||= direct_subcomponents.reduce(Set.new) do |set, component|
          set << component
          component.subcomponents.each { set << _1 }
          set
        end
      end

      private

      def cacheable_ancestors
        @cacheable_ancestors ||= ancestors.lazy
          .reject { [self, Object, BasicObject, Kernel].include? _1 }
          .reject { _1.name.start_with? "Phlex::" }
          .map { CacheableObject.new(_1) }.to_a
      end

      def direct_subcomponents
        source_file.scan(SUBCOMPONENT_REGEX).flatten.map do
          Phlex.find_constant(_1, relative_to: self)
        end
      end
    end

    def initialize(**attributes)
      attributes.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def call
      template(&@_content)
      super
    end

    def target
      @_target || self
    end

    def <<(node)
      target.children << node
    end

    def content
      yield(self) if block_given?
    end

    def render_block(new_target, ...)
      old_target = target
      @_target = new_target
      instance_exec(...)
      @_target = old_target
    end

    def cache_key
      @cache_key ||= CacheKey.new(
        self.class,
        cacheable_content,
        cacheable_resources
      )
    end

    def cache_version
      @cache_version ||= CacheVersion.new(
        RUBY_VERSION,
        Phlex::VERSION,
        self.class,
        cacheable_content,
        cacheable_resources
      )
    end

    private

    def cacheable_resources
      (@_cache == true) ? assigns : @_cache
    end

    def cacheable_content
      CacheableObject.new(@_content)
    end

    def assigns
      instance_variables
        .reject { _1.start_with? "@_" }
        .map { [_1, instance_variable_get(_1)] }.to_h
    end
  end
end
