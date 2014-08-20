require "app_dup/duper"

module AppDup
  module Interface
    # TODO: bring in AR-import for performance!
    attr_accessor :from, :to, :options, :data, :results, :models

    DEFAULT_OPTIONS = { create_db: false }

    def self.included(base)
      base.extend(Duper)
    end

    def initialize(options)
      if (options.keys & [:from, :to]).size != 2
        raise "must provide `from` and `to` options for initialization"
      end

      @from = options.delete(:from)
      @to = options.delete(:to)

      @options = options.reverse_merge!(DEFAULT_OPTIONS)
    end

    def run!
      puts "STARTING"
      connect_to(@from)
      puts "CONNECTED TO FROM, DUPING"
      @data = Duper.dup(options[:dup] || {})
      puts "DUPED"
      create_db(@to) if options[:create_db]
      connect_to(@to)
      puts "CONNECTED TO TO"
      transform
      puts "TRANSFORMED"
      before_dump
      puts "STARTING DUMP"
      sleep(20)
      ActiveRecord::Base.transaction do
        # DUUUUUMPPPP.
        @results = @data.map do |model_name, h|
          len = h.values.size
          [model_name, h.values.with_index.map do |d,i|
            puts "saving #{model_name} #{i} of #{len}"
            d.save
          end]
        end
        # do something if errors? :/
      end
      puts "FINISHED DUMP"
      after_dump
      return @results.inject({}){|h,(m,r)| h[m] = r.size}
    ensure
      connect_to(ENV['RAILS_ENV'])
    end

    def transform
      puts "`transform` not implemented"
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