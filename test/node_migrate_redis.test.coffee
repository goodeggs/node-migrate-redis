{expect} = chai = require 'chai'
fse = require 'fs-extra'
sinon = require 'sinon'
chai.use require 'sinon-chai'
redis = require 'redis'
Migrate = require '../'

describe 'node-migrate-redis', ->
  migrate = null

  before 'setup', (done) ->
    sinon.stub Migrate::, '_setKey', -> 'test_migrations'

    @redisClient = redis.createClient()
    @redisClient.on 'ready', -> done()

  after ->
    Migrate::_setKey.restore()

  beforeEach 'wipe set', (done) ->
    @redisClient.del 'test_migrations', (err) -> done err

  before 'instantiate', ->
    opts =
      path: __dirname
    migrate = new Migrate opts

  before 'stub log', ->
    sinon.stub migrate, 'log'

  after ->
    migrate.log.restore()

  describe '.get', ->
    migration = null

    beforeEach ->
      migration = migrate.get 'migration'

    it 'loads ok', ->
      expect(migration).to.be.ok

    it 'has name', ->
      expect(migration.name).to.equal 'migration'

  describe '.exists', ->
    beforeEach 'add migration to history', (done) ->
      @redisClient.sadd 'test_migrations', 'test1', (err) -> done err

    afterEach 'cleanup', (done) ->
      @redisClient.srem 'test_migrations', 'test1', (err) -> done err

    it 'returns true for existing migration', (done) ->
      migrate.exists 'test1', (err, exists) ->
        expect(exists).to.eql true
        done err

    it 'returns false for existing migration', (done) ->
      migrate.exists 'test2', (err, exists) ->
        expect(exists).to.eql false
        done err

  describe '.test', ->
    migration = null

    beforeEach 'run test', (done) ->
      migration =
        name: 'migration'
        test: sinon.stub().yields()
      sinon.stub(migrate, 'get').returns migration
      migrate.test 'migration', done

    afterEach ->
      migrate.get.restore()

    it 'executes migration test', ->
      expect(migration.test).to.have.been.calledOnce

  describe '.one', ->
    migration = null

    beforeEach 'run one', (done) ->
      migration =
        name: 'test_pending_migration'
        up: sinon.stub().yields()
      sinon.stub(migrate, 'get').returns migration
      migrate.one 'test_pending_migration', done

    afterEach ->
      migrate.get.restore()

    it 'calls up on migration', ->
      expect(migration.up).to.have.been.calledOnce

    it 'saves new migration', (done) ->
      @redisClient.sismember 'test_migrations', 'test_pending_migration', (err, exists) ->
        expect(exists).to.equal 1
        done err

  describe '.all', ->
    migration = null

    describe 'migrating all pending', ->
      beforeEach 'run all', (done) ->
        migration =
          name: 'test_pending_migration'
          up: sinon.stub().yields()

        sinon.stub(migrate, 'pending').yields null, ['test_pending_migration']
        sinon.stub(migrate, 'get').returns migration

        migrate.all done

      afterEach ->
        migrate.pending.restore()
        migrate.get.restore()

      it 'calls up on migration', ->
        expect(migration.up).to.have.been.calledOnce

      it 'saves new migration', (done) ->
        @redisClient.sismember 'test_migrations', 'test_pending_migration', (err, exists) ->
          expect(exists).to.equal 1
          done err

    describe 'migrating existing migration', ->
      beforeEach 'run all', (done) ->
        migration =
          name: 'existing_migration'
          up: sinon.stub().yields()
        sinon.stub(migrate, 'pending').yields null, ['existing_migration']
        sinon.stub(migrate, 'exists').yields null, true
        sinon.stub(migrate, 'get').returns migration
        migrate.all (@err) => done()

      afterEach ->
        migrate.pending.restore()
        migrate.get.restore()
        migrate.exists.restore()

      it 'does not call up on migration', ->
        expect(migration.up).to.not.have.been.calledOnce

      it 'does not save new migration', (done) ->
        @redisClient.sismember 'test_migrations', 'test_pending_migration', (err, exists) ->
          expect(exists).to.equal 0
          done err

      it 'returns error', ->
        expect(@err).to.be.an.instanceOf Error
        expect(@err.message).to.match /already been run/


  describe '.down', ->
    {migration, version} = {}

    beforeEach 'add migration to history', (done) ->
      @redisClient.sadd 'test_migrations', 'test_migration', (err) -> done err

    beforeEach 'migrate down', (done) ->
      migration =
        name: 'test_migration'
        down: sinon.stub().yields()
      sinon.stub(migrate, 'get').returns migration

      version =
        name: 'test_migration'
        remove: sinon.stub().yields()

      migrate.down done

    afterEach ->
      migrate.get.restore()

    it 'calls down on the migration', ->
      expect(migration.down).to.have.been.calledOnce

    it 'removes version', (done) ->
      @redisClient.sismember 'test_migrations', 'test_migration', (err, exists) ->
        expect(exists).to.equal 0
        done err

  describe '.pending', ->
    scenarioForFileExtension = (ext) ->
      beforeEach 'add migration to history', (done) ->
        @redisClient.sadd 'test_migrations', 'migration1', (err) -> done err

      beforeEach 'read migration files', (done) ->
        migrate2 = new Migrate {path: __dirname, ext: ext}
        sinon.stub(fse, 'readdir').yields null, ["migration3.#{ext}", "migration2.#{ext}", "migration1.#{ext}"]
        migrate2.pending (err, @pending) => done()

      afterEach ->
        fse.readdir.restore()

      it 'returns pending migrations', ->
        expect(@pending).to.eql ['migration2', 'migration3']

    describe 'coffee-script', ->
      scenarioForFileExtension 'coffee'

    describe 'javascript', ->
      scenarioForFileExtension 'js'

  describe '.generate', ->
    beforeEach (done) ->
      sinon.stub(fse, 'mkdirp').yields()
      sinon.stub(fse, 'writeFile').yields()
      migrate.generate 'filename', done

    afterEach ->
      fse.mkdirp.restore()
      fse.writeFile.restore()

    it 'generates migration file', ->
      expect(fse.writeFile).to.have.been.calledWithMatch /^.*_filename/, /.+/

