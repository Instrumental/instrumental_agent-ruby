begin
  require 'net/https'
  INSTRUMENTAL_SSL_AVAILABLE = true
rescue LoadError
  INSTRUMENTAL_SSL_AVAILABLE = false
end