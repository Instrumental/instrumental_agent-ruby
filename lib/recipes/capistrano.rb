defined?(Capistrano) && Capistrano::Configuration.instance.load do
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
      revision = current_revision
      agent = Instrumental::Agent.new(instrumental_key,
                                      :collector => collector_host)
      agent.synchronous = true
      agent.notice("#{deployer} deployed #{revision}",
                   @instrumental_deploy_start,
                   deploy_duration_in_seconds)
    end
  end

  before "deploy", "instrumental:util:deploy_start"
  after  "deploy", "instrumental:util:deploy_end"
  after  "instrumental:util:deploy_end", "instrumental:record_deploy_notice"
end
