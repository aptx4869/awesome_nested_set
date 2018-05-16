# frozen_string_literal: true

require 'spec_helper'

describe 'MongoUser', type: :model do
  before :each do
    # %w(categories notes things brokens users).each do |model|
    %w(notes users).each do |model|
      fixtures = YAML.load_file "spec/fixtures/mongo_#{model}.yml"
      instance_variable_set "@#{model}", {}
      instances = instance_variable_get "@#{model}"
      model_class = "mongo_#{model}".classify.constantize
      model_class.delete_all
      collection = model_class.collection
      backup = Mongo::Collection.new collection.database, "mongo_#{model}_back"
      backup.aggregate([{ '$out': collection.name }]).to_a
      all = "mongo_#{model}".classify.constantize.all.to_a
      fixtures.each do |key, value|
        id = BSON::ObjectId(value['id'])
        instances[key.to_sym] = all.find { |i| i.id == id }
      end
    end
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
    expect([child1, child2]).to eq(MongoNote.roots.find_by(body: 'A').children.read.to_a)
  end

  describe 'hierarchical structure' do
    it 'roots_class_method' do
      found_by_us = MongoUser.where(parent_uuid: nil).to_a
      found_by_roots = MongoUser.roots.to_a
      expect(found_by_us.length).to eq(found_by_roots.length)
      found_by_us.each do |root|
        expect(found_by_roots).to include(root)
      end
    end

    it 'root_class_method' do
      expect(MongoUser.root).to eq(@users[:top_level])
    end

    it 'root' do
      expect(@users[:child_3].root).to eq(@users[:top_level])
    end

    it 'root when not persisted and parent_column_name value is self' do
      new_user = MongoUser.new
      expect(new_user.root).to eq(new_user)
    end

    it 'root?' do
      expect(@users[:top_level].root?).to be_truthy
      expect(@users[:top_level_2].root?).to be_truthy
    end

    it 'leaves_class_method' do
      expect(MongoUser.where(%(this["#{MongoUser.right_column_name}"] - this["#{MongoUser.left_column_name}"] == 1)).to_a).to eq(MongoUser.leaves.to_a)
      expect(MongoUser.leaves.count).to eq(4)
      expect(MongoUser.leaves).to include(@users[:child_1])
      expect(MongoUser.leaves).to include(@users[:child_2_1])
      expect(MongoUser.leaves).to include(@users[:child_3])
      expect(MongoUser.leaves).to include(@users[:top_level_2])
    end

    it 'leaf' do
      expect(@users[:child_1].leaf?).to be_truthy
      expect(@users[:child_2_1].leaf?).to be_truthy
      expect(@users[:child_3].leaf?).to be_truthy
      expect(@users[:top_level_2].leaf?).to be_truthy

      expect(@users[:top_level].leaf?).to be_falsey
      expect(@users[:child_2].leaf?).to be_falsey
      expect(MongoUser.new.leaf?).to be_falsey
    end

    it 'parent' do
      expect(@users[:child_2_1].parent).to eq(@users[:child_2])
    end

    it 'self_and_ancestors' do
      child = @users[:child_2_1]
      self_and_ancestors = [@users[:top_level], @users[:child_2], child]
      expect(child.self_and_ancestors).to eq(self_and_ancestors)
    end

    it 'ancestors' do
      child = @users[:child_2_1]
      ancestors = [@users[:top_level], @users[:child_2]]
      expect(ancestors).to eq(child.ancestors)
    end

    it 'self_and_siblings' do
      child = @users[:child_2]
      self_and_siblings = [@users[:child_1], child, @users[:child_3]]
      expect(self_and_siblings).to eq(child.self_and_siblings)
      expect do
        tops = [@users[:top_level], @users[:top_level_2]]
        assert_equal tops, @users[:top_level].self_and_siblings
      end.not_to raise_exception
    end

    it 'siblings' do
      child = @users[:child_2]
      siblings = [@users[:child_1], @users[:child_3]]
      expect(siblings).to eq(child.siblings)
    end

    it 'leaves' do
      leaves = [@users[:child_1], @users[:child_2_1], @users[:child_3]]
      expect(@users[:top_level].leaves).to eq(leaves)
    end
  end

  describe 'level' do
    it 'returns the correct level' do
      expect(@users[:top_level].level).to eq(0)
      expect(@users[:child_1].level).to eq(1)
      expect(@users[:child_2_1].level).to eq(2)
    end

    context 'given parent associations are loaded' do
      it 'returns the correct level' do
        child = @users[:child_1]
        if child.respond_to?(:associations)
          child.parent
          child.parent.parent
          expect(child.level).to eq(1)
        else
          skip 'associations not used where child#associations is not a method'
        end
      end
    end
  end

  describe 'depth' do
    context 'in general' do
      let(:ceo) { MongoUser.create!(name: 'CEO') }
      let(:district_manager) { MongoUser.create!(name: 'District Manager') }
      let(:store_manager) { MongoUser.create!(name: 'Store Manager') }
      let(:cashier) { MongoUser.create!(name: 'Cashier') }

      before(:each) do
        # ceo > district_manager > store_manager > cashier
        district_manager.move_to_child_of(ceo)
        store_manager.move_to_child_of(district_manager)
        cashier.move_to_child_of(store_manager)
        [ceo, district_manager, store_manager, cashier].each(&:reload)
      end

      it 'updates depth when moved into child position' do
        expect(ceo.depth).to eq(0)
        expect(district_manager.depth).to eq(1)
        expect(store_manager.depth).to eq(2)
        expect(cashier.depth).to eq(3)
      end

      it 'updates depth of all descendants when parent is moved' do
        # ceo
        # district_manager > store_manager > cashier
        district_manager.move_to_right_of(ceo)
        [ceo, district_manager, store_manager, cashier].each(&:reload)
        expect(district_manager.depth).to eq(0)
        expect(store_manager.depth).to eq(1)
        expect(cashier.depth).to eq(2)
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
    expect(@users[:child_2_1].children.empty?).to be_truthy
    expect(@users[:child_2].children.empty?).to be_falsey
    expect(@users[:top_level].children.empty?).to be_falsey
  end

  it 'self_and_descendants' do
    parent = @users[:top_level]
    self_and_descendants = [
      parent,
      @users[:child_1],
      @users[:child_2],
      @users[:child_2_1],
      @users[:child_3]
    ]
    expect(self_and_descendants).to eq(parent.self_and_descendants)
    expect(self_and_descendants.count).to eq(parent.self_and_descendants.count)
  end

  it 'descendants' do
    lawyers = MongoUser.create!(name: 'lawyers')
    us = MongoUser.create!(name: 'United States')
    us.move_to_child_of(lawyers)
    patent = MongoUser.create!(name: 'Patent Law')
    patent.move_to_child_of(us)
    lawyers.reload

    expect(lawyers.children.size).to eq(1)
    expect(us.children.size).to eq(1)
    expect(lawyers.descendants.size).to eq(2)
  end

  it 'self_and_descendants' do
    parent = @users[:top_level]
    descendants = [
      @users[:child_1],
      @users[:child_2],
      @users[:child_2_1],
      @users[:child_3]
    ]
    expect(descendants).to eq(parent.descendants)
  end

  it 'children' do
    user = @users[:top_level]
    user.children.each { |c| expect(user.uuid).to eq(c.parent_uuid) }
  end

  it 'order_of_children' do
    @users[:child_2].move_left
    @users[:top_level].reload
    @users[:child_1].reload
    @users[:child_2].reload
    @users[:child_3].reload
    expect(@users[:child_2]).to eq(@users[:top_level].sorted_children[0])
    expect(@users[:child_1]).to eq(@users[:top_level].sorted_children[1])
    expect(@users[:child_3]).to eq(@users[:top_level].sorted_children[2])
  end

  it 'is_or_is_ancestor_of?' do
    expect(@users[:top_level].is_or_is_ancestor_of?(@users[:child_1])).to be_truthy
    expect(@users[:top_level].is_or_is_ancestor_of?(@users[:child_2_1])).to be_truthy
    expect(@users[:child_2].is_or_is_ancestor_of?(@users[:child_2_1])).to be_truthy
    expect(@users[:child_2_1].is_or_is_ancestor_of?(@users[:child_2])).to be_falsey
    expect(@users[:child_1].is_or_is_ancestor_of?(@users[:child_2])).to be_falsey
    expect(@users[:child_1].is_or_is_ancestor_of?(@users[:child_1])).to be_truthy
  end

  it 'is_ancestor_of?' do
    expect(@users[:top_level].is_ancestor_of?(@users[:child_1])).to be_truthy
    expect(@users[:top_level].is_ancestor_of?(@users[:child_2_1])).to be_truthy
    expect(@users[:child_2].is_ancestor_of?(@users[:child_2_1])).to be_truthy
    expect(@users[:child_2_1].is_ancestor_of?(@users[:child_2])).to be_falsey
    expect(@users[:child_1].is_ancestor_of?(@users[:child_2])).to be_falsey
    expect(@users[:child_1].is_ancestor_of?(@users[:child_1])).to be_falsey
  end

  it 'is_or_is_ancestor_of_with_scope' do
    root = MongoScopedUser.root
    child = root.children.first
    expect(root.is_or_is_ancestor_of?(child)).to be_truthy
    child.update_attribute :organization_id, 999_999_999
    expect(root.is_or_is_ancestor_of?(child)).to be_falsey
  end

  it 'is_or_is_descendant_of?' do
    expect(@users[:child_1].is_or_is_descendant_of?(@users[:top_level])).to be_truthy
    expect(@users[:child_2_1].is_or_is_descendant_of?(@users[:top_level])).to be_truthy
    expect(@users[:child_2_1].is_or_is_descendant_of?(@users[:child_2])).to be_truthy
    expect(@users[:child_2].is_or_is_descendant_of?(@users[:child_2_1])).to be_falsey
    expect(@users[:child_2].is_or_is_descendant_of?(@users[:child_1])).to be_falsey
    expect(@users[:child_1].is_or_is_descendant_of?(@users[:child_1])).to be_truthy
  end

  it 'is_descendant_of?' do
    expect(@users[:child_1].is_descendant_of?(@users[:top_level])).to be_truthy
    expect(@users[:child_2_1].is_descendant_of?(@users[:top_level])).to be_truthy
    expect(@users[:child_2_1].is_descendant_of?(@users[:child_2])).to be_truthy
    expect(@users[:child_2].is_descendant_of?(@users[:child_2_1])).to be_falsey
    expect(@users[:child_2].is_descendant_of?(@users[:child_1])).to be_falsey
    expect(@users[:child_1].is_descendant_of?(@users[:child_1])).to be_falsey
  end

  it 'is_or_is_descendant_of_with_scope' do
    root = MongoScopedUser.root
    child = root.children.first
    expect(child.is_or_is_descendant_of?(root)).to be_truthy
    child.update_attribute :organization_id, 999_999_999
    expect(child.is_or_is_descendant_of?(root)).to be_falsey
  end

  it 'same_scope?' do
    root = MongoScopedUser.root
    child = root.children.first
    expect(child.same_scope?(root)).to be_truthy
    child.update_attribute :organization_id, 999_999_999
    expect(child.same_scope?(root)).to be_falsey
  end

  it 'left_sibling' do
    expect(@users[:child_1]).to eq(@users[:child_2].left_sibling)
    expect(@users[:child_2]).to eq(@users[:child_3].left_sibling)
  end

  it 'left_sibling_of_root' do
    expect(@users[:top_level].left_sibling).to be_nil
  end

  it 'left_sibling_without_siblings' do
    expect(@users[:child_2_1].left_sibling).to be_nil
  end

  it 'left_sibling_of_leftmost_node' do
    expect(@users[:child_1].left_sibling).to be_nil
  end

  it 'right_sibling' do
    expect(@users[:child_3]).to eq(@users[:child_2].right_sibling)
    expect(@users[:child_2]).to eq(@users[:child_1].right_sibling)
  end

  it 'right_sibling_of_root' do
    expect(@users[:top_level_2]).to eq(@users[:top_level].right_sibling)
    expect(@users[:top_level_2].right_sibling).to be_nil
  end

  it 'right_sibling_without_siblings' do
    expect(@users[:child_2_1].right_sibling).to be_nil
  end

  it 'right_sibling_of_rightmost_node' do
    expect(@users[:child_3].right_sibling).to be_nil
  end

  it 'move_left' do
    @users[:child_2].move_left
    expect(@users[:child_2].left_sibling).to be_nil
    expect(@users[:child_1]).to eq(@users[:child_2].right_sibling)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'move_right' do
    @users[:child_2].move_right
    expect(@users[:child_2].right_sibling).to be_nil
    expect(@users[:child_3]).to eq(@users[:child_2].left_sibling)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'move_to_left_of' do
    @users[:child_3].move_to_left_of(@users[:child_1])
    expect(@users[:child_3].left_sibling).to be_nil
    expect(@users[:child_1]).to eq(@users[:child_3].right_sibling)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'move_to_right_of' do
    @users[:child_1].move_to_right_of(@users[:child_3])
    expect(@users[:child_1].right_sibling).to be_nil
    expect(@users[:child_3]).to eq(@users[:child_1].left_sibling)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'move_to_root' do
    @users[:child_2].move_to_root
    expect(@users[:child_2].parent).to be_nil
    expect(@users[:child_2].level).to eq(0)
    expect(@users[:child_2_1].level).to eq(1)
    expect(@users[:child_2].left).to eq(9)
    expect(@users[:child_2].right).to eq(12)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'move_to_child_of' do
    @users[:child_1].move_to_child_of(@users[:child_3])
    expect(@users[:child_3].uuid).to eq(@users[:child_1].parent_uuid)
    expect(MongoUser.valid?).to be_truthy
  end

  describe '#move_to_child_with_index' do
    it 'move to a node without child' do
      @users[:child_1].move_to_child_with_index(@users[:child_3], 0)
      @users[:child_1].reload
      @users[:child_3].reload
      expect(@users[:child_3].uuid).to eq(@users[:child_1].parent_uuid)
      expect(@users[:child_1].left).to eq(7)
      expect(@users[:child_1].right).to eq(8)
      expect(@users[:child_3].left).to eq(6)
      expect(@users[:child_3].right).to eq(9)
      expect(MongoUser.valid?).to be_truthy
    end

    it 'move to a node to the left child' do
      @users[:child_1].move_to_child_with_index(@users[:child_2], 0)
      @users[:child_1].reload
      expect(@users[:child_1].parent_uuid).to eq(@users[:child_2].uuid)
      @users[:child_2_1].reload
      expect(@users[:child_2_1].left).to eq(5)
      expect(@users[:child_2_1].right).to eq(6)
      expect(@users[:child_1].left).to eq(3)
      expect(@users[:child_1].right).to eq(4)
      @users[:child_2].reload
      expect(@users[:child_2].left).to eq(2)
      expect(@users[:child_2].right).to eq(7)
    end

    it 'move to a node to the right child' do
      @users[:child_1].move_to_child_with_index(@users[:child_2], 1)
      expect(@users[:child_1].parent_uuid).to eq(@users[:child_2].uuid)
      @users[:child_2_1].reload
      expect(@users[:child_2_1].left).to eq(3)
      expect(@users[:child_2_1].right).to eq(4)
      expect(@users[:child_1].left).to eq(5)
      expect(@users[:child_1].right).to eq(6)
      @users[:child_2].reload
      expect(@users[:child_2].left).to eq(2)
      expect(@users[:child_2].right).to eq(7)
    end
  end

  it 'move_to_child_of_appends_to_end' do
    child = MongoUser.create! name: 'New Child'
    child.move_to_child_of @users[:top_level]
    expect(child).to eq(@users[:top_level].children.last)
  end

  it 'subtree_move_to_child_of' do
    expect(@users[:child_2].left).to eq(4)
    expect(@users[:child_2].right).to eq(7)

    expect(@users[:child_1].left).to eq(2)
    expect(@users[:child_1].right).to eq(3)

    @users[:child_2].move_to_child_of(@users[:child_1])
    expect(MongoUser.valid?).to be_truthy
    expect(@users[:child_1].uuid).to eq(@users[:child_2].parent_uuid)

    expect(@users[:child_2].left).to eq(3)
    expect(@users[:child_2].right).to eq(6)
    expect(@users[:child_1].left).to eq(2)
    expect(@users[:child_1].right).to eq(7)
  end

  it 'slightly_difficult_move_to_child_of' do
    expect(@users[:top_level_2].left).to eq(11)
    expect(@users[:top_level_2].right).to eq(12)

    # create a new top-level node and move single-node top-level tree inside it.
    new_top = MongoUser.create(name: 'New Top')
    expect(new_top.left).to eq(13)
    expect(new_top.right).to eq(14)

    @users[:top_level_2].move_to_child_of(new_top)

    expect(MongoUser.valid?).to be_truthy
    expect(new_top.uuid).to eq(@users[:top_level_2].parent_uuid)

    expect(@users[:top_level_2].left).to eq(12)
    expect(@users[:top_level_2].right).to eq(13)
    expect(new_top.left).to eq(11)
    expect(new_top.right).to eq(14)
  end

  it 'difficult_move_to_child_of' do
    expect(@users[:top_level].left).to eq(1)
    expect(@users[:top_level].right).to eq(10)
    expect(@users[:child_2_1].left).to eq(5)
    expect(@users[:child_2_1].right).to eq(6)

    # create a new top-level node and move an entire top-level tree inside it.
    new_top = MongoUser.create(name: 'New Top')
    @users[:top_level].move_to_child_of(new_top)
    @users[:child_2_1].reload
    expect(MongoUser.valid?).to be_truthy
    expect(new_top.uuid).to eq(@users[:top_level].parent_uuid)

    expect(@users[:top_level].left).to eq(4)
    expect(@users[:top_level].right).to eq(13)
    expect(@users[:child_2_1].left).to eq(8)
    expect(@users[:child_2_1].right).to eq(9)
  end

  # rebuild swaps the position of the 2 children
  # when added using move_to_child twice onto same parent
  it 'move_to_child_more_than_once_per_parent_rebuild' do
    root1 = MongoUser.create(name: 'Root1')
    root2 = MongoUser.create(name: 'Root2')
    root3 = MongoUser.create(name: 'Root3')

    root2.move_to_child_of root1
    root3.move_to_child_of root1

    output = MongoUser.roots.last.to_text
    MongoUser.update_all('&l' => nil, '&r' => nil)
    MongoUser.rebuild!

    expect(MongoUser.roots.last.to_text).to eq(output)
  end

  # doing move_to_child twice onto same parent from the furthest right first
  it 'move_to_child_more_than_once_per_parent_outside_in' do
    node1 = MongoUser.create(name: 'Node-1')
    node2 = MongoUser.create(name: 'Node-2')
    node3 = MongoUser.create(name: 'Node-3')

    node2.move_to_child_of node1
    node3.move_to_child_of node1

    output = MongoUser.roots.last.to_text
    MongoUser.update_all('&l' => nil, '&r' => nil)
    MongoUser.rebuild!

    expect(MongoUser.roots.last.to_text).to eq(output)
  end

  it 'should_move_to_ordered_child' do
    node1 = MongoUser.create(name: 'Node-1')
    node2 = MongoUser.create(name: 'Node-2')
    node3 = MongoUser.create(name: 'Node-3')

    node2.move_to_ordered_child_of(node1, 'name')

    assert_equal node1, node2.parent
    assert_equal 1, node1.children.count

    node3.move_to_ordered_child_of(node1, 'name', true) # acending

    expect(node3.parent).to eq(node1)
    expect(node1.children.count).to be(2)
    expect(node1.sorted_children[0].name).to eq(node2.name)
    expect(node1.sorted_children[1].name).to eq(node3.name)

    node3.move_to_ordered_child_of(node1, 'name', false) # decending
    node1.reload

    expect(node3.parent).to eq(node1)
    expect(node1.children.count).to be(2)
    expect(node1.sorted_children[0].name).to eq(node3.name)
    expect(node1.sorted_children[1].name).to eq(node2.name)
  end

  it 'should be able to rebuild without validating each record' do
    root1 = MongoUser.create(name: 'Root1')
    root2 = MongoUser.create(name: 'Root2')
    root3 = MongoUser.create(name: 'Root3')

    root2.move_to_child_of root1
    root3.move_to_child_of root1

    root2.name = nil
    root2.save!(validate: false)

    output = MongoUser.roots.last.to_text
    MongoUser.update_all('&l' => nil, '&r' => nil)
    MongoUser.rebuild!(false)

    expect(MongoUser.roots.last.to_text).to eq(output)
  end

  it 'valid_with_null_lefts' do
    expect(MongoUser.valid?).to be_truthy
    MongoUser.update_all('&l' => nil)
    expect(MongoUser.valid?).to be_falsey
  end

  it 'valid_with_null_rights' do
    expect(MongoUser.valid?).to be_truthy
    MongoUser.update_all('&r' => nil)
    expect(MongoUser.valid?).to be_falsey
  end

  it 'valid_with_missing_intermediate_node' do
    # Even though child_2_1 will still exist, it is a sign of a sloppy delete, not an invalid tree.
    expect(MongoUser.valid?).to be_truthy
    MongoUser.where(uuid: @users[:child_2].uuid).delete_all
    expect(MongoUser.valid?).to be_truthy
  end

  it 'valid_with_overlapping_and_rights' do
    expect(MongoUser.valid?).to be_truthy
    MongoUser.collection.find_one_and_update(
      { _id: @users[:top_level_2].id },
      '$set' => { '&l' => 0 }
    )
    expect(MongoUser.valid?).to be_falsey
  end

  it 'rebuild' do
    expect(MongoUser.valid?).to be_truthy
    before_text = MongoUser.root.to_text
    MongoUser.update_all('&l' => nil, '&r' => nil)
    MongoUser.rebuild!
    expect(MongoUser.valid?).to be_truthy
    expect(before_text).to eq(MongoUser.root.to_text)
  end

  it 'move_possible_for_sibling' do
    expect(@users[:child_2].move_possible?(@users[:child_1])).to be_truthy
  end

  it 'move_not_possible_to_self' do
    expect(@users[:top_level].move_possible?(@users[:top_level])).to be_falsey
  end

  it 'move_not_possible_to_parent' do
    @users[:top_level].descendants.each do |descendant|
      expect(@users[:top_level].move_possible?(descendant)).to be_falsey
      expect(descendant.move_possible?(@users[:top_level])).to be_truthy
    end
  end

  it 'is_or_is_ancestor_of?' do
    %i(child_1 child_2 child_2_1 child_3).each do |c|
      expect(@users[:top_level].is_or_is_ancestor_of?(@users[c])).to be_truthy
    end
    expect(@users[:top_level].is_or_is_ancestor_of?(@users[:top_level_2])).to be_falsey
  end

  it 'left_and_rights_valid_with_blank_left' do
    expect(MongoUser.left_and_rights_valid?).to be_truthy
    @users[:child_2][:'&l'] = nil
    @users[:child_2].save(validate: false)
    expect(MongoUser.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_blank_right' do
    expect(MongoUser.left_and_rights_valid?).to be_truthy
    @users[:child_2][:'&r'] = nil
    @users[:child_2].save(validate: false)
    expect(MongoUser.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_equal' do
    expect(MongoUser.left_and_rights_valid?).to be_truthy
    @users[:top_level_2][:'&l'] = @users[:top_level_2][:'&r']
    @users[:top_level_2].save(validate: false)
    expect(MongoUser.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_left_equal_to_parent' do
    expect(MongoUser.left_and_rights_valid?).to be_truthy
    MongoUser.collection.find_one_and_update(
      { _id: @users[:child_2].id },
      '$set' => { '&l' => @users[:top_level].left }
    )
    # @users[:child_2].reload
    expect(MongoUser.left_and_rights_valid?).to be_falsey
  end

  it 'left_and_rights_valid_with_right_equal_to_parent' do
    expect(MongoUser.left_and_rights_valid?).to be_truthy
    MongoUser.collection.find_one_and_update(
      { _id: @users[:child_2].id },
      '$set' => { '&r' => @users[:top_level].right }
    )
    # @users[:child_2].reload
    expect(MongoUser.left_and_rights_valid?).to be_falsey
  end

  it 'moving_dirty_objects_doesnt_invalidate_tree' do
    r1 = MongoUser.create name: 'Test 1'
    r2 = MongoUser.create name: 'Test 2'
    r3 = MongoUser.create name: 'Test 3'
    r4 = MongoUser.create name: 'Test 4'
    nodes = [r1, r2, r3, r4]

    r2.move_to_child_of(r1)
    expect(MongoUser.valid?).to be_truthy

    r3.move_to_child_of(r1)
    expect(MongoUser.valid?).to be_truthy

    r4.move_to_child_of(r2)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'delete_does_not_invalidate' do
    MongoUser.acts_as_nested_set_options[:dependent] = :delete
    @users[:child_2].destroy
    expect(MongoUser.valid?).to be_truthy
  end

  it 'destroy_does_not_invalidate' do
    MongoUser.acts_as_nested_set_options[:dependent] = :destroy
    @users[:child_2].destroy
    expect(MongoUser.valid?).to be_truthy
  end

  it 'destroy_multiple_times_does_not_invalidate' do
    MongoUser.acts_as_nested_set_options[:dependent] = :destroy
    @users[:child_2].destroy
    @users[:child_2].destroy
    expect(MongoUser.valid?).to be_truthy
  end

  it 'assigning_parent_uuid_on_create' do
    user = MongoUser.create!(name: 'Child', parent_uuid: @users[:child_2].uuid)
    expect(@users[:child_2]).to eq(user.parent)
    expect(@users[:child_2].uuid).to eq(user.parent_uuid)
    expect(user.left).not_to be_nil
    expect(user.right).not_to be_nil
    expect(MongoUser.valid?).to be_truthy
  end

  it 'assigning_parent_on_create' do
    user = MongoUser.create!(name: 'Child', parent: @users[:child_2])
    expect(@users[:child_2]).to eq(user.parent)
    expect(@users[:child_2].uuid).to eq(user.parent_uuid)
    expect(user.left).not_to be_nil
    expect(user.right).not_to be_nil
    expect(MongoUser.valid?).to be_truthy
  end

  it 'assigning_parent_uuid_to_nil_on_create' do
    user = MongoUser.create!(name: 'New Root', parent_uuid: nil)
    expect(user.parent).to be_nil
    expect(user.parent_uuid).to be_nil
    expect(user.left).not_to be_nil
    expect(user.right).not_to be_nil
    expect(MongoUser.valid?).to be_truthy
  end

  it 'assigning_parent_uuid_on_update' do
    user = @users[:child_2_1]
    user.parent_uuid = @users[:child_3].uuid
    user.save
    user.reload
    @users[:child_3].reload
    expect(@users[:child_3]).to eq(user.parent)
    expect(@users[:child_3].uuid).to eq(user.parent_uuid)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'assigning_parent_on_update' do
    user = @users[:child_2_1]
    user.parent = @users[:child_3]
    user.save
    user.reload
    @users[:child_3].reload
    expect(@users[:child_3]).to eq(user.parent)
    expect(@users[:child_3].uuid).to eq(user.parent_uuid)
    expect(MongoUser.valid?).to be_truthy
  end

  it 'assigning_parent_uuid_to_nil_on_update' do
    user = @users[:child_2_1]
    user.parent_uuid = nil
    user.save
    expect(user.parent).to be_nil
    expect(user.parent_uuid).to be_nil
    expect(MongoUser.valid?).to be_truthy
  end

  it 'creating_child_from_parent' do
    user = @users[:child_2].children.create!(name: 'Child')
    expect(@users[:child_2]).to eq(user.parent)
    expect(@users[:child_2].uuid).to eq(user.parent_uuid)
    expect(user.left).not_to be_nil
    expect(user.right).not_to be_nil
    expect(MongoUser.valid?).to be_truthy
  end

  it 'creates user when clause where provided' do
    parent = MongoUser.first

    expect do
      MongoUser.where(name: "Chris-#{Time.current.to_f}").first_or_create! do |user|
        user.parent = parent
      end
    end.to change { MongoUser.count }.by 1
  end

  def check_structure(entries, structure)
    structure = structure.dup
    MongoUser.each_with_level(entries) do |user, level|
      expected_level, expected_name = structure.shift
      expect(expected_name).to eq(user.name)
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

    check_structure(MongoUser.root.self_and_descendants, levels)

    # test some deeper structures
    user = MongoUser.find_by(name: 'Child 1')
    c1 = MongoUser.new(name: 'Child 1.1')
    c2 = MongoUser.new(name: 'Child 1.1.1')
    c3 = MongoUser.new(name: 'Child 1.1.1.1')
    c4 = MongoUser.new(name: 'Child 1.2')
    [c1, c2, c3, c4].each(&:save!)

    c1.move_to_child_of(user)
    c2.move_to_child_of(c1)
    c3.move_to_child_of(c2)
    c4.move_to_child_of(user)

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

    check_structure(MongoUser.root.self_and_descendants, levels)
  end

  describe 'before_move_callback' do
    it 'should fire the callback' do
      expect(@users[:child_2]).to receive(:custom_before_move)
      @users[:child_2].move_to_root
    end

    it 'should stop move when callback returns false' do
      MongoUser.test_allows_move = false
      expect(@users[:child_3].move_to_root).to be_falsey
      expect(@users[:child_3].root?).to be_falsey
    end

    it 'should not halt save actions' do
      MongoUser.test_allows_move = false
      @users[:child_3].parent_uuid = nil
      expect(@users[:child_3].save).to be_truthy
    end
  end

  describe 'associate_parents' do
    it 'assigns parent' do
      root = MongoUser.root
      users = root.self_and_descendants
      users = MongoUser.associate_parents users
      expect(users[1].parent).to eq users.first
    end

    it 'adds children on inverse of associations' do
      root = MongoUser.root
      users = root.self_and_descendants
      users = MongoUser.associate_parents users
      expect(users[0].children.first).to eq users[1]
    end
  end

  describe 'option dependent' do
    it 'destroy should destroy children and node' do
      MongoUser.acts_as_nested_set_options[:dependent] = :destroy
      root = MongoUser.root
      root.destroy!
      expect(MongoUser.where(uuid: root.uuid)).to be_empty
      expect(MongoUser.where(parent_uuid: root.uuid)).to be_empty
    end

    it 'delete should delete children and node' do
      MongoUser.acts_as_nested_set_options[:dependent] = :delete
      root = MongoUser.root
      root.destroy!
      expect(MongoUser.where(uuid: root.uuid)).to be_empty
      expect(MongoUser.where(parent_uuid: root.uuid)).to be_empty
    end

    describe 'restrict_with_exception' do
      it 'raises an exception' do
        MongoUser.acts_as_nested_set_options[:dependent] = :restrict_with_exception
        root = MongoUser.root
        expect { root.destroy! }.to raise_error Mongoid::Errors::DeleteRestriction
      end

      it 'deletes the leaf' do
        MongoUser.acts_as_nested_set_options[:dependent] = :restrict_with_exception
        leaf = MongoUser.last
        expect(leaf.destroy).to eq(true)
      end
    end

    describe 'restrict_with_error' do
      it 'adds the error to the parent' do
        MongoUser.acts_as_nested_set_options[:dependent] = :restrict_with_error
        root = MongoUser.root
        root.destroy
        expect(root.errors[:base]).to eq(
          ["Cannot delete Top Level because of dependent 'children'."]
        )
      end

      it 'deletes the leaf' do
        MongoUser.acts_as_nested_set_options[:dependent] = :restrict_with_error
        leaf = MongoUser.last
        expect(leaf.destroy).to eq(true)
      end
    end
  end
end
