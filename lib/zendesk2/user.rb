# frozen_string_literal: true
class Zendesk2::User
  include Zendesk2::Model

  extend Zendesk2::Attributes

  # @return [Integer] Automatically assigned when creating users
  identity :id, type: :integer

  # @return [Boolean] Users that have been deleted will have the value false here
  attribute :active, type: :boolean
  # @return [String] Agents can have an alias that is displayed to end-users
  attribute :alias, type: :string
  # @return [Time] The time the user was created
  attribute :created_at, type: :time
  # @return [Integer] A custom role on the user if the user is an agent on the entreprise plan
  attribute :custom_role_id, type: :integer
  # @return [String] In this field you can store any details obout the user. e.g. the address
  attribute :details, type: :string
  # @return [String] The primary email address of this user
  attribute :email, type: :string
  # @return [String] A unique id you can set on a user
  attribute :external_id, type: :string
  # @return [Array] Array of user identities (e.g. email and Twitter) associated with this user. See User Identities
  attribute :identities, type: :array
  # @return [Time] A time-stamp of the last time this user logged in to Zendesk
  attribute :last_login_at, type: :time
  # @return [Integer] The language identifier for this user
  attribute :locale_id, type: :integer
  # @return [Boolean] Designates whether this user has forum moderation capabilities
  attribute :moderator, type: :boolean
  # @return [String] The name of the user
  attribute :name, type: :string
  # @return [String] In this field you can store any notes you have about the user
  attribute :notes, type: :string
  # @return [Boolean] true if this user only can create private comments
  attribute :only_private_comments, type: :boolean
  # @return [Integer] The id of the organization this user is associated with
  attribute :organization_id, type: :integer
  # @return [String] The primary phone number of this user
  attribute :phone, type: :string
  # @return [Attachment] The user's profile picture represented as an Attachment object
  attribute :photo, type: :Attachment
  # @return [String] The role of the user. Possible values: "end-user", "agent", "admin"
  attribute :role, type: :string
  # @return [Boolean] If this user is shared from a different Zendesk, ticket sharing accounts only
  attribute :shared, type: :boolean
  # @return [String] The signature of this user. Only agents and admins can have signatures
  attribute :signature, type: :string
  # @return [Boolean] Tickets from suspended users are also suspended, and these users cannot log in to the end-user
  #   portal
  attribute :suspended, type: :boolean
  # @return [Array] The tags of the user. Only present if your account has user tagging enabled
  attribute :tags, type: :array
  # @return [String] Specified which tickets this user has access to.
  #   Possible values are: "organization", "groups", "assigned", "requested", null
  attribute :ticket_restriction, type: :string
  # @return [String] The time-zone of this user
  attribute :time_zone, type: :string
  # @return [Time] The time of the last update of the user
  attribute :updated_at, type: :time
  # @return [String] The API url of this user
  attribute :url, type: :string
  # @return [Hash] Custom fields for the user
  attribute :user_fields
  # @return [Boolean] Zendesk has verified that this user is who he says he is
  attribute :verified, type: :boolean

  attr_accessor :errors
  assoc_accessor :organization

  def save!
    data = if new_record?
             requires :name, :email

             cistern.create_user('user' => attributes)
           else
             requires :identity

             cistern.update_user('user' => attributes)
           end.body['user']

    merge_attributes(data)
  end

  def destroy!
    requires :identity

    raise "don't nuke yourself" if email == cistern.username

    merge_attributes(
      cistern.destroy_user('user' => { 'id' => identity }).body['user']
    )
  end

  def destroyed?
    !reload || !active
  end

  # @param [Time] timestamp time sent with intial handshake
  # @option options [String] :return_to (nil) url to return to after handshake
  # @return [String] remote authentication login url
  # Using this method requires you to implement the additional (user-defined) /handshake endpoint
  # @see http://www.zendesk.com/support/api/remote-authentication
  def login_url(timestamp, options = {})
    requires :name, :email

    return_to = options[:return_to]
    token     = cistern.token || options[:token]

    uri      = URI.parse(cistern.url)
    uri.path = '/access/remote'

    raise 'timestamp cannot be nil' unless timestamp

    hash_str = "#{name}#{email}#{token}#{timestamp}"
    query_values = {
      'name'      => name,
      'email'     => email,
      'timestamp' => timestamp,
      'hash'      => Digest::MD5.hexdigest(hash_str),
    }

    query_values['return_to'] = return_to unless Zendesk2.blank?(return_to)

    uri.query = Faraday::NestedParamsEncoder.encode(query_values)

    uri.to_s
  end

  # @option options [String] :return_to (nil) url to return to after initial auth
  # @return [String] url to redirect your user's browser to for login
  # @see https://support.zendesk.com/entries/23675367-Setting-up-single-sign-on-with-JWT-JSON-Web-Token-
  # Cargo-culted from: https://github.com/zendesk/zendesk_jwt_sso_examples/blob/master/ruby_on_rails_jwt.rb
  def jwt_login_url(options = {})
    requires :name, :email

    return_to = options[:return_to]
    jwt_token = cistern.jwt_token || options[:jwt_token]

    uri       = URI.parse(cistern.url)
    uri.path  = '/access/jwt'

    iat = Time.now.to_i
    jti = "#{iat}/#{rand(36**64).to_s(36)}"
    payload = JWT.encode({
                           iat: iat, # Seconds since epoch, determine when this token is stale
                           jti: jti, # Unique token id, helps prevent replay attacks
                           name: name,
                           email: email,
                         }, jwt_token)

    query_values = {
      'jwt' => payload,
    }
    query_values['return_to'] = return_to unless Zendesk2.blank?(return_to)

    uri.query = Faraday::NestedParamsEncoder.encode(query_values)

    uri.to_s
  end

  # @return [Zendesk2::Tickets] tickets this user requested
  def tickets
    requires :identity

    cistern.tickets(requester_id: identity)
  end
  alias requested_tickets tickets

  # @return [Zendesk2::Tickets] tickets this user is CC'd
  def ccd_tickets
    requires :identity

    cistern.tickets(collaborator_id: identity)
  end

  # @return [Zendesk2::UserIdentities] the identities of this user
  def identities
    cistern.user_identities('user_id' => identity)
  end

  # @return [Zendesk2::Memberships] the organization memberships of this user
  def memberships
    cistern.memberships(user: self)
  end

  # @return [Zendesk2::Organizations] the organizations of this user through memberships
  def organizations
    cistern.organizations(user: self)
  end

  # @return [Zendesk2::HelpCenter::Subscriptions] subscriptions
  def subscriptions
    requires :identity

    cistern.help_center_subscriptions(user_id: identity)
  end

  # @return [Zendesk2::HelpCenter::Post] authored posts
  def posts
    requires :identity

    cistern.help_center_posts(user_id: identity)
  end
end
