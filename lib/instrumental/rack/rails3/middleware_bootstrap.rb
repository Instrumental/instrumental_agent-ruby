module Instrumental
  class MiddlewareBootstrap < Rails::Railtie
    config.app_middleware.use Instrumental::Middleware

  end
end