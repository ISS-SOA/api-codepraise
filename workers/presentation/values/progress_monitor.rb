# frozen_string_literal: true

module GitClone
  # Infrastructure to clone while yielding progress
  # Legacy module for backwards compatibility
  module CloneMonitor
    CLONE_PROGRESS = {
      'STARTED'   => 15,
      'Cloning'   => 30,
      'remote'    => 70,
      'Receiving' => 85,
      'Resolving' => 95,
      'Checking'  => 100,
      'FINISHED'  => 100
    }.freeze

    def self.starting_percent
      CLONE_PROGRESS['STARTED'].to_s
    end

    def self.finished_percent
      CLONE_PROGRESS['FINISHED'].to_s
    end

    def self.progress(line)
      CLONE_PROGRESS[first_word_of(line)].to_s
    end

    def self.percent(stage)
      CLONE_PROGRESS[stage].to_s
    end

    def self.first_word_of(line)
      line.match(/^[A-Za-z]+/).to_s
    end
  end

  # Progress phases for full appraisal flow (clone + appraise + cache)
  # Progress distribution:
  #   Clone: 0-50% (or skip if already cloned)
  #   Appraise: 50-90%
  #   Cache: 90-100%
  module AppraisalMonitor
    PHASES = {
      started: 15,
      cloning: 25,
      clone_receiving: 40,
      clone_resolving: 45,
      clone_done: 50,
      appraising: 55,
      appraise_done: 85,
      caching: 90,
      finished: 100
    }.freeze

    def self.starting_percent
      PHASES[:started].to_s
    end

    def self.finished_percent
      PHASES[:finished].to_s
    end
  end
end
