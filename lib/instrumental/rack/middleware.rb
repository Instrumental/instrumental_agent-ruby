module Instrumental
  class Middleware
    def self.boot
      Instrumental::Agent.logger.warn "The Instrumental Rails middlware has been removed - contact support@instrumentalapp.com for more information"
    end
  end
end
