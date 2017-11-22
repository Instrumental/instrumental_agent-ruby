require "etc"
require "instrumental_agent"

Capistrano::Configuration.instance.load do
  _cset(:instrumental_hooks) { true }
  _cset(:instrumental_key) { nil }
  _cset(:deployer) { Etc.getlogin.chomp }

  if fetch(:instrumental_hooks)
    before "deploy", "instrumental:util:deploy_start"
    after  "deploy", "instrumental:util:deploy_end"
    before "deploy:migrations", "instrumental:util:deploy_start"
    after  "deploy:migrations", "instrumental:util:deploy_end"
    after  "instrumental:util:deploy_end", "instrumental:record_deploy_notice"
  end

  namespace :instrumental do
    namespace :util do
      desc "marker for beginning of deploy"
      task :deploy_start do
        set :instrumental_deploy_start, Time.now
      end

      desc "marker for end of deploy"
      task :deploy_end do
        set :instrumental_deploy_end, Time.now
      end
    end

    desc "send a notice to instrumental about the deploy"
    task :record_deploy_notice do
      start_at                   = fetch(:instrumental_deploy_start, Time.now)
      end_at                     = fetch(:instrumental_deploy_end, start_at)
      deploy_duration_in_seconds = end_at - start_at
      deployer                   = fetch(:deployer)
      agent_options              = { :synchronous => true }
      agent_options[:collector]  = instrumental_host if fetch(:instrumental_host)
      agent                      = Instrumental::Agent.new(fetch(:instrumental_key), agent_options)
      message                    = fetch(:deploy_message, "#{deployer} deployed #{current_revision}")

      agent.notice(message,
                   start_at,
                   deploy_duration_in_seconds)
      logger.info("Notified Instrumental of deployment")
    end
  end
end
