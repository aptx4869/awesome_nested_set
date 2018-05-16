# frozen_string_literal: true

require 'spec_helper'

describe 'mongoidNestedSet' do
  before :each do
    %w(mongo_categories mongo_notes mongo_things mongo_users mongo_default_scoped_models).each do |model|
      fixtures = YAML.load_file "spec/fixtures/#{model}.yml"
      instance_variable_set "@#{model}", {}
      instances = instance_variable_get "@#{model}"
      model_class = model.classify.constantize
      model_class.delete_all
      collection = model_class.collection
      backup = Mongo::Collection.new collection.database, "#{model}_back"
      backup.aggregate([{ '$out': collection.name }]).to_a
      all = model_class.all.to_a
      fixtures.each do |key, value|
        id = BSON::ObjectId(value['id'])
        instances[key.to_sym] = all.find { |i| i.id == id }
      end
    end
  end
  describe 'defaults' do
    it 'should have left_column_default' do
      expect(MongoDefault.acts_as_nested_set_options[:left_column]).to eq(:'&l')
    end

    it 'should have right_column_default' do
      expect(MongoDefault.acts_as_nested_set_options[:right_column]).to eq(:'&r')
    end

    it 'should have parent_column_default' do
      expect(MongoDefault.acts_as_nested_set_options[:parent_column]).to eq(:'&p')
    end

    it ' should have a primary_column_default' do
      expect(MongoDefault.acts_as_nested_set_options[:primary_column]).to eq(:_id)
    end

    it 'should have scope_default' do
      expect(MongoDefault.acts_as_nested_set_options[:scope]).to be_nil
    end

    it 'should have left_column_name' do
      expect(MongoDefault.left_column_name).to eq(:'&l')
      expect(MongoDefault.new.left_column_name).to eq(:'&l')
      expect(MongoRenamedColumns.left_column_name).to eq(:red)
      expect(MongoRenamedColumns.new.left_column_name).to eq(:red)
    end

    it 'should have right_column_name' do
      expect(MongoDefault.right_column_name).to eq(:'&r')
      expect(MongoDefault.new.right_column_name).to eq(:'&r')
      expect(MongoRenamedColumns.right_column_name).to eq(:black)
      expect(MongoRenamedColumns.new.right_column_name).to eq(:black)
    end

    it 'has a depth_column_name' do
      expect(MongoDefault.depth_column_name).to eq(:'&d')
      expect(MongoDefault.new.depth_column_name).to eq(:'&d')
      expect(MongoRenamedColumns.depth_column_name).to eq(:pitch)
      expect(MongoRenamedColumns.new.depth_column_name).to eq(:pitch)
    end

    it 'should have parent_column_name' do
      expect(MongoDefault.parent_column_name).to eq(:'&p')
      expect(MongoDefault.new.parent_column_name).to eq(:'&p')
      expect(MongoRenamedColumns.parent_column_name).to eq(:mother_id)
      expect(MongoRenamedColumns.new.parent_column_name).to eq(:mother_id)
    end

    it 'should have primary_column_name' do
      expect(MongoDefault.primary_column_name).to eq(:_id)
      expect(MongoDefault.new.primary_column_name).to eq(:_id)
      expect(MongoUser.primary_column_name).to eq(:uuid)
      expect(MongoUser.new.primary_column_name).to eq(:uuid)
    end
  end

  it 'creation_with_altered_column_names' do
    expect do
      MongoRenamedColumns.create!
    end.not_to raise_exception
  end

  it 'creation when existing record has nil left column' do
    expect do
      MongoBroken.create!
    end.not_to raise_exception
  end

  describe 'quoted column names' do
    it 'quoted_left_column_name' do
      quoted = "'&l'"
      expect(MongoDefault.quoted_left_column_name).to eq(quoted)
      expect(MongoDefault.new.quoted_left_column_name).to eq(quoted)
    end

    it 'quoted_right_column_name' do
      quoted = "'&r'"
      expect(MongoDefault.quoted_right_column_name).to eq(quoted)
      expect(MongoDefault.new.quoted_right_column_name).to eq(quoted)
    end

    it 'quoted_depth_column_name' do
      quoted = "'&d'"
      expect(MongoDefault.quoted_depth_column_name).to eq(quoted)
      expect(MongoDefault.new.quoted_depth_column_name).to eq(quoted)
    end

    it 'quoted_order_column_name' do
      quoted = "'&l'"
      expect(MongoDefault.quoted_order_column_name).to eq(quoted)
      expect(MongoDefault.new.quoted_order_column_name).to eq(quoted)
    end
  end

  describe 'protected columns' do
    it 'left_column_protected_from_assignment' do
      expect do
        MongoCategory.new.set '&l' => 1
      end.to raise_exception(ActiveRecord::ActiveRecordError)
    end

    it 'right_column_protected_from_assignment' do
      expect do
        MongoCategory.new.set '&r' => 1
      end.to raise_exception(ActiveRecord::ActiveRecordError)
    end

    it 'depth_column_protected_from_assignment' do
      expect do
        MongoCategory.new.set '&d' => 1
      end.to raise_exception(ActiveRecord::ActiveRecordError)
    end
  end

  describe 'scope' do
    it 'scoped_appends_id' do
      expect(MongoScopedCategory.acts_as_nested_set_options[:scope]).to eq(:organization_id)
    end
  end

  describe 'hierarchical structure' do
    it 'roots_class_method' do
      found_by_us = MongoCategory.where('&p': nil).to_a
      found_by_roots = MongoCategory.roots.to_a
      expect(found_by_us.length).to eq(found_by_roots.length)
      found_by_us.each do |root|
        expect(found_by_roots).to include(root)
      end
    end

    it 'root_class_method' do
      expect(MongoCategory.root).to eq(@mongo_categories[:top_level])
    end

    it 'root' do
      expect(@mongo_categories[:child_3].root).to eq(@mongo_categories[:top_level])
    end

    it 'root when not persisted and parent_column_name value is self' do
      new_category = MongoCategory.new
      expect(new_category.root).to eq(new_category)
    end

    it 'root when not persisted and parent_column_name value is set' do
      last_category = MongoCategory.last
      expect(MongoCategory.new(MongoDefault.parent_column_name => last_category.id).root).to eq(last_category.root)
    end

    it 'root?' do
      expect(@mongo_categories[:top_level].root?).to be_truthy
      expect(@mongo_categories[:top_level_2].root?).to be_truthy
    end

    it 'leaves_class_method' do
      expect(
        MongoCategory
        .where(
          "this['#{MongoCategory.right_column_name}']-this['#{MongoCategory.left_column_name}']==1"
        ).to_a
      ).to eq(MongoCategory.leaves.to_a)
      expect(MongoCategory.leaves.count).to eq(4)
      expect(MongoCategory.leaves).to include(@mongo_categories[:child_1])
      expect(MongoCategory.leaves).to include(@mongo_categories[:child_2_1])
      expect(MongoCategory.leaves).to include(@mongo_categories[:child_3])
      expect(MongoCategory.leaves).to include(@mongo_categories[:top_level_2])
    end

    it 'leaf' do
      expect(@mongo_categories[:child_1].leaf?).to be_truthy
      expect(@mongo_categories[:child_2_1].leaf?).to be_truthy
      expect(@mongo_categories[:child_3].leaf?).to be_truthy
      expect(@mongo_categories[:top_level_2].leaf?).to be_truthy

      expect(@mongo_categories[:top_level].leaf?).to be_falsey
      expect(@mongo_categories[:child_2].leaf?).to be_falsey
      expect(MongoCategory.new.leaf?).to be_falsey
    end

    it 'parent' do
      expect(@mongo_categories[:child_2_1].parent).to eq(@mongo_categories[:child_2])
    end

    it 'self_and_ancestors' do
      child = @mongo_categories[:child_2_1]
      self_and_ancestors = [@mongo_categories[:top_level], @mongo_categories[:child_2], child]
      expect(child.self_and_ancestors).to eq(self_and_ancestors)
    end

    it 'ancestors' do
      child = @mongo_categories[:child_2_1]
      ancestors = [@mongo_categories[:top_level], @mongo_categories[:child_2]]
      expect(ancestors).to eq(child.ancestors)
    end

    it 'self_and_siblings' do
      child = @mongo_categories[:child_2]
      self_and_siblings = [@mongo_categories[:child_1], child, @mongo_categories[:child_3]]
      expect(self_and_siblings).to eq(child.self_and_siblings)
      expect do
        tops = [@mongo_categories[:top_level], @mongo_categories[:top_level_2]]
        assert_equal tops, @mongo_categories[:top_level].self_and_siblings
      end.not_to raise_exception
    end

    it 'siblings' do
      child = @mongo_categories[:child_2]
      siblings = [@mongo_categories[:child_1], @mongo_categories[:child_3]]
      expect(siblings).to eq(child.siblings)
    end

    it 'leaves' do
      leaves = [@mongo_categories[:child_1], @mongo_categories[:child_2_1], @mongo_categories[:child_3]]
      expect(@mongo_categories[:top_level].leaves).to eq(leaves)
    end
  end

  describe 'level' do
    it 'returns the correct level' do
      expect(@mongo_categories[:top_level].level).to eq(0)
      expect(@mongo_categories[:child_1].level).to eq(1)
      expect(@mongo_categories[:child_2_1].level).to eq(2)
    end

    context 'given parent associations are loaded' do
      it 'returns the correct level' do
        child = @mongo_categories[:child_1]
        if child.respond_to?(:associations)
          # child.association(:parent).load_target
          # child.parent.association(:parent).load_target
          expect(child.level).to eq(1)
        else
          skip 'associations not used where child#association is not a method'
        end
      end
    end
  end

  describe 'depth' do
    context 'in general' do
      let(:lawyers) { MongoCategory.create!(name: 'lawyers') }
      let(:us) { MongoCategory.create!(name: 'United States') }
      let(:new_york) { MongoCategory.create!(name: 'New York') }
      let(:patent) { MongoCategory.create!(name: 'Patent Law') }
      let(:ch) { MongoCategory.create!(name: 'Switzerland') }
      let(:bern) { MongoCategory.create!(name: 'Bern') }

      before(:each) do
        # lawyers > us > new_york > patent
        #         > ch > bern
        us.move_to_child_of(lawyers)
        new_york.move_to_child_of(us)
        patent.move_to_child_of(new_york)
        ch.move_to_child_of(lawyers)
        bern.move_to_child_of(ch)
        [lawyers, us, new_york, patent, ch, bern].each(&:reload)
      end

      it 'updates depth when moved into child position' do
        expect(lawyers.depth).to eq(0)
        expect(us.depth).to eq(1)
        expect(new_york.depth).to eq(2)
        expect(patent.depth).to eq(3)
        expect(ch.depth).to eq(1)
        expect(bern.depth).to eq(2)
      end

      it 'decreases depth of all descendants when parent is moved up' do
        # lawyers
        # us > new_york > patent
        us.move_to_right_of(lawyers)
        [lawyers, us, new_york, patent, ch, bern].each(&:reload)
        expect(us.depth).to eq(0)
        expect(new_york.depth).to eq(1)
        expect(patent.depth).to eq(2)
        expect(ch.depth).to eq(1)
        expect(bern.depth).to eq(2)
      end

      it 'keeps depth of all descendants when parent is moved right' do
        us.move_to_right_of(ch)
        [lawyers, us, new_york, patent, ch, bern].each(&:reload)
        expect(us.depth).to eq(1)
        expect(new_york.depth).to eq(2)
        expect(patent.depth).to eq(3)
        expect(ch.depth).to eq(1)
        expect(bern.depth).to eq(2)
      end

      it 'increases depth of all descendants when parent is moved down' do
        us.move_to_child_of(bern)
        [lawyers, us, new_york, patent, ch, bern].each(&:reload)
        expect(us.depth).to eq(3)
        expect(new_york.depth).to eq(4)
        expect(patent.depth).to eq(5)
        expect(ch.depth).to eq(1)
        expect(bern.depth).to eq(2)
      end
    end

    it 'is magic and does not apply when column is missing' do
      expect { MongoNoDepth.create!(name: 'shallow') }.not_to raise_error
      expect { MongoNoDepth.first.save }.not_to raise_error
      expect { MongoNoDepth.rebuild! }.not_to raise_error

      expect(MongoNoDepth.method_defined?(:depth)).to be_falsey
      expect(MongoNoDepth.first.respond_to?(:depth)).to be_falsey
    end
  end

  it 'has_children?' do
    expect(@mongo_categories[:child_2_1].children.empty?).to be_truthy
    expect(@mongo_categories[:child_2].children.empty?).to be_falsey
    expect(@mongo_categories[:top_level].children.empty?).to be_falsey
  end

  it 'self_and_descendants' do
    parent = @mongo_categories[:top_level]
    self_and_descendants = [
      parent,
      @mongo_categories[:child_1],
      @mongo_categories[:child_2],
      @mongo_categories[:child_2_1],
      @mongo_categories[:child_3]
    ]
    expect(self_and_descendants).to eq(parent.self_and_descendants)
    expect(self_and_descendants.count).to eq(parent.self_and_descendants.count)
  end

  it 'descendants' do
    lawyers = MongoCategory.create!(name: 'lawyers')
    us = MongoCategory.create!(name: 'United States')
    us.move_to_child_of(lawyers)
    patent = MongoCategory.create!(name: 'Patent Law')
    patent.move_to_child_of(us)
    lawyers.reload

    expect(lawyers.children.size).to eq(1)
    expect(us.children.size).to eq(1)
    expect(lawyers.descendants.size).to eq(2)
  end

  it 'self_and_descendants' do
    parent = @mongo_categories[:top_level]
    descendants = [
      @mongo_categories[:child_1],
      @mongo_categories[:child_2],
      @mongo_categories[:child_2_1],
      @mongo_categories[:child_3]
    ]
    expect(descendants).to eq(parent.descendants)
  end

  it 'children' do
    category = @mongo_categories[:top_level]
    category.children.each { |c| expect(category.id).to eq(c.parent_id) }
  end

  it 'order_of_children' do
    @mongo_categories[:child_2].move_left
    expect(@mongo_categories[:child_2]).to eq(@mongo_categories[:top_level].sorted_children[0])
    expect(@mongo_categories[:child_1]).to eq(@mongo_categories[:top_level].sorted_children[1])
    expect(@mongo_categories[:child_3]).to eq(@mongo_categories[:top_level].sorted_children[2])
  end

  it 'is_or_is_ancestor_of?' do
    expect(@mongo_categories[:top_level].is_or_is_ancestor_of?(@mongo_categories[:child_1])).to be_truthy
    expect(@mongo_categories[:top_level].is_or_is_ancestor_of?(@mongo_categories[:child_2_1])).to be_truthy
    expect(@mongo_categories[:child_2].is_or_is_ancestor_of?(@mongo_categories[:child_2_1])).to be_truthy
    expect(@mongo_categories[:child_2_1].is_or_is_ancestor_of?(@mongo_categories[:child_2])).to be_falsey
    expect(@mongo_categories[:child_1].is_or_is_ancestor_of?(@mongo_categories[:child_2])).to be_falsey
    expect(@mongo_categories[:child_1].is_or_is_ancestor_of?(@mongo_categories[:child_1])).to be_truthy
  end

  it 'is_ancestor_of?' do
    expect(@mongo_categories[:top_level].is_ancestor_of?(@mongo_categories[:child_1])).to be_truthy
    expect(@mongo_categories[:top_level].is_ancestor_of?(@mongo_categories[:child_2_1])).to be_truthy
    expect(@mongo_categories[:child_2].is_ancestor_of?(@mongo_categories[:child_2_1])).to be_truthy
    expect(@mongo_categories[:child_2_1].is_ancestor_of?(@mongo_categories[:child_2])).to be_falsey
    expect(@mongo_categories[:child_1].is_ancestor_of?(@mongo_categories[:child_2])).to be_falsey
    expect(@mongo_categories[:child_1].is_ancestor_of?(@mongo_categories[:child_1])).to be_falsey
  end

  it 'is_or_is_ancestor_of_with_scope' do
    root = MongoScopedCategory.root
    child = root.children.first
    expect(root.is_or_is_ancestor_of?(child)).to be_truthy
    child.update_attribute :organization_id, 999_999_999
    expect(root.is_or_is_ancestor_of?(child)).to be_falsey
  end

  it 'is_or_is_descendant_of?' do
    expect(@mongo_categories[:child_1].is_or_is_descendant_of?(@mongo_categories[:top_level])).to be_truthy
    expect(@mongo_categories[:child_2_1].is_or_is_descendant_of?(@mongo_categories[:top_level])).to be_truthy
    expect(@mongo_categories[:child_2_1].is_or_is_descendant_of?(@mongo_categories[:child_2])).to be_truthy
    expect(@mongo_categories[:child_2].is_or_is_descendant_of?(@mongo_categories[:child_2_1])).to be_falsey
    expect(@mongo_categories[:child_2].is_or_is_descendant_of?(@mongo_categories[:child_1])).to be_falsey
    expect(@mongo_categories[:child_1].is_or_is_descendant_of?(@mongo_categories[:child_1])).to be_truthy
  end

  it 'is_descendant_of?' do
    expect(@mongo_categories[:child_1].is_descendant_of?(@mongo_categories[:top_level])).to be_truthy
    expect(@mongo_categories[:child_2_1].is_descendant_of?(@mongo_categories[:top_level])).to be_truthy
    expect(@mongo_categories[:child_2_1].is_descendant_of?(@mongo_categories[:child_2])).to be_truthy
    expect(@mongo_categories[:child_2].is_descendant_of?(@mongo_categories[:child_2_1])).to be_falsey
    expect(@mongo_categories[:child_2].is_descendant_of?(@mongo_categories[:child_1])).to be_falsey
    expect(@mongo_categories[:child_1].is_descendant_of?(@mongo_categories[:child_1])).to be_falsey
  end

  it 'is_or_is_descendant_of_with_scope' do
    root = MongoScopedCategory.root
    child = root.children.first
    expect(child.is_or_is_descendant_of?(root)).to be_truthy
    child.update_attribute :organization_id, 999_999_999
    expect(child.is_or_is_descendant_of?(root)).to be_falsey
  end

  it 'same_scope?' do
    root = MongoScopedCategory.root
    child = root.children.first
    expect(child.same_scope?(root)).to be_truthy
    child.update_attribute :organization_id, 999_999_999
    expect(child.same_scope?(root)).to be_falsey
  end

  it 'left_sibling' do
    expect(@mongo_categories[:child_1]).to eq(@mongo_categories[:child_2].left_sibling)
    expect(@mongo_categories[:child_2]).to eq(@mongo_categories[:child_3].left_sibling)
  end

  it 'left_sibling_of_root' do
    expect(@mongo_categories[:top_level].left_sibling).to be_nil
  end

  it 'left_sibling_without_siblings' do
    expect(@mongo_categories[:child_2_1].left_sibling).to be_nil
  end

  it 'left_sibling_of_leftmost_node' do
    expect(@mongo_categories[:child_1].left_sibling).to be_nil
  end

  it 'right_sibling' do
    expect(@mongo_categories[:child_3]).to eq(@mongo_categories[:child_2].right_sibling)
    expect(@mongo_categories[:child_2]).to eq(@mongo_categories[:child_1].right_sibling)
  end

  it 'right_sibling_of_root' do
    expect(@mongo_categories[:top_level_2]).to eq(@mongo_categories[:top_level].right_sibling)
    expect(@mongo_categories[:top_level_2].right_sibling).to be_nil
  end

  it 'right_sibling_without_siblings' do
    expect(@mongo_categories[:child_2_1].right_sibling).to be_nil
  end

  it 'right_sibling_of_rightmost_node' do
    expect(@mongo_categories[:child_3].right_sibling).to be_nil
  end

  it 'move_left' do
    @mongo_categories[:child_2].move_left
    expect(@mongo_categories[:child_2].left_sibling).to be_nil
    expect(@mongo_categories[:child_1]).to eq(@mongo_categories[:child_2].right_sibling)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'move_right' do
    @mongo_categories[:child_2].move_right
    expect(@mongo_categories[:child_2].right_sibling).to be_nil
    expect(@mongo_categories[:child_3]).to eq(@mongo_categories[:child_2].left_sibling)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'move_to_left_of' do
    @mongo_categories[:child_3].move_to_left_of(@mongo_categories[:child_1])
    expect(@mongo_categories[:child_3].left_sibling).to be_nil
    expect(@mongo_categories[:child_1]).to eq(@mongo_categories[:child_3].right_sibling)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'move_to_right_of' do
    @mongo_categories[:child_1].move_to_right_of(@mongo_categories[:child_3])
    expect(@mongo_categories[:child_1].right_sibling).to be_nil
    expect(@mongo_categories[:child_3]).to eq(@mongo_categories[:child_1].left_sibling)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'move_to_root' do
    @mongo_categories[:child_2].move_to_root
    expect(@mongo_categories[:child_2].parent).to be_nil
    expect(@mongo_categories[:child_2].level).to eq(0)
    expect(@mongo_categories[:child_2_1].level).to eq(1)
    expect(@mongo_categories[:child_2].left).to eq(9)
    expect(@mongo_categories[:child_2].right).to eq(12)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'move_to_child_of' do
    @mongo_categories[:child_1].move_to_child_of(@mongo_categories[:child_3])
    expect(@mongo_categories[:child_3].id).to eq(@mongo_categories[:child_1].parent_id)
    expect(MongoCategory.valid?).to be_truthy
  end

  describe '#move_to_child_with_index' do
    it 'move to a node without child' do
      @mongo_categories[:child_1].move_to_child_with_index(@mongo_categories[:child_3], 0)
      expect(@mongo_categories[:child_3].id).to eq(@mongo_categories[:child_1].parent_id)
      expect(@mongo_categories[:child_1].left).to eq(7)
      expect(@mongo_categories[:child_1].right).to eq(8)
      expect(@mongo_categories[:child_3].left).to eq(6)
      expect(@mongo_categories[:child_3].right).to eq(9)
      expect(MongoCategory.valid?).to be_truthy
    end

    it 'move to a node to the left child' do
      @mongo_categories[:child_1].move_to_child_with_index(@mongo_categories[:child_2], 0)
      expect(@mongo_categories[:child_1].parent_id).to eq(@mongo_categories[:child_2].id)
      expect(@mongo_categories[:child_2_1].left).to eq(5)
      expect(@mongo_categories[:child_2_1].right).to eq(6)
      expect(@mongo_categories[:child_1].left).to eq(3)
      expect(@mongo_categories[:child_1].right).to eq(4)
      @mongo_categories[:child_2].reload
      expect(@mongo_categories[:child_2].left).to eq(2)
      expect(@mongo_categories[:child_2].right).to eq(7)
    end

    it 'move to a node to the right child' do
      @mongo_categories[:child_1].move_to_child_with_index(@mongo_categories[:child_2], 1)
      @mongo_categories[:child_2_1].reload
      @mongo_categories[:child_2].reload
      expect(@mongo_categories[:child_1].parent_id).to eq(@mongo_categories[:child_2].id)
      expect(@mongo_categories[:child_2_1].left).to eq(3)
      expect(@mongo_categories[:child_2_1].right).to eq(4)
      expect(@mongo_categories[:child_1].left).to eq(5)
      expect(@mongo_categories[:child_1].right).to eq(6)
      @mongo_categories[:child_2].reload
      expect(@mongo_categories[:child_2].left).to eq(2)
      expect(@mongo_categories[:child_2].right).to eq(7)
    end

    it 'move downward within current parent' do
      @mongo_categories[:child_1].move_to_child_with_index(@mongo_categories[:top_level], 1)
      expect(@mongo_categories[:child_1].parent_id).to eq(@mongo_categories[:top_level].id)
      expect(@mongo_categories[:child_1].left).to eq(6)
      expect(@mongo_categories[:child_1].right).to eq(7)
      @mongo_categories[:child_2].reload
      expect(@mongo_categories[:child_2].parent_id).to eq(@mongo_categories[:top_level].id)
      expect(@mongo_categories[:child_2].left).to eq(2)
      expect(@mongo_categories[:child_2].right).to eq(5)
    end

    it 'move to the same position within current parent' do
      @mongo_categories[:child_1].move_to_child_with_index(@mongo_categories[:top_level], 0)
      expect(@mongo_categories[:child_1].parent_id).to eq(@mongo_categories[:top_level].id)
      expect(@mongo_categories[:child_1].left).to eq(2)
      expect(@mongo_categories[:child_1].right).to eq(3)
    end
  end

  it 'move_to_child_of_appends_to_end' do
    child = MongoCategory.create! name: 'New Child'
    child.move_to_child_of @mongo_categories[:top_level]
    expect(child).to eq(@mongo_categories[:top_level].children.last)
  end

  it 'subtree_move_to_child_of' do
    expect(@mongo_categories[:child_2].left).to eq(4)
    expect(@mongo_categories[:child_2].right).to eq(7)

    expect(@mongo_categories[:child_1].left).to eq(2)
    expect(@mongo_categories[:child_1].right).to eq(3)

    @mongo_categories[:child_2].move_to_child_of(@mongo_categories[:child_1])
    expect(MongoCategory.valid?).to be_truthy
    expect(@mongo_categories[:child_1].id).to eq(@mongo_categories[:child_2].parent_id)

    expect(@mongo_categories[:child_2].left).to eq(3)
    expect(@mongo_categories[:child_2].right).to eq(6)
    expect(@mongo_categories[:child_1].left).to eq(2)
    expect(@mongo_categories[:child_1].right).to eq(7)
  end

  it 'slightly_difficult_move_to_child_of' do
    expect(@mongo_categories[:top_level_2].left).to eq(11)
    expect(@mongo_categories[:top_level_2].right).to eq(12)

    # create a new top-level node and move single-node top-level tree inside it.
    new_top = MongoCategory.create(name: 'New Top')
    expect(new_top.left).to eq(13)
    expect(new_top.right).to eq(14)

    @mongo_categories[:top_level_2].move_to_child_of(new_top)

    expect(MongoCategory.valid?).to be_truthy
    expect(new_top.id).to eq(@mongo_categories[:top_level_2].parent_id)

    expect(@mongo_categories[:top_level_2].left).to eq(12)
    expect(@mongo_categories[:top_level_2].right).to eq(13)
    expect(new_top.left).to eq(11)
    expect(new_top.right).to eq(14)
  end

  it 'difficult_move_to_child_of' do
    expect(@mongo_categories[:top_level].left).to eq(1)
    expect(@mongo_categories[:top_level].right).to eq(10)
    expect(@mongo_categories[:child_2_1].left).to eq(5)
    expect(@mongo_categories[:child_2_1].right).to eq(6)

    # create a new top-level node and move an entire top-level tree inside it.
    new_top = MongoCategory.create(name: 'New Top')
    @mongo_categories[:top_level].move_to_child_of(new_top)
    @mongo_categories[:child_2_1].reload
    expect(MongoCategory.valid?).to be_truthy
    expect(new_top.id).to eq(@mongo_categories[:top_level].parent_id)

    expect(@mongo_categories[:top_level].left).to eq(4)
    expect(@mongo_categories[:top_level].right).to eq(13)
    expect(@mongo_categories[:child_2_1].left).to eq(8)
    expect(@mongo_categories[:child_2_1].right).to eq(9)
  end

  # rebuild swaps the position of the 2 children when added using move_to_child twice onto same parent
  it 'move_to_child_more_than_once_per_parent_rebuild' do
    root1 = MongoCategory.create(name: 'Root1')
    root2 = MongoCategory.create(name: 'Root2')
    root3 = MongoCategory.create(name: 'Root3')

    root2.move_to_child_of root1
    root3.move_to_child_of root1

    output = MongoCategory.roots.last.to_text
    MongoCategory.update_all('&l' => nil, '&r' => nil)
    MongoCategory.rebuild!

    expect(MongoCategory.roots.last.to_text).to eq(output)
  end

  # doing move_to_child twice onto same parent from the furthest right first
  it 'move_to_child_more_than_once_per_parent_outside_in' do
    node1 = MongoCategory.create(name: 'Node-1')
    node2 = MongoCategory.create(name: 'Node-2')
    node3 = MongoCategory.create(name: 'Node-3')

    node2.move_to_child_of node1
    node3.move_to_child_of node1

    output = MongoCategory.roots.last.to_text
    MongoCategory.update_all('&l' => nil, '&r' => nil)
    MongoCategory.rebuild!

    expect(MongoCategory.roots.last.to_text).to eq(output)
  end

  it 'should_move_to_ordered_child' do
    node1 = MongoCategory.create(name: 'Node-1')
    node2 = MongoCategory.create(name: 'Node-2')
    node3 = MongoCategory.create(name: 'Node-3')

    node2.move_to_ordered_child_of(node1, 'name')

    assert_equal node1, node2.parent
    assert_equal 1, node1.children.count

    node3.move_to_ordered_child_of(node1, 'name', true) # acending

    assert_equal node1, node3.parent
    assert_equal 2, node1.children.count
    assert_equal node2.name, node1.sorted_children[0].name
    assert_equal node3.name, node1.sorted_children[1].name

    node3.move_to_ordered_child_of(node1, 'name', false) # decending
    node1.reload

    expect(node3.parent).to eq(node1)
    expect(node1.children.count).to be(2)
    expect(node1.sorted_children[0].name).to eq(node3.name)
    expect(node1.sorted_children[1].name).to eq(node2.name)
  end

  it 'should be able to rebuild without validating each record' do
    root1 = MongoCategory.create(name: 'Root1')
    root2 = MongoCategory.create(name: 'Root2')
    root3 = MongoCategory.create(name: 'Root3')

    root2.move_to_child_of root1
    root3.move_to_child_of root1

    root2.name = nil
    root2.save!(validate: false)

    output = MongoCategory.roots.last.to_text
    MongoCategory.update_all('&l' => nil, '&r' => nil)
    MongoCategory.rebuild!(false)

    expect(MongoCategory.roots.last.to_text).to eq(output)
  end

  it 'valid_with_null_lefts' do
    expect(MongoCategory.valid?).to be_truthy
    MongoCategory.update_all('&l' => nil)
    expect(MongoCategory.valid?).to be_falsey
  end

  it 'valid_with_null_rights' do
    expect(MongoCategory.valid?).to be_truthy
    MongoCategory.update_all('&r' => nil)
    expect(MongoCategory.valid?).to be_falsey
  end

  it 'valid_with_missing_intermediate_node' do
    # Even though child_2_1 will still exist, it is a sign of a sloppy delete, not an invalid tree.
    expect(MongoCategory.valid?).to be_truthy
    MongoCategory.collection.find_one_and_delete(_id: @mongo_categories[:child_2].id)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'valid_with_overlapping_and_rights' do
    expect(MongoCategory.valid?).to be_truthy
    @mongo_categories[:top_level_2]['&l'] = 0
    @mongo_categories[:top_level_2].save
    expect(MongoCategory.valid?).to be_falsey
  end

  it 'rebuild' do
    expect(MongoCategory.valid?).to be_truthy
    before_text = MongoCategory.root.to_text
    MongoCategory.update_all('&l' => nil, '&r' => nil)
    MongoCategory.rebuild!
    expect(MongoCategory.valid?).to be_truthy
    expect(before_text).to eq(MongoCategory.root.to_text)
  end

  describe '.rebuild!' do
    subject { MongoThing.rebuild! }
    before { MongoThing.update_all(children_count: 0) }

    context 'when items have children' do
      it 'updates their counter_cache' do
        expect { subject }.to change {
                                @mongo_things[:parent1].reload.children_count
                              } .to(2).from(0)
          .and change { @mongo_things[:child_2].reload.children_count }.to(1).from(0)
      end
    end

    context 'when items do not have children' do
      it "doesn't change their counter_cache" do
        subject
        expect(@mongo_things[:child_1].reload.children_count).to eq(0)
        expect(@mongo_things[:child_2_1].reload.children_count).to eq(0)
      end
    end
  end

  it 'move_possible_for_sibling' do
    expect(@mongo_categories[:child_2].move_possible?(@mongo_categories[:child_1])).to be_truthy
  end

  it 'move_not_possible_to_self' do
    expect(@mongo_categories[:top_level].move_possible?(@mongo_categories[:top_level])).to be_falsey
  end

  it 'move_not_possible_to_parent' do
    @mongo_categories[:top_level].descendants.each do |descendant|
      expect(@mongo_categories[:top_level].move_possible?(descendant)).to be_falsey
      expect(descendant.move_possible?(@mongo_categories[:top_level])).to be_truthy
    end
  end

  it 'is_or_is_ancestor_of?' do
    %i(child_1 child_2 child_2_1 child_3).each do |c|
      expect(@mongo_categories[:top_level].is_or_is_ancestor_of?(@mongo_categories[c])).to be_truthy
    end
    expect(@mongo_categories[:top_level].is_or_is_ancestor_of?(@mongo_categories[:top_level_2])).to be_falsey
  end

  it 'left_and_rights_valid_with_blank_left' do
    expect(MongoCategory.left_and_rights_valid?).to be_truthy
    @mongo_categories[:child_2][:'&l'] = nil
    @mongo_categories[:child_2].save(validate: false)
    expect(MongoCategory.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_blank_right' do
    expect(MongoCategory.left_and_rights_valid?).to be_truthy
    @mongo_categories[:child_2][:'&r'] = nil
    @mongo_categories[:child_2].save(validate: false)
    expect(MongoCategory.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_equal' do
    expect(MongoCategory.left_and_rights_valid?).to be_truthy
    @mongo_categories[:top_level_2][:'&l'] = @mongo_categories[:top_level_2][:'&r']
    @mongo_categories[:top_level_2].save(validate: false)
    expect(MongoCategory.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_left_equal_to_parent' do
    expect(MongoCategory.left_and_rights_valid?).to be_truthy
    @mongo_categories[:child_2][:'&l'] = @mongo_categories[:top_level][:'&l']
    @mongo_categories[:child_2].save(validate: false)
    expect(MongoCategory.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_right_equal_to_parent' do
    expect(MongoCategory.left_and_rights_valid?).to be_truthy
    @mongo_categories[:child_2][:'&r'] = @mongo_categories[:top_level][:'&r']
    @mongo_categories[:child_2].save(validate: false)
    expect(MongoCategory.left_and_rights_valid?).to be_falsey
  end

  it 'moving_dirty_objects_doesnt_invalidate_tree' do
    r1 = MongoCategory.create name: 'Test 1'
    r2 = MongoCategory.create name: 'Test 2'
    r3 = MongoCategory.create name: 'Test 3'
    r4 = MongoCategory.create name: 'Test 4'
    nodes = [r1, r2, r3, r4]

    r2.move_to_child_of(r1)
    expect(MongoCategory.valid?).to be_truthy

    r3.move_to_child_of(r1)
    expect(MongoCategory.valid?).to be_truthy

    r4.move_to_child_of(r2)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'multi_scoped_no_duplicates_for_columns?' do
    expect do
      MongoNote.no_duplicates_for_columns?
    end.not_to raise_exception
  end

  it 'multi_scoped_all_roots_valid?' do
    expect do
      MongoNote.all_roots_valid?
    end.not_to raise_exception
  end

  it 'multi_scoped' do
    note1 = MongoNote.create!(body: 'A', notable_id: '5ade97ee0aa0120300483259', notable_type: 'MongoCategory')
    note2 = MongoNote.create!(body: 'B', notable_id: '5ade97ee0aa0120300483259', notable_type: 'MongoCategory')
    note3 = MongoNote.create!(body: 'C', notable_id: '5ade97ee0aa0120300483259', notable_type: 'MongoDefault')

    expect([note1, note2]).to eq(note1.self_and_siblings)
    expect([note3]).to eq(note3.self_and_siblings)
  end

  it 'multi_scoped_rebuild' do
    root = MongoNote.create!(body: 'A', notable_id: '5ade97ed0aa0120300483258', notable_type: 'MongoCategory')
    child1 = MongoNote.create!(body: 'B', notable_id: '5ade97ed0aa0120300483258', notable_type: 'MongoCategory')
    child2 = MongoNote.create!(body: 'C', notable_id: '5ade97ed0aa0120300483258', notable_type: 'MongoCategory')

    child1.move_to_child_of root
    child2.move_to_child_of root

    MongoNote.update_all('&l' => nil, '&r' => nil)
    MongoNote.rebuild!

    expect(MongoNote.roots.find_by(body: 'A')).to eq(root)
    expect([child1, child2]).to eq(MongoNote.roots.find_by(body: 'A').children)
  end

  it 'same_scope_with_multi_scopes' do
    expect do
      @mongo_notes[:scope1].same_scope?(@mongo_notes[:child_1])
    end.not_to raise_exception
    expect(@mongo_notes[:scope1].same_scope?(@mongo_notes[:child_1])).to be_truthy
    expect(@mongo_notes[:child_1].same_scope?(@mongo_notes[:scope1])).to be_truthy
    expect(@mongo_notes[:scope1].same_scope?(@mongo_notes[:scope2])).to be_falsey
  end

  it 'equal_in_same_scope' do
    expect(@mongo_notes[:scope1]).to eq(@mongo_notes[:scope1])
    expect(@mongo_notes[:scope1]).not_to eq(@mongo_notes[:child_1])
  end

  it 'equal_in_different_scopes' do
    expect(@mongo_notes[:scope1]).not_to eq(@mongo_notes[:scope2])
  end

  it 'delete_does_not_invalidate' do
    MongoCategory.acts_as_nested_set_options[:dependent] = :delete
    @mongo_categories[:child_2].destroy
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'destroy_does_not_invalidate' do
    MongoCategory.acts_as_nested_set_options[:dependent] = :destroy
    @mongo_categories[:child_2].destroy
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'destroy_multiple_times_does_not_invalidate' do
    MongoCategory.acts_as_nested_set_options[:dependent] = :destroy
    @mongo_categories[:child_2].destroy
    @mongo_categories[:child_2].destroy
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'assigning_parent_id_on_create' do
    category = MongoCategory.create!(name: 'Child', '&p': @mongo_categories[:child_2].id)
    expect(@mongo_categories[:child_2]).to eq(category.parent)
    expect(@mongo_categories[:child_2].id).to eq(category.parent_id)
    expect(category.left).not_to be_nil
    expect(category.right).not_to be_nil
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'assigning_parent_on_create' do
    category = MongoCategory.create!(name: 'Child', parent: @mongo_categories[:child_2])
    expect(@mongo_categories[:child_2]).to eq(category.parent)
    expect(@mongo_categories[:child_2].id).to eq(category.parent_id)
    expect(category.left).not_to be_nil
    expect(category.right).not_to be_nil
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'assigning_parent_id_to_nil_on_create' do
    category = MongoCategory.create!(name: 'New Root', '&p': nil)
    expect(category.parent).to be_nil
    expect(category.parent_id).to be_nil
    expect(category.left).not_to be_nil
    expect(category.right).not_to be_nil
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'assigning_parent_id_on_update' do
    category = @mongo_categories[:child_2_1]
    category.parent = @mongo_categories[:child_3]
    category.save
    category.reload
    @mongo_categories[:child_3].reload
    expect(@mongo_categories[:child_3]).to eq(category.parent)
    expect(@mongo_categories[:child_3].id).to eq(category.parent_id)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'assigning_parent_on_update' do
    category = @mongo_categories[:child_2_1]
    category.parent = @mongo_categories[:child_3]
    category.save
    category.reload
    @mongo_categories[:child_3].reload
    expect(@mongo_categories[:child_3]).to eq(category.parent)
    expect(@mongo_categories[:child_3].id).to eq(category.parent_id)
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'assigning_parent_id_to_nil_on_update' do
    category = @mongo_categories[:child_2_1]
    category.parent = nil
    category.save
    expect(category.parent).to be_nil
    expect(category.parent_id).to be_nil
    expect(MongoCategory.valid?).to be_truthy
  end

  it 'creating_child_from_parent' do
    category = @mongo_categories[:child_2].children.create!(name: 'Child')
    expect(@mongo_categories[:child_2]).to eq(category.parent)
    expect(@mongo_categories[:child_2].id).to eq(category.parent_id)
    expect(category.left).not_to be_nil
    expect(category.right).not_to be_nil
    expect(MongoCategory.valid?).to be_truthy
  end

  def check_structure(entries, structure)
    structure = structure.dup
    MongoCategory.each_with_level(entries) do |category, level|
      expected_level, expected_name = structure.shift
      expect(expected_name).to eq(category.name)
      expect(expected_level).to eq(level)
    end
  end

  it 'each_with_level' do
    levels = [
      [0, 'Top Level'],
      [1, 'Child 1'],
      [1, 'Child 2'],
      [2, 'Child 2.1'],
      [1, 'Child 3']
    ]

    check_structure(MongoCategory.root.self_and_descendants, levels)

    # test some deeper structures
    category = MongoCategory.find_by(name: 'Child 1')
    c1 = MongoCategory.new(name: 'Child 1.1')
    c2 = MongoCategory.new(name: 'Child 1.1.1')
    c3 = MongoCategory.new(name: 'Child 1.1.1.1')
    c4 = MongoCategory.new(name: 'Child 1.2')
    [c1, c2, c3, c4].each(&:save!)

    c1.move_to_child_of(category)
    c2.move_to_child_of(c1)
    c3.move_to_child_of(c2)
    c4.move_to_child_of(category)

    levels = [
      [0, 'Top Level'],
      [1, 'Child 1'],
      [2, 'Child 1.1'],
      [3, 'Child 1.1.1'],
      [4, 'Child 1.1.1.1'],
      [2, 'Child 1.2'],
      [1, 'Child 2'],
      [2, 'Child 2.1'],
      [1, 'Child 3']
    ]

    check_structure(MongoCategory.root.self_and_descendants, levels)
  end

  describe 'before_move_callback' do
    it 'should fire the callback' do
      expect(@mongo_categories[:child_2]).to receive(:custom_before_move)
      @mongo_categories[:child_2].move_to_root
    end

    it 'should stop move when callback returns false' do
      MongoCategory.test_allows_move = false
      expect(@mongo_categories[:child_3].move_to_root).to be_falsey
      expect(@mongo_categories[:child_3].root?).to be_falsey
    end

    it 'should not halt save actions' do
      MongoCategory.test_allows_move = false
      @mongo_categories[:child_3].parent = nil
      expect(@mongo_categories[:child_3].save).to be_truthy
    end
  end

  describe 'counter_cache' do
    let(:parent1) { @mongo_things[:parent1] }
    let(:child_1) { @mongo_things[:child_1] }
    let(:child_2) { @mongo_things[:child_2] }
    let(:child_2_1) { @mongo_things[:child_2_1] }

    it 'should allow use of a counter cache for children' do
      expect(parent1.children_count).to eq(parent1.children.count)
    end

    it 'should increment the counter cache on create' do
      expect do
        parent1.children.create body: 'Child 3'
      end.to change { parent1.reload.children_count }.by(1)
    end

    it 'should decrement the counter cache on destroy' do
      expect do
        parent1.children.last.destroy
      end.to change { parent1.reload.children_count }.by(-1)
    end

    context 'when moving a grandchild to the root' do
      subject { child_2_1.move_to_root }

      it 'should decrement the counter cache of its parent' do
        expect { subject }.to change { child_2.reload.children_count }.by(-1)
      end
    end

    context 'when moving within a node' do
      subject { child_1.move_to_right_of(child_2) }

      it 'should not update any values' do
        expect { subject }.to_not change { parent1.reload.children_count }
      end
    end

    context 'when a child moves to another node' do
      let(:old_parent) { @mongo_things[:child_2] }
      let(:child) { @mongo_things[:child_2_1] }
      let!(:new_parent) { MongoThing.create(body: 'New Parent') }

      subject { child.move_to_child_of(new_parent) }

      it 'should decrement the counter cache of its parent' do
        expect { subject }.to change { old_parent.reload.children_count }.by(-1)
      end

      it 'should increment the counter cache of its new parent' do
        expect { subject }.to change { new_parent.reload.children_count }.by(1)
      end
    end
  end

  describe 'association callbacks on children' do
    it 'should call the appropriate callbacks on the children :has_many association ' do
      root = MongoDefaultWithCallbacks.create
      expect(root).not_to be_new_record

      child = root.children.build

      expect(root.before_add).to eq(child)
      expect(root.after_add).to  eq(child)

      expect(root.before_remove).not_to eq(child)
      expect(root.after_remove).not_to  eq(child)

      expect(child.save).to be_truthy
      expect(root.children.delete(child)).to be_truthy

      expect(root.before_remove).to eq(child)
      expect(root.after_remove).to  eq(child)
    end
  end

  describe 'rebuilding tree with a default scope ordering' do
    it "doesn't throw exception" do
      expect { MongoPosition.rebuild! }.not_to raise_error
    end
  end

  describe 'creating roots with a default scope ordering' do
    it 'assigns rgt and lft correctly' do
      MongoOrder.delete_all
      alpha = MongoOrder.create(name: 'Alpha')
      gamma = MongoOrder.create(name: 'Gamma')
      omega = MongoOrder.create(name: 'Omega')

      expect(alpha['&l']).to eq(1)
      expect(alpha['&r']).to eq(2)
      expect(gamma['&l']).to eq(3)
      expect(gamma['&r']).to eq(4)
      expect(omega['&l']).to eq(5)
      expect(omega['&r']).to eq(6)
    end
  end

  describe 'moving node from one scoped tree to another' do
    xit 'moves single node correctly' do
      root1 = MongoNote.create!(body: 'A-1', notable_id: '5ade97ef0aa012030048325a', notable_type: 'MongoCategory')
      child1_1 = MongoNote.create!(body: 'B-1', notable_id:  '5ade97ef0aa012030048325a', notable_type: 'MongoCategory')
      child1_2 = MongoNote.create!(body: 'C-1', notable_id:  '5ade97ef0aa012030048325a', notable_type: 'MongoCategory')
      child1_1.move_to_child_of root1
      child1_2.move_to_child_of root1

      root2 = MongoNote.create!(body: 'A-2', notable_id: '5ade97f00aa012030048325b', notable_type: 'MongoCategory')
      child2_1 = MongoNote.create!(body: 'B-2', notable_id: '5ade97f00aa012030048325b', notable_type: 'MongoCategory')
      child2_2 = MongoNote.create!(body: 'C-2', notable_id: '5ade97f00aa012030048325b', notable_type: 'MongoCategory')
      child2_1.move_to_child_of root2
      child2_2.move_to_child_of root2

      child1_1.update!(notable_id: '5ade97f00aa012030048325b')
      child1_1.move_to_child_of root2

      expect(root1.children).to eq([child1_2])
      expect(root2.children).to eq([child2_1, child2_2, child1_1])

      expect(MongoNote.valid?).to eq(true)
    end

    xit 'moves node with children correctly' do
      root1 = MongoNote.create!(body: 'A-1', notable_id: '5ade97ef0aa012030048325a', notable_type: 'MongoCategory')
      child1_1 = MongoNote.create!(body: 'B-1', notable_id:  '5ade97ef0aa012030048325a', notable_type: 'MongoCategory')
      child1_2 = MongoNote.create!(body: 'C-1', notable_id:  '5ade97ef0aa012030048325a', notable_type: 'MongoCategory')
      child1_1.move_to_child_of root1
      child1_2.move_to_child_of child1_1

      root2 = MongoNote.create!(body: 'A-2', notable_id: '5ade97f00aa012030048325b', notable_type: 'MongoCategory')
      child2_1 = MongoNote.create!(body: 'B-2', notable_id: '5ade97f00aa012030048325b', notable_type: 'MongoCategory')
      child2_2 = MongoNote.create!(body: 'C-2', notable_id: '5ade97f00aa012030048325b', notable_type: 'MongoCategory')
      child2_1.move_to_child_of root2
      child2_2.move_to_child_of root2

      child1_1.update!(notable_id: '5ade97f00aa012030048325b')
      child1_1.move_to_child_of root2

      expect(root1.children).to eq([])
      expect(root2.children).to eq([child2_1, child2_2, child1_1])
      child1_1.children is_expected.to eq([child1_2])
      expect(root2.siblings).to eq([child2_1, child2_2, child1_1, child1_2])

      expect(MongoNote.valid?).to eq(true)
    end
  end

  describe 'specifying custom sort column' do
    it 'should sort by the default sort column' do
      expect(MongoCategory.order_column).to eq(:'&l')
    end

    it 'should sort by custom sort column' do
      expect(MongoOrderedCategory.acts_as_nested_set_options[:order_column]).to eq('name')
      expect(MongoOrderedCategory.order_column).to eq('name')
    end
  end

  describe 'associate_parents' do
    it 'assigns parent' do
      root = MongoCategory.root
      mongo_categories = root.self_and_descendants
      mongo_categories = MongoCategory.associate_parents mongo_categories
      expect(mongo_categories[1].parent).to eq mongo_categories.first
    end

    it 'adds children on inverse of association' do
      root = MongoCategory.root
      mongo_categories = root.self_and_descendants
      mongo_categories = MongoCategory.associate_parents mongo_categories
      expect(mongo_categories[0].sorted_children.first).to eq mongo_categories[1]
    end
  end

  describe 'table inheritance' do
    it 'allows creation of a subclass pointing to a superclass' do
      subclass1 = MongoSubclass1.create(name: 'MongoSubclass1')
      MongoSubclass2.create(name: 'MongoSubclass2', '&p': subclass1.id)
    end
  end

  describe 'option dependent' do
    it 'destroy should destroy children and node' do
      MongoCategory.acts_as_nested_set_options[:dependent] = :destroy
      root = MongoCategory.root
      root.destroy!
      expect(MongoCategory.where(id: root.id)).to be_empty
      expect(MongoCategory.where('&p': root.id)).to be_empty
    end

    it "properly destroy association's objects and its children and nodes" do
      MongoCategory.acts_as_nested_set_options[:dependent] = :destroy
      user = MongoUser.first
      note_ids = user.note_ids
      user.notes.destroy_all
      expect(MongoNote.where(id: note_ids, user_id: user.id).count).to be_zero
    end

    it 'delete should delete children and node' do
      MongoCategory.acts_as_nested_set_options[:dependent] = :delete
      root = MongoCategory.root
      root.destroy!
      expect(MongoCategory.where(id: root.id)).to be_empty
      expect(MongoCategory.where('&p': root.id)).to be_empty
    end

    it 'nullify should nullify child parent IDs rather than deleting' do
      MongoCategory.acts_as_nested_set_options[:dependent] = :nullify
      root = MongoCategory.root
      child_ids = root.child_ids
      root.destroy!
      expect(MongoCategory.where(:id.in => child_ids).count).to be child_ids.length
      expect(MongoCategory.where('&p': root.id)).to be_empty
    end

    describe 'restrict_with_exception' do
      it 'raises an exception' do
        MongoCategory.acts_as_nested_set_options[:dependent] = :restrict_with_exception
        root = MongoCategory.root
        expect { root.destroy! }.to raise_error(
          Mongoid::Errors::DeleteRestriction,
          /Cannot delete MongoCategory because of dependent 'children'./
        )
      end

      it 'deletes the leaf' do
        MongoCategory.acts_as_nested_set_options[:dependent] = :restrict_with_exception
        leaf = MongoCategory.last
        expect(leaf.destroy).to eq(true)
      end
    end

    describe 'restrict_with_error' do
      it 'adds the error to the parent' do
        MongoCategory.acts_as_nested_set_options[:dependent] = :restrict_with_error
        root = MongoCategory.root
        root.destroy
        expect(root.errors[:base]).to eq(["Cannot delete Top Level because of dependent 'children'."])
      end

      it 'deletes the leaf' do
        MongoCategory.acts_as_nested_set_options[:dependent] = :restrict_with_error
        leaf = MongoCategory.last
        expect(leaf.destroy).to eq(true)
      end
    end

    describe 'model with default_scope' do
      it 'should have correct #lft & #rgt' do
        parent = MongoDefaultScopedModel.find('5ade9d920aa0127f6adb56f4')

        MongoDefaultScopedModel.default_scoping = nil
        MongoDefaultScopedModel.send(:default_scope, proc { parent.reload.self_and_descendants })

        children = parent.children.create(name: 'Helloworld')

        MongoDefaultScopedModel.unscoped do
          expect(children.is_descendant_of?(parent.reload)).to be true
        end
      end

      it 'is .all_roots_valid? even when default_scope has custom order' do
        class MongoDefaultScopedModel; default_scope -> { order('&r' => -1) }; end
        expect(MongoDefaultScopedModel.all_roots_valid?).to be_truthy
      end

      it 'is .all_roots_valid? even when uses multi scope' do
        class MongoDefaultScopedModel
          acts_as_nested_set scope: [:id]
          default_scope -> { order('&r' => -1) }
        end
        expect(MongoDefaultScopedModel.all_roots_valid?).to be_truthy
      end

      it 'should respect the default_scope' do
        MongoDefaultScopedModel.default_scoping = nil
        MongoDefaultScopedModel.send(:default_scope, -> { MongoDefaultScopedModel.where(draft: false) })

        no_parents = MongoDefaultScopedModel.find('5ade9d910aa0127f6adb56f2')

        expect(no_parents.self_and_ancestors.count).to eq(1)

        no_parents.draft = true
        no_parents.save

        other_root = MongoDefaultScopedModel.create!(name: 'Another root')
        expect(other_root.self_and_ancestors.count).to eq(1)
      end
    end
  end
end
