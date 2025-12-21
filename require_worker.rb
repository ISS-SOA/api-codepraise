# frozen_string_literal: true

# Requires all ruby files in specified worker folders
# Worker has its own domain (contributions) and services separate from the API
# Params:
# - (opt) folders: Array of folder names within workers/, or String of single folder name
# Usage:
#  require_worker
#  require_worker(%w[domain])
#  require_worker('services')
def require_worker(folders = %w[domain services])
  worker_list = Array(folders).map { |folder| "workers/#{folder}" }

  Dir.glob("./{#{worker_list.join(',')}}/**/*.rb").each do |file|
    require file
  end
end
