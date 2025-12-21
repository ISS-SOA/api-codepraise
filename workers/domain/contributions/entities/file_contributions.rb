# frozen_string_literal: true

require_relative '../lib/contributions_calculator'
require_relative '../values/code_language'

module CodePraise
  module Entity
    # Entity for file contributions
    class FileContributions
      include Mixins::ContributionsCalculator

      attr_reader :file_path, :lines

      def initialize(file_path:, lines:)
        @file_path = Value::FilePath.new(file_path)
        @lines = lines
      end

      def language
        file_path.language
      end

      def total_credits
        credit_share.total_credits
      end

      def credit_share
        return Value::CreditShare.new if unwanted?

        @credit_share ||=
          lines.each_with_object(Value::CreditShare.new) do |line, credit|
            credit.add_credit(line.contributor, line.credit)
          end
      end

      def contributors
        credit_share.contributors
      end

      private

      def unwanted? = language.unwanted?
      def wanted? = language.wanted?
    end
  end
end
