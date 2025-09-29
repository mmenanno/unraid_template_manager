# frozen_string_literal: true

require "test_helper"

class TemplateTest < ActiveSupport::TestCase
  test "should have default not_in_community as false" do
    template = Template.new(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
    )

    refute(template.not_in_community)
  end

  test "should validate not_in_community presence" do
    template = Template.new(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
      not_in_community: nil,
    )

    refute_predicate(template, :valid?)
    assert_includes(template.errors[:not_in_community], "is not included in the list")
  end

  test "should_sync_with_community? returns false when not_in_community is true" do
    template = Template.create!(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
      not_in_community: true,
    )

    refute_predicate(template, :should_sync_with_community?)
  end

  test "should_sync_with_community? returns true when not_in_community is false" do
    template = Template.create!(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
      not_in_community: false,
    )

    assert_predicate(template, :should_sync_with_community?)
  end

  test "should_sync_with_community? returns false for community templates" do
    template = Template.create!(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "community",
      not_in_community: false,
    )

    refute_predicate(template, :should_sync_with_community?)
  end

  test "in_community scope excludes templates marked as not in community" do
    local_template = Template.create!(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
      not_in_community: true,
    )

    refute_includes(Template.in_community, local_template)
  end

  test "not_in_community scope includes only templates marked as not in community" do
    local_template = Template.create!(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
      not_in_community: true,
    )

    assert_includes(Template.not_in_community, local_template)
  end

  test "find_or_create_comparison_with returns nil when template is marked as not in community" do
    local_template = Template.create!(
      name: "Local App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "local",
      not_in_community: true,
    )

    community_template = Template.create!(
      name: "Community App",
      repository: "test/app",
      xml_content: "<Container></Container>",
      source: "community",
    )

    result = local_template.find_or_create_comparison_with(community_template)

    assert_nil(result)
  end
end
