require 'parallel'

class UaImporter
  attr_accessor :source_url, :source_name, :document_id, :retrieved_at

  def initialize(
    source_url:, source_name:, document_id:, retrieved_at:, entity_resolver: EntityResolver.new
  )
    @entity_resolver = entity_resolver
    @source_url = source_url
    @source_name = source_name
    @document_id = document_id
    @retrieved_at = retrieved_at
  end

  def parse(file)
    queue = SizedQueue.new(100)

    Thread.abort_on_exception = true
    Thread.new do
      file.each_line do |line|
        queue << line
      end

      queue << Parallel::Stop
    end

    Parallel.each(queue, in_threads: Concurrent.processor_count) do |line|
      process(line)
    rescue Timeout::Error
      retry
    end
  end

  private

  def process(line)
    record = JSON.parse(line)

    return if !record['Is beneficial owner'] || record['Name'].blank?

    child_entity = child_entity!(record)

    parent_entity = parent_entity!(record)

    relationship!(child_entity, parent_entity, record)
  end

  def child_entity!(record)
    entity = Entity.new(
      lang_code: 'uk',
      identifiers: [
        {
          'document_id' => document_id,
          'company_number' => record['Company number'],
        },
      ],
      type: Entity::Types::LEGAL_ENTITY,
      jurisdiction_code: 'ua',
      company_number: record['Company number'],
      name: record['Company name'].presence,
      address: record['Company address'].presence,
    )

    @entity_resolver.resolve!(entity)

    entity.upsert
    index_entity(entity)
    entity
  end

  def parent_entity!(record)
    entity = Entity.new(
      lang_code: 'uk',
      identifiers: [
        {
          'document_id' => document_id,
          'company_number' => record['Company number'],
          'beneficial_owner_id' => record['Name'],
        },
      ],
      type: Entity::Types::NATURAL_PERSON,
      name: record['Name'],
      country_of_residence: record['Country of residence'].presence,
      address: record['Address of residence'].presence,
    )

    entity.upsert
    index_entity(entity)
    entity
  end

  def relationship!(child_entity, parent_entity, record)
    attributes = {
      _id: {
        'document_id' => document_id,
        'company_number' => record['Company number'],
        'beneficial_owner_id' => record['Name'],
      },
      source: parent_entity,
      target: child_entity,
      provenance: {
        source_url: source_url,
        source_name: source_name,
        retrieved_at: retrieved_at,
        imported_at: Time.now.utc,
      },
    }

    Relationship.new(attributes).upsert
  end

  def index_entity(entity)
    IndexEntityService.new(entity).index
  end
end
