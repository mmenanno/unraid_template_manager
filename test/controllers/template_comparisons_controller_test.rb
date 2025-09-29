# frozen_string_literal: true

require "test_helper"

class TemplateComparisonsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @local_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest",
      network: "bridge",
      webui: "http://[IP]:[PORT:8200]",
      xml_content: <<~XML,
        <?xml version="1.0"?>
        <Container version="2">
          <Name>duplicati</Name>
          <Repository>lscr.io/linuxserver/duplicati:latest</Repository>
          <Network>bridge</Network>
          <WebUI>http://[IP]:[PORT:8200]</WebUI>
        </Container>
      XML
      source: "local",
    )

    @community_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest-community",
      network: "host",
      webui: "http://[IP]:[PORT:8200]/web",
      xml_content: <<~XML,
        <?xml version="1.0"?>
        <Container version="2">
          <Name>duplicati</Name>
          <Repository>lscr.io/linuxserver/duplicati:latest-community</Repository>
          <Network>host</Network>
          <WebUI>http://[IP]:[PORT:8200]/web</WebUI>
        </Container>
      XML
      source: "community",
    )

    @comparison = TemplateComparison.create!(
      local_template: @local_template,
      community_template: @community_template,
      status: "pending",
    )

    @comparison.calculate_differences!
  end

  test "should update comparison with user choices and manual edits" do
    patch template_comparison_path(@comparison), params: {
      template_comparison: {
        "network" => "community",
        "webui" => "community",
      },
      manual_edits: {
        "network" => "custom_network",
        "webui" => "http://[IP]:[PORT:8300]/custom",
      },
    }

    assert_redirected_to @comparison
    @comparison.reload

    assert_equal("reviewed", @comparison.status)
    assert_equal("community", @comparison.user_choices["network"])
    assert_equal("community", @comparison.user_choices["webui"])
    assert_equal("custom_network", @comparison.manual_edits["network"])
    assert_equal("http://[IP]:[PORT:8300]/custom", @comparison.manual_edits["webui"])
  end

  test "should show comparison with manual edits" do
    @comparison.update!(
      manual_edits: { "network" => "custom_network" },
    )

    get template_comparison_path(@comparison)

    assert_response(:success)
    assert_includes(response.body, "custom_network")
  end

  test "should permit manual edits for existing differences" do
    controller = TemplateComparisonsController.new
    controller.instance_variable_set(:@comparison, @comparison)

    # Mock params
    params = ActionController::Parameters.new({
      manual_edits: {
        "network" => "custom_network",
        "webui" => "custom_webui",
        "invalid_field" => "should_not_be_permitted",
      },
    })
    controller.stubs(:params).returns(params)

    permitted_edits = controller.send(:permitted_manual_edits)

    assert_equal("custom_network", permitted_edits["network"])
    assert_equal("custom_webui", permitted_edits["webui"])
    refute_includes(permitted_edits.keys, "invalid_field")
  end
end
