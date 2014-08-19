require "app_dup/duper"

module AppDup
  module Interface
    # TODO: bring in AR-import for performance!
    include Duper

    attr_accessor :from, :to, :options, :data, :results, :models

    DEFAULT_OPTIONS = { create_db: false }

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
      @data = dup
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