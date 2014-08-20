require 'deep_cloneable'

module AppDup
  module Duper
    DEFAULT_DUP_OPTIONS = { models: :all, exclusions: [] }

    def dup(opts = {})
      sanitize_args(opts, DEFAULT_DUP_OPTIONS.keys, raise: true)
      opts.reverse_merge!(DEFAULT_DUP_OPTIONS)

      case opts[:models]
      when :all
        models = ActiveRecord::Base.descendants
        models.reject!{|m| opts[:exclusions].include?(m.name.underscore.pluralize.to_sym)}
      when Array
        models = opts[:models].map do |m|
          m = m.to_s.classify.constantize unless m.is_a?(Class)
          m < ActiveRecord::Base ? m : raise(ArgumentError, "#{m} is not an ActiveRecord model")
        end
      end

      tree = build_tree(models, opts)
      dict = {} # uber important

      tree.each do |model, dup_hash|
        model.all.each.map do |i|
          i.dup include: dup_hash, dup_habtm: true, dictionary: dict
        end
      end

      return dict
    end

    def build_tree(models, opts = {})
      analysed = []
      tree = {}
      models.each do |m|
        tree[m] = discover(m, opts[:exclusions], analysed)
      end
      tree
    end

    private
      def discover(model, exclusions = [], analysed)
        belongs_to_reflections = model.reflect_on_all_associations(:belongs_to)
        habtm_reflections = model.reflect_on_all_associations(:has_and_belongs_to_many)
        excluded_associations = (exclusions.find{|e| e.is_a?(Hash) && e.key?(:model)} || {})[model] || []
        reflections = (belongs_to_reflections + habtm_reflections).reject do |r|
          exclusions.include?(r.klass.name.underscore.pluralize.to_sym) ||
            excluded_associations.include?(r.name)
        end
        analysed << model

        reflections.empty? ? {} : begin
          hash = {}
          reflections.each do |r|
            if analysed.include?(r.klass)
              hash[r.name] = {} if r.macro != :has_and_belongs_to_many
            else
              hash[r.name] = discover(r.klass, exclusions, analysed)
            end
          end
          hash
        end
      end

      def sanitize_args(hash, keys, opts = {})
        unrecognised_keys = hash.keys - keys
        if opts[:raise] && unrecognised_keys.any?
          raise ArgumentError, "Unrecognised keys: #{unrecognised_keys}"
        end
        hash.except!(unrecognised_keys)
      end
  end
end
