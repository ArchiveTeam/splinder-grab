require 'connection_pool'
require 'girl_friday'
require 'mechanize'
require 'nokogiri'
require 'redis'

BASE_URL = "http://www.splinder.com/users/list"
CATEGORIES = ['a'..'z', '0'..'9', ['_']].map(&:to_a).inject(&:+)
CONCURRENCY_LEVEL = 6

# ---

def goes_to_next_page?(link)
  link.inner_html =~ /successiva/
end

redis_connections = ConnectionPool.new(:size => CONCURRENCY_LEVEL) { Redis.new }

page_workers = GirlFriday::WorkQueue.new(:page_workers, :size => CONCURRENCY_LEVEL) do |agent, page|
  puts "Working on #{page.uri}..."

  redis_connections.with_connection do |redis|
    doc = Nokogiri.HTML(page.body)

    puts "Parsing #{page.uri} for user links..."
    (doc/'.main_content .user-data a').map { |link| link.attribute('href').value }.each do |href|
      if href =~ %r{/profile/(.+)}
        redis.sadd('users', $1)
      end
    end

    puts "Looking for 'next page' link..."

    next_links = (doc/'#pager a')
    go_to_next_page = next_links.detect { |l| goes_to_next_page?(l) }

    if go_to_next_page
      next_page = agent.click(go_to_next_page)

      puts "Queuing up #{next_page.uri}..."
      page_workers << [agent, next_page]
    end

    count = redis.scard('users')
    redis.sadd('done', page.uri)

    puts "Done with #{page.uri}.  Total username count: #{count}."
  end
end

CATEGORIES.each do |category|
  agent = Mechanize.new
  agent.user_agent_alias = 'Linux Firefox'
  initial_page = agent.get("#{BASE_URL}/#{category}")

  page_workers << [agent, initial_page]
end

loop do
  sleep 30
end
