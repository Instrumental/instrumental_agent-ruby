module Instrumental
  class Middleware
    class Rails23 < Stack
      def self.create
        if (defined?(::RAILS_VERSION) && const_get(:RAILS_VERSION).to_s =~ /^2\.3/) ||
            (defined?(Rails) && Rails.respond_to?(:version) && Rails.version.to_s =~ /^2\.3/)
          new
        end
      end

      def install_middleware
        Rails.configuration.middleware.use Instrumental::Middleware
      end

      def log(msg)
        Rails.logger.error msg
      end

      def recognize_uri(request)
        params = ActionController::Routing::Routes.recognize_path(request.path, request.env.merge(:method => request.env["REQUEST_METHOD"].downcase.to_sym))
        ["controller", params[:controller], params[:action]]
      rescue ActionController::RoutingError => e
        ["controller", "unknown"]
      end
    end
  end
end