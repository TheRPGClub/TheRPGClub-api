# frozen_string_literal: true

require "rails_helper"

# The acting member on the Club Codex (CodexActing) when nobody is signed
# in. Club History lets signed-out Visitors read, so any Club Codex
# endpoint may meet a request with no principal: it has no acting member,
# and an endpoint that needs one answers 401 rather than failing.
#
# No shipped endpoint asks a signed-out caller for its acting member yet,
# so this drives the concern through a probe endpoint on its own routes.
RSpec.describe "Club Codex acting member, signed out", type: :request do
  let(:probe) do
    Class.new(Api::V1::Codex::BaseController) do
      skip_before_action :require_authentication!
      before_action :require_acting_member!, only: :create

      def show = render(json: { acting_user_id: acting_user_id, member: actor.member })
      def create = render(json: { acting_user_id: acting_user_id })
      def destroy = render(json: { acting_user_id: acting_user_id })

      private

      def part = CodexEntry::HISTORY_EVENT
    end
  end

  around do |example|
    with_routing do |routes|
      routes.draw do
        get "/probe/acting", to: "api/v1/codex/acting_probe#show"
        post "/probe/acting", to: "api/v1/codex/acting_probe#create"
        delete "/probe/acting", to: "api/v1/codex/acting_probe#destroy"
      end
      example.run
    end
  end

  before do
    stub_const("Api::V1::Codex::ActingProbeController", probe)
    set_feature_flag("club_codex", "live")
  end

  it "reads a signed-out caller as a Visitor with no acting member" do
    get "/probe/acting", params: { acting_user_id: "123" }

    expect(response).to have_http_status(:ok)
    expect(json).to eq("acting_user_id" => nil, "member" => false)
  end

  it "has no acting member on a signed-out delete" do
    delete "/probe/acting", params: { acting_user_id: "123" }

    expect(response).to have_http_status(:ok)
    expect(json).to eq("acting_user_id" => nil)
  end

  it "answers 401 where an acting member is required" do
    post "/probe/acting", params: { data: { acting_user_id: "123" } }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(json).to eq("error" => "unauthorized")
  end
end
