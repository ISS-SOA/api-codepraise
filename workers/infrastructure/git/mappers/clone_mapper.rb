# frozen_string_literal: true

module CodePraise
  # Maps git clone output lines to progress symbols
  # Used by Service::AppraiseProject to report fine-grained clone progress
  module CloneMapper
    CLONE_PATTERNS = {
      /^Cloning/i   => :cloning_started,
      /^remote:/i   => :cloning_remote,
      /^Receiving/i => :cloning_receiving,
      /^Resolving/i => :cloning_resolving,
      /^Checking/i  => :cloning_done
    }.freeze

    # Map a git clone output line to a progress symbol
    # Returns nil if line doesn't match any known pattern
    def self.map(line)
      CLONE_PATTERNS.each do |pattern, symbol|
        return symbol if line.match?(pattern)
      end
      nil
    end

    # Map a git clone output line, returning a default symbol if no match
    def self.map_or_default(line, default = :cloning_started)
      map(line) || default
    end
  end
end
