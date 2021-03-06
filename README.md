# Instrumental Ruby Agent

Instrumental is a [application monitoring platform](https://instrumentalapp.com) built for developers who want a better understanding of their production software. Powerful tools, like the [Instrumental Query Language](https://instrumentalapp.com/docs/query-language), combined with an exploration-focused interface allow you to get real answers to complex questions, in real-time.

This agent supports custom metric monitoring for Ruby applications. It provides high-data reliability at high scale, without ever blocking your process or causing an exception.

## Setup & Usage

Add the gem to your Gemfile.

```sh
gem 'instrumental_agent'
```

Visit [instrumentalapp.com](https://instrumentalapp.com) and create an account, then initialize the agent with your [project API token](https://instrumentalapp.com/docs/tokens).

```ruby
I = Instrumental::Agent.new('PROJECT_API_TOKEN', :enabled => Rails.env.production?)
```

You'll probably want something like the above, only enabling the agent in production mode so you don't have development and production data writing to the same value. Or you can setup two projects, so that you can verify stats in one, and release them to production in another.

Now you can begin to use Instrumental to track your application.

```ruby
I.gauge('load', 1.23)                # value at a point in time

I.increment('signups')               # increasing value, think "events"

I.time('query_time') do              # time a block of code
  post = Post.find(1)
end
I.time_ms('query_time_in_ms') do     # prefer milliseconds?
  post = Post.find(1)
end
```

**Note**: For your app's safety, the agent is meant to isolate your app from any problems our service might suffer. If it is unable to connect to the service, it will discard data after reaching a low memory threshold.

Want to track an event (like an application deploy, or downtime)? You can capture events that are instantaneous, or events that happen over a period of time.

```ruby
I.notice('Jeffy deployed rev ef3d6a') # instantaneous event
I.notice('Testing socket buffer increase', 3.days.ago, 20.minutes) # an event with a duration
```

## Backfilling

Streaming data is better with a little historical context. Instrumental lets you backfill data, allowing you to see deep into your project's past.

When backfilling, you may send tens of thousands of metrics per second, and the command buffer may start discarding data it isn't able to send fast enough. We provide a synchronous mode that will ensure every stat makes it to Instrumental before continuing on to the next.

**Warning**: You should only enable synchronous mode for backfilling data as any issues with the Instrumental service issues will cause this code to halt until it can reconnect.

```ruby
I.synchronous = true # every command sends immediately
User.find_each do |user|
  I.increment('signups', 1, user.created_at)
end
```

## Aggregation
Aggregation collects more data on your system before sending it to Instrumental. This reduces the total amount of data being sent, at the cost of a small amount of additional latency. You can control this feature with the frequency parameter:

```ruby
I = Instrumental::Agent.new('PROJECT_API_TOKEN', :frequency => 15) # send data every 15 seconds
I.frequency = 6 # send batches of data every 6 seconds
```

The agent may send data more frequently if you are sending a large number of different metrics. Values between 3 and 15 are generally reasonable. If you want to disable this behavior and send every metric as fast as possible, set frequency to zero or nil. Note that a frequency of zero will still use a seperate thread for performance - it is NOT the same as synchronous mode.


## Server Metrics

Want server stats like load, memory, etc.? Check out [InstrumentalD](https://github.com/instrumental/instrumentald).

## Agent Control

Need to quickly disable the agent? set :enabled to false on initialization and you don't need to change any application code.


## Capistrano Integration

Add `require "instrumental/capistrano"` to your capistrano configuration and your deploys will be tracked by Instrumental. Add the API token for the project you want to track to by setting the following Capistrano var:

```ruby
set :instrumental_key, "MY_API_KEY"
```

The following configuration will be added:

```ruby
before "deploy", "instrumental:util:deploy_start"
after  "deploy", "instrumental:util:deploy_end"
before "deploy:migrations", "instrumental:util:deploy_start"
after  "deploy:migrations", "instrumental:util:deploy_end"
after  "instrumental:util:deploy_end", "instrumental:record_deploy_notice"
```

The default message sent is "USER deployed COMMIT_HASH". If you need to customize it, set a capistrano variable named `deploy_message` to the value you'd prefer.

## Tracking metrics in Resque jobs (and Resque-like scenarios)

If you plan on tracking metrics in Resque jobs, you will need to explicitly cleanup after the agent when the jobs are finished. You can accomplish this by adding `after_perform` and `on_failure` hooks to your Resque jobs. See the Resque [hooks documentation](https://github.com/resque/resque/blob/master/docs/HOOKS.md) for more information.

You're required to do this because Resque calls `exit!` when a worker has finished processing, which bypasses Ruby's `at_exit` hooks. The Instrumental Agent installs an `at_exit` hook to flush any pending metrics to the servers, but this hook is bypassed by the `exit!` call; any other code you rely that uses `exit!` should call `I.cleanup` to ensure any pending metrics are correctly sent to the server before exiting the process.

## Automated Metric Collection

v2.x+ of the Instrumental Agent introduced automated metric collection for your application by way of the [Metrician gem](https://github.com/Instrumental/metrician-ruby). You can read more about the metrics it collects in the [Instrumental documentation](https://instrumentalapp.com/docs/metrician/installation).

### Upgrading from 1.x

If you are upgrading from the pre-2.x version of instrumental and **do not** want automated metric collection, you can disable it by setting the following in your agent setup:

```
I = Instrumental::Agent.new('PROJECT_API_TOKEN',
  :enabled => Rails.env.production?,
  :metrician => false
)
```

### Upgrading from 2.x

Agent version 3.x drops support for some older rubies, but should otherwise be a drop-in replacement. If you wish to enable Aggregation, enable the agent with the frequency option set to the number of seconds you would like to wait between flushes. For example:

```
I = Instrumental::Agent.new('PROJECT_API_TOKEN',
  :enabled => Rails.env.production?,
  :frequency => 15
)
```

## Troubleshooting & Help

We are here to help. Email us at [support@instrumentalapp.com](mailto:support@instrumentalapp.com).


## Release Process

1. Pull latest master
2. Merge feature branch(es) into master
3. `script/test`
4. Increment version in:
  - `lib/instrumental/version.rb`
5. Update [CHANGELOG.md](CHANGELOG.md)
6. Commit "Release vX.Y.Z"
7. Push to GitHub
8. Release packages: `rake release`
9. Update documentation on instrumentalapp.com


## Version Policy

This library follows [Semantic Versioning 2.0.0](http://semver.org).
