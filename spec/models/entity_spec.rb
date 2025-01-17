require 'rails_helper'

RSpec.describe Entity do
  it_behaves_like "acts as entity"

  describe '.find_or_unknown' do
    subject { Entity.find_or_unknown(id) }

    context "when id is id of a normal entity" do
      let(:id) { "1234" }

      it "finds the entity" do
        expect(Entity).to receive(:find).with(id).and_return(:entity)
        expect(subject).to eq(:entity)
      end
    end

    context "when id is id of an unknown persons entity" do
      let(:id) { 'unknown-person-statement' }

      it "returns an unknown persons entity" do
        expect(subject).to be_a(UnknownPersonsEntity)
      end

      it "returns entity with same id" do
        expect(subject.id).to eq(id)
      end
    end
  end

  describe '#relationships_as_target' do
    let(:entity) { create(:legal_entity) }
    subject { entity.relationships_as_target }

    context "when entity is a Entity::Types::NATURAL_PERSON" do
      let(:entity) { create(:natural_person) }

      it "returns empty array" do
        expect(subject).to eq([])
      end
    end

    context "when entity is not a Entity::Types::NATURAL_PERSON" do
      context "when entity is target of some persisted relationships" do
        let!(:relationships) { create_list(:relationship, 3, target: entity) }

        it "returns those relationships" do
          expect(subject).to match_array(relationships)
        end
      end

      context "when entity is target of no persisted relationships" do
        it "returns an array containing a relationship to an unknown persons entity" do
          expect(subject.count).to eq(1)
          expect(subject[0].source).to eq(UnknownPersonsEntity.new_for_entity(entity))
          expect(subject[0].target).to eq(entity)
        end
      end
    end
  end

  describe '#natural_person?' do
    subject { Entity.new(type: type).natural_person? }

    context "when entity type is Entity::Types::NATURAL_PERSON" do
      let(:type) { Entity::Types::NATURAL_PERSON }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "when entity type is not Entity::Types::NATURAL_PERSON" do
      let(:type) { Entity::Types::LEGAL_ENTITY }

      it "returns false" do
        expect(subject).to be false
      end
    end
  end

  describe '#legal_entity?' do
    subject { Entity.new(type: type).legal_entity? }

    context "when entity type is Entity::Types::LEGAL_ENTITY" do
      let(:type) { Entity::Types::LEGAL_ENTITY }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "when entity type is not Entity::Types::LEGAL_ENTITY" do
      let(:type) { Entity::Types::NATURAL_PERSON }

      it "returns false" do
        expect(subject).to be false
      end
    end
  end

  describe '#country' do
    let(:entity) { Entity.new }
    subject { entity.country }

    context "when entity is a natural person" do
      before { entity.type = Entity::Types::NATURAL_PERSON }

      context "when entity does not have a nationality" do
        before { entity.nationality = nil }

        it "returns nil" do
          expect(subject).to be_nil
        end
      end

      context "when entity has a nationality" do
        before { entity.nationality = "GB" }

        it "returns country of that nationality" do
          expect(subject).to eq(ISO3166::Country[:GB])
        end
      end
    end

    context "when entity is a legal entity" do
      before { entity.type = Entity::Types::LEGAL_ENTITY }

      context "when entity does not have a jurisdiction_code" do
        before { entity.jurisdiction_code = nil }

        it "returns nil" do
          expect(subject).to be_nil
        end
      end

      context "when entity has an unknown jurisdiction_code" do
        before { entity.jurisdiction_code = "xx" }

        it "returns nil" do
          expect(subject).to be_nil
        end
      end

      context "when entity has a jurisdiction_code" do
        before { entity.jurisdiction_code = "gb" }

        it "returns country of that jurisdiction" do
          expect(subject).to eq(ISO3166::Country[:GB])
        end
      end

      context "when entity has a jurisdiction_code with subdivision" do
        before { entity.jurisdiction_code = "gb_xx" }

        it "returns country of that jurisdiction" do
          expect(subject).to eq(ISO3166::Country[:GB])
        end
      end
    end
  end

  describe '#country_subdivision' do
    let(:entity) { Entity.new }
    subject { entity.country_subdivision }

    context "when entity is a natural person" do
      before { entity.type = Entity::Types::NATURAL_PERSON }

      it "returns nil" do
        expect(subject).to be_nil
      end
    end

    context "when entity is a legal entity" do
      before { entity.type = Entity::Types::LEGAL_ENTITY }

      context "when entity does not have a country" do
        before { entity.jurisdiction_code = nil }

        it "returns nil" do
          expect(subject).to be_nil
        end
      end

      context "when entity does not have a subdivision code" do
        before { entity.jurisdiction_code = "gb" }

        it "returns nil" do
          expect(subject).to be_nil
        end
      end

      context "when entity has an unknown subdivision code" do
        before { entity.jurisdiction_code = "gb_xx" }

        it "returns nil" do
          expect(subject).to be_nil
        end
      end

      context "when entity has a known subdivision code" do
        before { entity.jurisdiction_code = "us_de" }

        it "returns subdivision" do
          expect(subject).to eq(ISO3166::Country[:US].subdivisions["DE"])
        end
      end
    end
  end

  describe '#country_code' do
    let(:entity) { Entity.new }

    subject { entity.country_code }

    context 'when the entity has a country' do
      before do
        allow(entity).to receive(:country).and_return(ISO3166::Country[:GB])
      end

      it 'returns the alpha2 code of the country' do
        expect(subject).to eq('GB')
      end
    end

    context 'when the entity does not have a country' do
      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#upsert' do
    let(:jurisdiction_code) { 'gb' }

    let(:identifier) do
      {
        'jurisdiction_code' => jurisdiction_code,
        'company_number' => '01234567',
      }
    end

    let(:name) { 'EXAMPLE LIMITED' }

    subject { Entity.new(identifiers: [identifier], name: name) }

    context 'when a document with the same identifier exists in the database' do
      before do
        @entity = Entity.create!(identifiers: [identifier], name: 'Example Limited')
      end

      it 'updates the fields of the existing document' do
        expect { subject.upsert }.to change { @entity.reload.name }.to(name)
      end

      it 'reloads the subject so it has all the fields of the existing document' do
        subject.upsert
        expect(subject).to eq @entity.reload
      end

      it 'does not create a new document' do
        expect { subject.upsert }.not_to change { Entity.count }
      end

      it 'sets the updated_at' do
        expect { subject.upsert }.to change { @entity.reload.updated_at }
      end

      it 'sets the self_updated_at' do
        expect { subject.upsert }.to change { @entity.reload.self_updated_at }
      end

      context "when the new document has multiple identifiers" do
        let(:other_identifier) { { 'a' => 'b' } }
        before do
          subject.identifiers << other_identifier
        end

        it "matches existing document with any of them" do
          @entity.set(identifiers: [identifier])
          subject.upsert
          expect(@entity.reload.identifiers).to match_array(
            [
              identifier,
              other_identifier,
            ],
          )

          @entity.set(identifiers: [other_identifier])
          subject.upsert
          expect(@entity.reload.identifiers).to match_array(
            [
              identifier,
              other_identifier,
            ],
          )
        end

        context "when a second document with one of the other identifiers exists in the database" do
          before do
            Entity.create!(identifiers: [other_identifier])
          end

          it "raises an exception mentioning the identifiers" do
            expect { subject.upsert }.to raise_error(DuplicateEntitiesDetected, /#{subject.identifiers}/)
          end
        end
      end

      context "when the existing document also has other identifiers" do
        let(:other_identifier) { { 'a' => 'b' } }
        before do
          @entity.identifiers << other_identifier
          @entity.save!
        end

        it "keeps both identifiers" do
          subject.upsert

          expect(@entity.reload.identifiers).to match_array(
            [
              identifier,
              other_identifier,
            ],
          )
        end
      end

      context "when the existing document is a merged person" do
        let!(:person) { create(:natural_person) }
        let!(:merged_person) { create(:natural_person, master_entity: person) }

        subject do
          Entity.new(identifiers: merged_person.identifiers, name: 'Upserted Person')
        end

        it "doesn't overwrite the master entity in the merged person" do
          expect { subject.upsert }.not_to change { merged_person.master_entity_id }
        end

        it "doesn't change the master entity's merged_entities_count" do
          expect(person.merged_entities_count).to eq(1)
          subject.upsert
          expect(person.reload.merged_entities_count).to eq(1)
        end
      end

      context "when the existing document is a master_entity" do
        let!(:person) { create(:natural_person) }
        let!(:merged_person) { create(:natural_person, master_entity: person) }

        subject do
          Entity.new(identifiers: person.identifiers, name: 'Upserted Person')
        end

        it "doesn't change the entity's merged_entities_count" do
          expect(person.merged_entities_count).to eq(1)
          subject.upsert
          expect(person.reload.merged_entities_count).to eq(1)
        end
      end
    end

    context 'when no document with the same identifier exists in the database' do
      it 'creates a new document' do
        expect { subject.upsert }.to change { Entity.count }.from(0).to(1)
      end

      it 'sets #new_record to false' do
        entity = subject
        expect(entity.new_record?).to eq(true)
        entity.upsert
        expect(entity.new_record?).to eq(false)
      end

      it 'sets updated_at on the new entity' do
        subject.upsert
        expect(Entity.first.updated_at).not_to be_nil
      end
    end

    it 'retries on duplicate key error exceptions' do
      # The findAndModify command is atomic but can potentially fail
      # due to unique index constraint violation, as documented here:
      # https://docs.mongodb.com/manual/reference/command/findAndModify/#upsert-and-unique-index

      collection = subject.collection

      allow(subject).to receive(:collection).and_return(collection)

      error = Mongo::Error::OperationFailure.new('E11000 duplicate key error collection: ...')

      expect(collection).to receive(:find_one_and_update).and_raise(error)
      expect(collection).to receive(:find_one_and_update).and_call_original

      subject.upsert
    end
  end

  describe '#upsert_and_merge_duplicates!' do
    let(:oc_identifier) { { jurisdiction_code: 'gb', company_number: '12345' } }
    let(:new_entity) { build(:legal_entity, identifiers: [oc_identifier]) }

    context 'when there are no duplicates' do
      it 'does a normal upsert' do
        expect { new_entity.upsert }.to change { Entity.count }.by(1)
      end
    end

    context 'when a duplicate Entity exists in the db already' do
      let!(:existing_entity) { create(:legal_entity, identifiers: [oc_identifier]) }

      it 'merges the two entities together and upserts the existing entity' do
        expect { new_entity.upsert }.not_to change { Entity.count }
        expect(new_entity.reload).to eq existing_entity.reload
      end
    end
  end

  describe '#with_identifiers scope' do
    let(:identifier1) { { a: 'b', c: 'd' } }

    let(:identifier2) { { e: 'f' } }

    let!(:entity) do
      create :legal_entity, identifiers: [identifier1, identifier2]
    end

    it 'should find the entity with an expected identifier' do
      expect(Entity.with_identifiers([identifier1]).first).to eq entity
    end

    it 'should find the entity with an expected identifier' do
      expect(Entity.with_identifiers([identifier2]).first).to eq entity
    end

    it 'should not find any entities with a partially matched identifier' do
      i = { c: 'd' }
      expect(Entity.with_identifiers([i]).first).to be nil
    end

    it 'should not find any entities with an unknown identifier' do
      i = { foo: 'unknown' }
      expect(Entity.with_identifiers([i]).first).to be nil
    end
  end

  describe '#oc_identifier' do
    subject { build :legal_entity }

    let(:data) do
      {
        jurisdiction_code: 'gb',
        company_number: 1234,
      }
    end

    context 'when the entity has an OC identifier added to it' do
      before do
        subject.add_oc_identifier(data)
      end

      it 'returns the identifier as unexpected' do
        expect(subject.oc_identifier).to eq(
          'jurisdiction_code' => 'gb',
          'company_number' => 1234,
        )
      end
    end

    context 'when the entity does not have an OC identifier' do
      before do
        subject.identifiers << { 'foo' => 1, 'bar' => 'abc' }
      end

      it 'returns nil' do
        expect(subject.oc_identifier).to be nil
      end
    end

    context 'when the entity has an OC identifier but with keys in reverse order' do
      before do
        subject.identifiers << {
          'company_number' => 1234,
          'jurisdiction_code' => 'gb',
        }
      end

      it 'still returns this as an OC identifier, for backwards compatibility' do
        expect(subject.oc_identifier).to eq(
          'company_number' => 1234,
          'jurisdiction_code' => 'gb',
        )
      end
    end
  end

  describe '.import' do
    let!(:person) { create(:natural_person, name: 'John Smith') }
    let!(:merged_person) do
      create(:natural_person, master_entity: person, name: 'Jane Jones')
    end

    it 'indexes records with elasticsearch' do
      Entity.import force: true, refresh: true
      expect(Entity.search(person.name).records.first).to eq(person)
    end

    it 'excludes merged people by default' do
      Entity.import force: true, refresh: true
      expect(Entity.search(merged_person.name)).to be_empty
    end

    it "doesn't override if the :scope option is passed" do
      Entity.import force: true, refresh: true, scope: :unscoped
      expect(Entity.search(merged_person.name).records.first).to eq(merged_person)
    end

    it "doesn't override if the :query option is passed" do
      Entity.import(
        force: true,
        refresh: true,
        query: -> { where('master_entity.ne' => nil) },
      )
      expect(Entity.search(merged_person.name).records.first).to eq(merged_person)
    end
  end

  describe '#all_ids' do
    context 'when the entity has no merged entities' do
      let(:entity) { create(:natural_person) }

      it 'returns an array with the entity id in it' do
        expect(entity.all_ids).to eq([entity.id])
      end
    end

    context 'when the entity has merged entities' do
      let(:entity) { create(:natural_person) }
      let(:merged_entity1) { create(:natural_person, master_entity: entity) }
      let(:merged_entity2) { create(:natural_person, master_entity: entity) }

      it 'returns an array with the entity id and its merged entity ids in it' do
        expected = [
          entity.id,
          merged_entity1.id,
          merged_entity2.id,
        ]
        expect(entity.all_ids).to match_array(expected)
      end
    end
  end
end
