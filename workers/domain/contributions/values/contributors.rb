module CodePraise
  module Value
    # Collection of Contributor objects
    class Contributors
      attr_reader :contributors

      def initialize(contributors)
        @contributors = contributors
      end

      # Group contributors by common identity attributes: username and email
      # note: unavoidably complex method
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength, Metrics/AbcSize
      def group_by_identity
        # Create a mapping of username and email to their groups
        groups = []
        id_map = {}

        contributors.each do |contributor|
          # Find existing group for username or email
          username_group = id_map[contributor[:username]]
          email_group = id_map[contributor[:email]]

          if username_group && email_group
            # Merge two groups if they are separate
            if username_group != email_group
              merged_group = username_group + email_group
              groups.delete(username_group)
              groups.delete(email_group)
              groups << merged_group
              merged_group.each { |p| id_map[p[:username]] = id_map[p[:email]] = merged_group }
            end
          elsif username_group || email_group
            # Add to the existing group
            group = username_group || email_group
            group << contributor
            id_map[contributor[:username]] = id_map[contributor[:email]] = group
          else
            # Create a new group
            new_group = [contributor]
            groups << new_group
            id_map[contributor[:username]] = id_map[contributor[:email]] = new_group
          end
        end

        groups
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength, Metrics/AbcSize
    end
  end
end
