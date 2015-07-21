async = require 'async'
redis = require 'redis'

KEY = 'test_migration_1'

module.exports =
  up: (cb) ->
    redisClient = null

    async.series [
      (next) ->
        redisClient = redis.createClient()
        redisClient.on 'ready', next
      (next) ->
        redisClient.set KEY, Math.random(), next
    ], cb

  down: (cb) ->
    async.series [
      (next) ->
        redisClient = redis.createClient()
        redisClient.on 'ready', next
      (next) ->
        redisClient.del KEY, next
    ], cb

