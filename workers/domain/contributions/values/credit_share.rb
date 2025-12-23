# frozen_string_literal: true

module CodePraise
  module Value
    # Value of credits shared by contributors for file, files, or folder
    class CreditShare
      # rubocop:disable Style/RedundantSelf
      attr_accessor :share
      attr_reader :contributors

      def initialize
        @share = Types::AutoZeroHash.new
        @contributors = Set.new
      end

      ### following methods allow two CreditShare objects to test equality
      def sorted_credit
        @share.to_a.sort_by { |a| a[0] }
      end

      def sorted_contributors
        @contributors.to_a.sort_by(&:username)
      end

      def state
        [sorted_credit, sorted_contributors]
      end

      def ==(other)
        other.class == self.class && other.state == self.state
      end

      alias eql? ==

      def hash
        state.hash
      end

      def total_credits
        @share.values.sum
      end

      def add_credit(contributor, count)
        to_add = find_contributor(contributor)
        @share[to_add.username] += count
        @contributors.add(to_add)
        self
      end

      def +(other)
        unique_contributors = Value::Contributors
          .new(contributors + other.contributors)
          .group_by_identity

        shares = self.share.merge(other.share) do |_k, v1, v2|
          v1 + v2
        end

        unique_contributors.each_with_object(Value::CreditShare.new) do |group, final|
          group_names = group.map(&:username).uniq
          group_total = group_names.sum { |name| shares[name] }
          final.add_credit(group.first, group_total)
        end
      end

      def by_email(email)
        contributor = @contributors.find { |c, _| c.email == email }
        by_contributor(contributor)
      end

      def by_contributor(contributor)
        @share[find_contributor(contributor).username]
      end

      private

      def find_contributor(contributor)
        @contributors.find { _1 == contributor } || contributor
        # get_or_new_contributor(contributor)
      end

      # TODO: remove or work into refactoring con contributor sets
      def get_or_new_contributor(contributor)
        if (existing = @contributors.find { _1 == contributor })
          existing.username >= contributor.username ? existing : contributor
        else
          contributor
        end
      end
      # rubocop:enable Style/RedundantSelf
    end
  end
end
