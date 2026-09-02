require "test_helper"

class FixtureSanityTest < ActiveSupport::TestCase
  test "web department has task manager enabled and two executives" do
    assert departments(:web).task_manager_enabled?
    execs = User.employed.joins(:access_role)
                .where(department_id: departments(:web).id, roles: { name: "Executive" })
    assert_equal 2, execs.count
  end

  test "exec_web_b is in the department but does not report to the manager" do
    assert_equal departments(:web).id, users(:exec_web_b).department_id
    refute_includes users(:manager_web).direct_reports, users(:exec_web_b)
    assert_includes users(:manager_web).direct_reports, users(:exec_web_a)
  end
end
