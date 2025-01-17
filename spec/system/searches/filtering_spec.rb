require 'rails_helper'

RSpec.describe 'Filtering search results' do
  include SearchHelpers

  let!(:uk_company) { FactoryBot.create(:legal_entity) }
  let!(:australian_company) { FactoryBot.create(:legal_entity, jurisdiction_code: 'au') }
  let!(:uk_person) { FactoryBot.create(:natural_person) }
  let!(:australian_person) { FactoryBot.create(:natural_person, nationality: 'au') }

  before do
    Entity.import(force: true, refresh: true)
  end

  it 'Can filter results by entity type' do
    search_for 'Example' # Matches all people and companies

    click_link 'Person', href: %r{/search/*}
    expect(page).to have_text uk_person.name
    expect(page).to have_text australian_person.name
    expect(page).not_to have_text uk_company.name
    expect(page).not_to have_text australian_company.name

    click_link 'Remove filter'
    expect(page).to have_text uk_person.name
    expect(page).to have_text australian_person.name
    expect(page).to have_text uk_company.name
    expect(page).to have_text australian_company.name
  end

  it 'Can filter results by country' do
    search_for 'Example' # Matches all people and companies

    click_link 'Australia', href: %r{/search/*}
    expect(page).to have_text australian_company.name
    expect(page).to have_text australian_person.name
    expect(page).not_to have_text uk_person.name
    expect(page).not_to have_text uk_company.name

    click_link 'Remove filter'
    expect(page).to have_text uk_person.name
    expect(page).to have_text australian_person.name
    expect(page).to have_text uk_company.name
    expect(page).to have_text australian_company.name
  end
end
