require "etc"

namespace :instrumental do
  desc "marker for beginning of deploy"
  task :deploy_start do
    @instrumental_deploy_start = Time.now
  end

  desc "marker for end of deploy"
  task :deploy_end do
    @instrumental_deploy_end = Time.now
  end

  desc "send a notice to instrumental about the deploy"
  task :notice_deploy do
    @instrumental_deploy_start ||= Time.now
    @instrumental_deploy_end   ||= Time.now
    deploy_duration_in_seconds = (@instrumental_deploy_end - @instrumental_deploy_start).to_i
    deployer = Etc.getlogin.chomp
    revision = deployed_revision
    agent = Instrumental::Agent.new(instrumental_key,
                                    :collector => collector_host)
    agent.synchronous = true
    agent.notice("#{deployer} deployed #{revision}",
                 @instrumental_deploy_start,
                 deploy_duration_in_seconds)
  end
end

before "deploy", "instrumental:deploy_start"
after "deploy",  "instrumental:deploy_end"
after "instrumental:deploy_end", "instrumental:notice_deploy"
