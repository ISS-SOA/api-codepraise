# frozen_string_literal: true

module CodePraise
  module Response
    # Request to clone a project (legacy - for backwards compatibility)
    CloneRequest = Struct.new :project, :id

    # Request to appraise a project folder
    # Includes full project info so worker doesn't need database access
    AppraisalRequest = Struct.new :project, :folder_path, :id
  end
end
