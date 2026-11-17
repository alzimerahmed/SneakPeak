# frozen_string_literal: true

# Shared context that ensures a SneakPeak Server instance is configured
# before running tests that depend on it.
#
# Usage in specs:
#   RSpec.describe 'Feature requiring SneakPeak Server', :smoke do
#     include_context 'with SneakPeak Server instance'
#
#     it 'does something with SneakPeak Server' do
#       # Instance is guaranteed to exist
#     end
#   end
#
RSpec.shared_context 'with SneakPeak Server instance' do
  before(:all) do
    @instance_setup ||= UITest::InstanceSetup.new(@axe)
    @instance_setup.ensure_sneakpeak_server(UITest::Config.sneakpeak_server_url)
  end
end
