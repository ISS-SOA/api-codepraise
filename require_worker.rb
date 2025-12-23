# frozen_string_literal: true

# Requires all ruby files in specified worker folders
# Worker has its own DDD layers parallel to the API:
#   - domain: contributions entities/values/lib
#   - infrastructure: git gateway/repositories/mappers, messaging
#   - presentation: progress monitor values
#   - application: controllers, services, requests
# Params:
# - (opt) folders: Array of folder names within workers/, or String of single folder name
# Usage:
#  require_worker
#  require_worker(%w[domain infrastructure])
#  require_worker('application')
def require_worker(folders = %w[domain infrastructure presentation application])
  worker_list = Array(folders).map { |folder| "workers/#{folder}" }

  Dir.glob("./{#{worker_list.join(',')}}/**/*.rb").each do |file|
    require file
  end
end
