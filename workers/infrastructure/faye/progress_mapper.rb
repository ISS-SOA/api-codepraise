# frozen_string_literal: true

module Appraiser
  # Maps progress symbols to percentages and publishes via FayeServer
  # Single source of truth for all progress phase percentages
  class ProgressMapper
    PHASES = {
      started:             15,
      cloning_started:     20,
      cloning_remote:      35,
      cloning_receiving:   40,
      cloning_resolving:   45,
      cloning_done:        50,
      appraising_started:  55,
      appraising_done:     85,
      caching_started:     90,
      finished:           100
    }.freeze

    def initialize(faye_server)
      @faye_server = faye_server
    end

    # Map a progress symbol to its percentage
    def map(symbol)
      PHASES.fetch(symbol) do
        raise ArgumentError, "Unknown progress phase: #{symbol}"
      end
    end

    # Report progress by mapping symbol to percentage and publishing
    def report(symbol)
      percentage = map(symbol)
      @faye_server.publish(percentage.to_s)
    end

    # Report the same symbol repeatedly for a number of seconds
    def report_each_second(seconds, symbol)
      seconds.times do
        sleep(1)
        report(symbol)
      end
    end

    # Returns a proc that can be passed to services for progress reporting
    def progress_callback
      ->(symbol) { report(symbol) }
    end
  end
end
