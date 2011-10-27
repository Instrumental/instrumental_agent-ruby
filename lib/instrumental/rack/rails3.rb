module Instrumental
  class Middleware
    class Rails3 < Stack
      def self.create
        if defined?(Rails) && Rails.respond_to?(:version) && Rails.version.to_s =~ /^3/
          new
        end
      end

      def install_middleware
        require 'instrumental/rack/rails3/middleware_bootstrap'
      end

      def log(msg)
        Rails.logger.error msg
      end

      def recognize_uri(request)
        Rails.application.routes.finalize!
        params = Rails.application.routes.recognize_path(request.url, request.env)
        ["controller", params[:controller], params[:action]]
      rescue ActionController::RoutingError => e
        ["controller", "unknown"]
      end
    end
  end
end
