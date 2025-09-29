# frozen_string_literal: true

require "test_helper"

class TemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @local_template = Template.create!(
      name: "Test App",
      repository: "test/app",
      xml_content: "<Container><Name>Test App</Name></Container>",
      source: "local",
    )

    @local_template_2 = Template.create!(
      name: "Another App",
      repository: "test/another",
      xml_content: "<Container><Name>Another App</Name></Container>",
      source: "local",
      description: "A test application for searching",
    )
  end

  test "should update template with not_in_community flag" do
    patch template_path(@local_template), params: {
      template: {
        not_in_community: true,
        community_repository: "test/app",
      },
    }

    assert_redirected_to @local_template
    @local_template.reload

    assert_predicate(@local_template, :not_in_community?)
  end

  test "should update template to remove not_in_community flag" do
    @local_template.update!(not_in_community: true)

    patch template_path(@local_template), params: {
      template: {
        not_in_community: false,
        community_repository: "test/app",
      },
    }

    assert_redirected_to @local_template
    @local_template.reload

    refute_predicate(@local_template, :not_in_community?)
  end

  test "should handle missing not_in_community parameter" do
    patch template_path(@local_template), params: {
      template: {
        community_repository: "test/app",
      },
    }

    assert_redirected_to @local_template
    @local_template.reload
    # Should remain false when not provided (checkbox behavior)
    refute_predicate(@local_template, :not_in_community?)
  end

  test "should get index with all templates by default" do
    get templates_path

    assert_response :success
    assert_includes response.body, @local_template.name
    assert_includes response.body, @local_template_2.name
  end

  test "should filter templates by search query" do
    get templates_path, params: { search: "Another" }

    assert_response :success
    assert_includes response.body, @local_template_2.name
    # Should not include the first template
    refute_includes response.body, "Test App"
  end

  test "should filter templates by status" do
    # Mark one template as not in community
    @local_template.update!(not_in_community: true)

    get templates_path, params: { status_filter: "not_in_community" }

    assert_response :success
    assert_includes response.body, @local_template.name
  end

  test "should combine search and status filters" do
    @local_template_2.update!(not_in_community: true)

    get templates_path, params: { search: "Another", status_filter: "not_in_community" }

    assert_response :success
    assert_includes response.body, @local_template_2.name
  end

  test "should handle sorting with filters" do
    get templates_path, params: {
      search: "App",
      sort_by: "name",
      sort_direction: "desc",
    }

    assert_response :success
    # Both templates contain "App" in their name
    assert_includes response.body, @local_template.name
    assert_includes response.body, @local_template_2.name
  end

  test "should display stats that reflect filtered results" do
    get templates_path

    assert_response :success

    # Should show stats for all templates
    assert_includes response.body, "Total Templates"
    assert_includes response.body, "Pending Reviews"
    assert_includes response.body, "Up to Date"

    # Should show the count of templates in the results text
    assert_includes response.body, "Showing 2 templates"
  end

  test "should update displayed stats when search filter is applied" do
    # Test with a search that should return one result
    get templates_path, params: { search: "Another" }

    assert_response :success

    # Should show filtered results count
    assert_includes response.body, "Showing 1 templates"
    assert_includes response.body, "(filtered)"

    # Should still show the template that matches
    assert_includes response.body, @local_template_2.name
  end

  test "should show zero count when no templates match filter" do
    get templates_path, params: { search: "nonexistent" }

    assert_response :success

    # Should show zero results
    assert_includes response.body, "Showing 0 templates"
    assert_includes response.body, "(filtered)"

    # Should show empty state message
    assert_includes response.body, "No templates match your filters"
  end
end
