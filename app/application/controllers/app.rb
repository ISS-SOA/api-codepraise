# frozen_string_literal: true

require 'rack' # for Rack::MethodOverride
require 'roda'

module CodePraise
  # Web App
  class App < Roda
    plugin :halt
    plugin :caching
    # plugin :all_verbs # allows DELETE and other HTTP verbs beyond GET/POST

    # use Rack::MethodOverride # for other HTTP verbs (with plugin all_verbs)

    route do |routing|
      response['Content-Type'] = 'application/json'

      # GET /
      routing.root do
        message = "CodePraise API v1 at /api/v1/ in #{App.environment} mode"

        result_response = Representer::HttpResponse.new(
          Response::ApiResult.new(status: :ok, message:)
        )

        response.status = result_response.http_status_code
        result_response.to_json
      end

      routing.on 'api/v1' do
        routing.on 'projects' do
          routing.on String, String do |owner_name, project_name|
            # GET /projects/{owner_name}/{project_name}[/folder_namepath/]
            routing.get do
              # Appraisal results cached in Redis by worker (1-day TTL)
              request_id = [request.env, request.path, Time.now.to_f].hash

              path_request = Request::Appraisal.new(
                owner_name, project_name, request
              )

              result = Service::FetchOrRequestAppraisal.new.call(
                requested: path_request,
                request_id:,
                config: App.config
              )

              if result.failure?
                # Failure includes appraisal request being processed by worker
                failed = Representer::HttpResponse.new(result.failure)
                routing.halt failed.http_status_code, failed.to_json
              end

              # Cache hit - return pre-serialized JSON directly
              appraisal_result = result.value!
              response.status = appraisal_result[:cache_hit] ? 200 : 500

              appraisal_result[:cached_json]
            end

            # POST /projects/{owner_name}/{project_name}
            routing.post do
              result = Service::AddProject.new.call(
                owner_name:, project_name:
              )

              if result.failure?
                failed = Representer::HttpResponse.new(result.failure)
                routing.halt failed.http_status_code, failed.to_json
              end

              http_response = Representer::HttpResponse.new(result.value!)
              response.status = http_response.http_status_code
              Representer::Project.new(result.value!.message).to_json
            end
          end

          routing.is do
            # GET /projects?list={base64_json_array_of_project_fullnames}
            routing.get do
              list_req = Request::EncodedProjectList.new(routing.params)
              result = Service::ListProjects.new.call(list_request: list_req)

              if result.failure?
                failed = Representer::HttpResponse.new(result.failure)
                routing.halt failed.http_status_code, failed.to_json
              end

              http_response = Representer::HttpResponse.new(result.value!)
              response.status = http_response.http_status_code
              Representer::ProjectsList.new(result.value!.message).to_json
            end
          end
        end
      end
    end
  end
end
