path = require 'path'
fse = require 'fs-extra'
redis = require 'redis'
slugify = require 'slugify'
async = require 'async'

module.exports = class Migrate
  constructor: (@opts = {}) ->
    @opts.path ?= 'migrations'
    @opts.ext ?= 'coffee'
    @opts.template ?= """
      module.exports =
        requiresDowntime: FIXME # true or false

        up: (done) ->
          done()

        down: (done) ->
          throw new Error('irreversible migration')

        test: (done) ->
          # copy live/dev db to test db

          # ... test before ...

          # @up()

          # ... test after ...

          #  done()
    """

    # url (as redis://host:port)
    @opts.redis = @opts.redis() if typeof @opts.redis is 'function'
    # password (optional)
    @opts.redisAuth = @opts.redisAuth() if typeof @opts.redisAuth is 'function'

    {port, hostname} = require('url').parse @opts.redis ? ''
    @redisClient = redis.createClient port, hostname, {auth_pass: @opts.redisAuth}

  log: (message) ->
    console.log message

  get: (name) ->
    name = name.replace new RegExp("\.#{@opts.ext}$"), ''
    migration = require path.resolve("#{@opts.path}/#{name}")
    migration.name = name
    migration

  # store previously-run migration names in a set.
  # TODO make config'able?
  setKey: ->
    'migrations'

  # Check a migration has been run
  exists: (name, callback) ->
    @redisClient.sismember @setKey(), name, (err, val) ->
      callback err, (val is 1)

  test: (name, callback) ->
    @log "Testing migration `#{name}`"
    @get(name).test(callback)

  # Run one migration by name
  one: (name, callback) ->
    @all [name], callback

  # Run all provided migrations or all pending if not provided
  # TODO this and `one` should be inverted!
  all: (args...) ->
    callback = args.pop()
    migrations = args.pop()   # optional

    async.waterfall [
      (next) =>
        if migrations then next null, migrations
        else @pending next
      (migrations, next) =>
        async.eachSeries migrations, (name, nextMigration) =>
          async.waterfall [
            (nextMigrationStep) =>
              @exists name, nextMigrationStep

            (exists, nextMigrationStep) =>
              if exists then nextMigrationStep new Error "Migration `#{name}` has already been run"
              else nextMigrationStep null, @get(name)

            (migration, nextMigrationStep) =>
              @log "Running migration `#{migration.name}`"
              migration.up (err) -> nextMigrationStep err, migration

            (migration, nextMigrationStep) =>
              @redisClient.sadd @setKey(), migration.name, nextMigrationStep

          ], nextMigration
        , next
    ], callback


  down: (callback) ->
    async.waterfall [
      (next) =>
        @redisClient.smembers @setKey(), next
      (migrationsAlreadyRun, next) =>
        if migrationsAlreadyRun?.length
          lastMigrationName = migrationsAlreadyRun.sort()[migrationsAlreadyRun.length - 1]
        if not lastMigrationName
          return next(new Error("No migrations found!"))
        migration = @get(lastMigrationName)
        @log "Reversing migration `#{migration.name}`"
        migration.down (err) =>
          return next(err) if err
          return next(null, lastMigrationName)

      (lastMigrationName, next) =>
        @redisClient.srem @setKey(), lastMigrationName, next

    ], callback

  # Return a list of pending migrations
  pending: (callback) ->
    async.waterfall [
      (next) =>
        fse.readdir @opts.path, (err, filenames) =>
          next err, filenames?.sort()

      (filenames, next) =>
        @redisClient.smembers @setKey(), (err, members) -> next err, filenames, members

      (filenames, migrationsAlreadyRun, next) =>
        names = filenames.map (filename) =>
          return unless (match = filename.match new RegExp "^([^_].+)\.#{@opts.ext}$")
          match[1]
        .filter (name) ->
          !!name
        .filter (name) ->
          name not in migrationsAlreadyRun

        next null, names
    ], (err, names) -> callback err, names


  # Generate a stub migration file
  generate: (name, done) ->
    name = "#{slugify name, '_'}"
    timestamp = (new Date()).toISOString().replace /\D/g, ''
    filename = "#{@opts.path}/#{timestamp}_#{name}.#{@opts.ext}"
    async.series [
      ((innerDone) => fse.mkdirp @opts.path, innerDone)
      ((innerDone) => fse.writeFile filename, @opts.template, innerDone)
    ], (err) =>
      return done(err) if err
      done(null, filename)
