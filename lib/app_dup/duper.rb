require 'deep_cloneable'

module AppDup
  class Duper
    # TODO: bring in AR-import for performance!

    attr_accessor :from, :to, :options, :data, :results, :models

    DEFAULT_OPTIONS     = { create_db: false }
    DEFAULT_DUP_OPTIONS = { models: :all, exclusions: nil }

    def initialize(options)
      if (options.keys & [:from, :to]).size != 2
        raise "must provide `from` and `to` options for initialization"
      end

      @from = options.delete(:from)
      @to = options.delete(:to)

      @options = options.reverse_merge!(DEFAULT_OPTIONS)
    end

    def run
      # 1. connect to old DB
      connect_to(@from)
      # 2. copy EVERYTHING into memory... x_x
      @data = Duper.dup
      # 3. create new db?
      create_db(@to) unless options[:create_db]
      # 4. connect to the new DB
      connect_to(@to)
      # 5. transform the data however required
      transform
      # before_dump hook!
      before_dump
      # 5. save all the data! and do it in a transaction so we don't end up with
      # fragmented data if it cacks out with an exception
      ActiveRecord::Base.transaction do
        # DUUUUUMPPPP.
        @results = @data.map do |model_name, (_, dups)|
          [model_name, dups.map(&:save)]
        end
        # do something if errors? :/
      end
      # after_dump hook!
      after_dump
      # count of the `save` return values.. lame
      return @results.inject({}){|h,(m,r)| h[m] = r.size}
    ensure
      # don't leave the user connected to some other database,
      # ensure we reconnect to the environment db
      connect_to(ENV['RAILS_ENV'])
    end

    def transform
      logger.info("`transform` not implemented")
    end

    def before_dump
    end

    def after_dump
    end

    def self.dup(opts = {})
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
          # TODO: hack deep_cloneable not to duplicate associations
          # for dictionary items..
          i.dup include: dup_hash, dup_habtm: true, dictionary: dict
        end
      end

      return dict
    end

    def self.build_tree(models, opts = {})
      analysed = []
      tree = {}
      models.each do |m|
        tree[m] = discover(m, opts[:exclusions], analysed)
      end
      tree
    end

    private
      def self.discover(model, exclusions = [], analysed)
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

      def self.sanitize_args(hash, keys, opts = {})
        unrecognised_keys = hash.keys - keys
        if opts[:raise] && unrecognised_keys.any?
          raise ArgumentError, "Unrecognised keys: #{unrecognised_keys}"
        end
        hash.except!(unrecognised_keys)
      end

      def connect_to(db)
        # establish_connection takes an env name or a hash config so, so do we!
        ActiveRecord::Base.establish_connection(db)
        reload_schema
      end

      def reload_schema
        # Reset column information for all our models
        ActiveRecord::Base.descendants.each do |model|
          model.reset_column_information
        end
      end
  end
end
