require 'capistrano'
require 'instrumental_agent'

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.load do
    namespace :instrumental do
      namespace :util do
        desc "marker for beginning of deploy"
        task :deploy_start do
          @instrumental_deploy_start = Time.now
        end

        desc "marker for end of deploy"
        task :deploy_end do
          @instrumental_deploy_end = Time.now
        end
      end

      desc "send a notice to instrumental about the deploy"
      task :record_deploy_notice do
        @instrumental_deploy_start ||= Time.now
        @instrumental_deploy_end   ||= Time.now
        deploy_duration_in_seconds = (@instrumental_deploy_end - @instrumental_deploy_start).to_i
        deployer = Etc.getlogin.chomp
        agent_options = {}
        agent_options[:collector] = instrumental_host if exists?(:instrumental_host)
        agent = Instrumental::Agent.new(instrumental_key, agent_options)
        agent.synchronous = true
        agent.notice("#{deployer} deployed #{current_revision}",
                     @instrumental_deploy_start,
                     deploy_duration_in_seconds)
        logger.info("Notified Instrumental of deployment")
      end
    end

    before "deploy", "instrumental:util:deploy_start"
    after  "deploy", "instrumental:util:deploy_end"
    after  "instrumental:util:deploy_end", "instrumental:record_deploy_notice"
  end
end
