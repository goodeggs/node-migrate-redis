{expect} = chai = require 'chai'
fibrous = require 'fibrous'
fse = require 'fs-extra'
sinon = require 'sinon'
chai.use require 'sinon-chai'
Migrate = require '../'

class StubMigrationVersion
  @find: ->
  @findOne: ->
  @create: ->

describe 'node-migrate-mongo', ->
  migrate = null

  before ->
    opts = path: __dirname
    migrate = new Migrate opts, StubMigrationVersion
    sinon.stub(migrate, 'log')

  after ->
    migrate.log.restore()

  describe '.get', ->
    migration = null

    before ->
      migration = migrate.get 'migration'

    it 'loads ok', ->
      expect(migration).to.be.ok

    it 'has name', ->
      expect(migration.name).to.equal 'migration'

  describe '.exists', ->
    before fibrous ->
      sinon.stub StubMigrationVersion, 'findOne', ({name}, cb) ->
        cb null, if name is 'existing' then {name} else null

    after ->
      StubMigrationVersion.findOne.restore()

    it 'returns true for existing migration', fibrous ->
      expect(migrate.sync.exists 'existing').to.eql true

    it 'returns false for existing migration', fibrous ->
      expect(migrate.sync.exists 'non_existing').to.eql false

  describe '.test', ->
    migration = null

    before fibrous ->
      migration =
        name: 'migration'
        test: sinon.stub().yields()
      sinon.stub(migrate, 'get').returns migration
      migrate.sync.test('migration')

    after ->
      migrate.get.restore()

    it 'executes migration test', fibrous ->
      expect(migration.test).to.have.been.calledOnce

  describe '.one', ->
    migration = null

    before fibrous ->
      migration =
        name: 'pending_migration'
        up: sinon.stub().yields()
      sinon.stub(migrate, 'exists').yields null, false
      sinon.stub(migrate, 'get').returns migration
      sinon.stub(StubMigrationVersion, 'create').yields()
      migrate.sync.one 'pending_migration'

    after ->
      StubMigrationVersion.create.restore()
      migrate.get.restore()
      migrate.exists.restore()

    it 'calls up on migration', fibrous ->
      expect(migration.up).to.have.been.calledOnce

    it 'saves new migration', fibrous ->
      expect(StubMigrationVersion.create).to.have.been.calledWithMatch name: 'pending_migration'

  describe '.all', ->
    migration = null

    describe 'migrating all pending', ->
      before fibrous ->
        migration =
          name: 'pending_migration'
          up: sinon.stub().yields()
        sinon.stub(migrate, 'pending').yields null, ['pending_migration']
        sinon.stub(migrate, 'exists').yields null, false
        sinon.stub(migrate, 'get').returns migration
        sinon.stub(StubMigrationVersion, 'create').yields()
        migrate.sync.all()

      after ->
        StubMigrationVersion.create.restore()
        migrate.pending.restore()
        migrate.get.restore()
        migrate.exists.restore()

      it 'calls up on migration', fibrous ->
        expect(migration.up).to.have.been.calledOnce

      it 'saves new migration', fibrous ->
        expect(StubMigrationVersion.create).to.have.been.calledWithMatch name: 'pending_migration'

    describe 'migrating existing migration', ->
      before fibrous ->
        migration =
          name: 'existing_migration'
          up: sinon.stub().yields()
        sinon.stub(migrate, 'pending').yields null, ['existing_migration']
        sinon.stub(migrate, 'exists').yields null, true
        sinon.stub(migrate, 'get').returns migration
        sinon.stub migrate, 'error'
        sinon.stub(StubMigrationVersion, 'create').yields()
        migrate.sync.all()

      after ->
        StubMigrationVersion.create.restore()
        migrate.error.restore()
        migrate.pending.restore()
        migrate.get.restore()
        migrate.exists.restore()

      it 'does not call up on migration', fibrous ->
        expect(migration.up).to.not.have.been.calledOnce

      it 'does not save new migration', fibrous ->
        expect(StubMigrationVersion.create).to.not.have.been.called

      it 'calls error', fibrous ->
        expect(migrate.error).to.have.been.calledOnce

  describe '.down', ->
    {migration, version} = {}

    before fibrous ->
      migration =
        name: 'migration'
        down: sinon.stub().yields()
      sinon.stub(migrate, 'get').returns migration

      version =
        name: 'migration'
        remove: sinon.stub().yields()
      sinon.stub(StubMigrationVersion, 'findOne').yields null, version

      migrate.sync.down()

    after ->
      StubMigrationVersion.findOne.restore()
      migrate.get.restore()

    it 'calls down on the migration', fibrous ->
      expect(migration.down).to.have.been.calledOnce

    it 'removes version', fibrous ->
      expect(version.remove).to.have.been.calledOnce

  describe '.pending', ->
    {pending} = {}

    scenarioForFileExtension = (ext) ->
      before fibrous ->
        migrate2 = new Migrate {path: __dirname, ext: ext}, StubMigrationVersion
        sinon.stub(fse, 'readdir').yields null, ["migration3.#{ext}", "migration2.#{ext}", "migration1.#{ext}"]
        sinon.stub(StubMigrationVersion, 'find').yields null, [name: 'migration1']
        pending = migrate2.sync.pending()

      after ->
        fse.readdir.restore()
        StubMigrationVersion.find.restore()

      it 'returns pending migrations', fibrous ->
        expect(pending).to.eql ['migration2', 'migration3']

    describe 'coffee-script', ->
      scenarioForFileExtension 'coffee'

    describe 'javascript', ->
      scenarioForFileExtension 'js'

  describe '.generate', ->
    before fibrous ->
      sinon.stub(fse, 'mkdirp').yields()
      sinon.stub(fse, 'writeFile').yields()
      migrate.sync.generate 'filename'

    after ->
      fse.mkdirp.restore()
      fse.writeFile.restore()

    it 'generates migration file', fibrous ->
      expect(fse.writeFile).to.have.been.calledWithMatch /^.*_filename/, /.+/

