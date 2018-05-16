# frozen_string_literal: true

# Enable the acts_as_nested_set method
class MongoNote
  include Mongoid::Document
  field :body, type: String
  field '&d', as: :depth, type: Integer
  field :notable_id, type: BSON::ObjectId
  field :notable_type, type: String
  acts_as_nested_set scope: %i(notable_id notable_type)

  belongs_to :user, inverse_of: :notes, class_name: 'MongoUser', required: false
end

class MongoDefaultScopedModel
  include Mongoid::Document
  field :name, type: String
  field '&d', as: :depth, type: Integer
  field :draft, type: Boolean, default: false
  acts_as_nested_set
end

class MongoDefault
  include Mongoid::Document

  store_in collection: 'mongo_categories'
  acts_as_nested_set
end

class MongoScopedCategory
  include Mongoid::Document
  store_in collection: 'mongo_categories'
  field :organization_id, type: BSON::ObjectId
  acts_as_nested_set scope: :organization
end

class MongoOrderedCategory
  include Mongoid::Document
  store_in collection: 'mongo_categories'
  acts_as_nested_set order_column: 'name'
end

class MongoRenamedColumns
  include Mongoid::Document
  field :name, type: String
  field :mother_id, type: BSON::ObjectId
  field :red, type: Integer
  field :black, type: Integer
  field :pitch, type: Integer
  acts_as_nested_set parent_column: 'mother_id',
                     left_column: 'red',
                     right_column: 'black',
                     depth_column: 'pitch'
end

class MongoCategory
  include Mongoid::Document
  field :name, type: String
  field '&d', as: :depth, type: Integer
  field :organization_id, type: BSON::ObjectId
  acts_as_nested_set

  validates_presence_of :name

  # Setup a callback that we can switch to true or false per-test
  set_callback :move, :before, :custom_before_move
  cattr_accessor :test_allows_move
  @@test_allows_move = true
  def custom_before_move
    unless @@test_allows_move
      if Rails::VERSION::MAJOR < 5
        false
      else
        throw :abort
      end
    end
  end

  def to_s
    name
  end

  def recurse(&block)
    yield self, lambda {
      children.each do |child|
        child.recurse(&block)
      end
    }
  end
end

class MongoThing
  include Mongoid::Document
  field :body, type: String
  field '&d', as: :depth, type: Integer
  field :children_count, type: Integer, default: 0
  acts_as_nested_set counter_cache: 'children_count'
end

class MongoDefaultWithCallbacks
  include Mongoid::Document
  store_in collection: 'mongo_categories'

  attr_accessor :before_add, :after_add, :before_remove, :after_remove

  acts_as_nested_set before_add: :do_before_add_stuff,
                     after_add: :do_after_add_stuff,
                     before_remove: :do_before_remove_stuff,
                     after_remove: :do_after_remove_stuff

  private

  %i(before_add after_add before_remove after_remove).each do |hook_name|
    define_method "do_#{hook_name}_stuff" do |child_node|
      send("#{hook_name}=", child_node)
    end
  end
end

class MongoBroken
  include Mongoid::Document
  field :name, type: String
  field '&d', as: :depth, type: Integer
  acts_as_nested_set
end

class MongoOrder
  include Mongoid::Document
  field :name, type: String
  field '&d', as: :depth, type: Integer
  acts_as_nested_set

  default_scope -> { order(name: 1) }
end

class MongoPosition
  include Mongoid::Document

  field :name, type: String
  field '&d', as: :depth, type: Integer
  field :position, type: Integer
  default_scope -> { order(position: 1) }
  acts_as_nested_set
end

class MongoNoDepth
  include Mongoid::Document
  field :name, type: String
  acts_as_nested_set
end

class MongoUser
  include Mongoid::Document
  include Mongoid::Timestamps

  field :uuid, type: String
  field :name, type: String
  field '&d', as: :depth, type: Integer
  field :organization_id, type: BSON::ObjectId

  acts_as_nested_set parent_column: 'parent_uuid', primary_column: 'uuid'
  validates_presence_of :name
  validates_presence_of :uuid
  validates_uniqueness_of :uuid

  after_initialize :ensure_uuid

  has_many :notes, dependent: :destroy, inverse_of: :user, class_name: 'MongoNote'

  # Setup a callback that we can switch to true or false per-test
  set_callback :move, :before, :custom_before_move
  cattr_accessor :test_allows_move
  @@test_allows_move = true
  def custom_before_move
    unless @@test_allows_move
      if Rails::VERSION::MAJOR < 5
        false
      else
        throw :abort
      end
    end
  end

  def to_s
    name
  end

  def recurse(&block)
    yield self, lambda {
      children.each do |child|
        child.recurse(&block)
      end
    }
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.hex
  end
end

class MongoScopedUser
  include Mongoid::Document
  store_in collection: 'mongo_users'
  # field :uuid, type: String
  # field :name, type: String
  # field '&d', as: :depth, type: Integer
  field :organization_id, type: BSON::ObjectId
  acts_as_nested_set parent_column: 'parent_uuid', primary_column: 'uuid', scope: :organization
end

class MongoSuperclass
  include Mongoid::Document
  store_in collection: 'single_table_inheritance'
  field :type, type: String
  field :name, type: String
  acts_as_nested_set
end

class MongoSubclass1 < MongoSuperclass
end

class MongoSubclass2 < MongoSuperclass
end
