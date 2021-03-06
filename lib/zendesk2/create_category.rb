# frozen_string_literal: true
class Zendesk2::CreateCategory
  include Zendesk2::Request

  request_method :post
  request_path { |_| '/categories.json' }
  request_body { |r| { 'category' => r.params['category'] } }

  def self.accepted_attributes
    %w(id name description position)
  end

  def mock
    identity = cistern.serial_id

    record = {
      'id'         => identity,
      'url'        => url_for("/categories/#{identity}.json"),
      'created_at' => timestamp,
      'updated_at' => timestamp,
    }.merge(Cistern::Hash.slice(params.fetch('category'), *self.class.accepted_attributes))

    cistern.data[:categories][identity] = record

    mock_response({ 'category' => record }, { status: 201 })
  end
end
