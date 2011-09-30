#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.
#

class RedisCache

  SUPPORTED_CACHES = [:created_at] #['updated_at', 
  CACHE_LIMIT = 100

  def initialize(user, order_field)
    @user = user
    @order_field = order_field.to_s
    self
  end

  # @return [Boolean]
  def cache_exists?
    self.size != 0
  end

  # @return [Integer] the cardinality of the redis set
  def size
    redis.zcard(set_key)
  end

  def post_ids(time=Time.now, limit=15)
    post_ids = redis.zrevrangebyscore(set_key, time.to_i, "-inf")
    post_ids[0...limit]
  end

  # @return [RedisCache] self
  def ensure_populated!
    self.repopulate! unless cache_exists?
    self
  end

  # @return [RedisCache] self
  def repopulate!
    self.populate! && self.trim!
    self
  end

  # @return [RedisCache] self
  def populate!
    # user executes query and gets back hashes
    sql = @user.visible_posts_sql(:limit => CACHE_LIMIT, :order => self.order)
    hashes = Post.connection.select_all(sql)

    # hashes are inserted into set in a single transaction
    redis.multi do
      hashes.each do |h|
        self.redis.zadd(set_key, h[@order_field], h["id"])
      end
    end

    self
  end

  # @return [RedisCache] self
  def trim!
    puts "cache limit #{CACHE_LIMIT}"
    puts "cache size #{self.size}"
    self.redis.zremrangebyrank(set_key, 0, -(CACHE_LIMIT+1))
    self
  end

  # @param order [Symbol, String]
  # @return [Boolean]
  def self.supported_order?(order)
    SUPPORTED_CACHES.include?(order.to_sym)
  end

  def order
    "#{@order_field} DESC"
  end

  protected
  # @return [Redis]
  def redis
    @redis ||= Redis.new
  end

  # @return [String]
  def set_key
    @set_key ||= "cache_stream_#{@user.id}_#{@order_field}"
  end
end
