require "test_helper"

class ApprovalTest < ActiveSupport::TestCase
  # The scaffold fixtures in test/fixtures are stale placeholders that no longer
  # match the schema; this test builds exactly the rows it needs instead.
  self.fixture_table_names = []

  # An approval is settled either by an employee (User, which has a `name`
  # column) or by an admin acting from the admin panel (AdminUser, which has no
  # name at all - only an email). Anything labelling an approver has to cope
  # with both, so the label lives on the model rather than in each view.
  def build_approval(approver)
    Approval.new(status: "approved", position: 0, approver: approver)
  end

  test "approver_name uses the name of a User approver" do
    assert_equal "Jane Manager", build_approval(User.new(name: "Jane Manager")).approver_name
  end

  test "approver_name falls back to email for an AdminUser approver" do
    admin = AdminUser.new(email: "ali.raza@quadroots.com")
    assert_equal "ali.raza@quadroots.com", build_approval(admin).approver_name
  end

  test "approver_name falls back to email for a User with a blank name" do
    user = User.new(name: "", email: "nameless@quadroots.com")
    assert_equal "nameless@quadroots.com", build_approval(user).approver_name
  end

  test "approver_name is nil when nobody has acted" do
    assert_nil build_approval(nil).approver_name
  end
end
